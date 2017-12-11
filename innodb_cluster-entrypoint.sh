#!/bin/bash
set -e


# if command starts with an option, save them as CMD arguments
if [ "${1:0:1}" = '-' ]; then
        ARGS="$@"
fi

# If the password variable is a filename we use the contents of the file
if [ -n "$MYSQL_ROOT_PASSWORD" -a -f "$MYSQL_ROOT_PASSWORD" ]; then
	MYSQL_ROOT_PASSWORD="$(cat $MYSQL_ROOT_PASSWORD)"
fi

# If we're setting up a router 
if [ "$NODE_TYPE" = 'router' ]; then

        echo 'Setting up a new router instance...'

        # we need to ensure that they've specified a boostrap URI 
        if [ -z "$MYSQL_HOST" -a -z "$MYSQL_PASSWORD" ]; then
                echo >&2 'error: You must specify a value for MYSQL_HOST and MYSQL_PASSWORD (MYSQL_USER=root is the default) when setting up a router'
                exit 1
        fi

        if [ -z "$MYSQL_PORT" ]; then
		MYSQL_PORT="3306"
	fi

        if [ -z "$MYSQL_USER" ]; then
		MYSQL_USER="root"
	fi

	if [ -z "$CLUSTER_NAME" ]; then
		CLUSTER_NAME="testcluster"
	fi

        # We'll use the hostname as the router instance name
	HOSTNAME=$(hostname)

        # first we need to see if the cluster metadata already exists 
	set +e
        metadata_exists=$(mysqlsh --uri="$MYSQL_USER"@"$MYSQL_HOST":"$MYSQL_PORT" -p"$MYSQL_ROOT_PASSWORD" --no-wizard --js -i -e "dba.getCluster( '${CLUSTER_NAME}' )" 2>&1 | grep "<Cluster:$CLUSTER_NAME>")
        set -e

	# We need to get the host:port combination for the primary node (or just the first node when NOT in single primary mode)
        HOSTPORT=$(mysql --no-defaults -h "$MYSQL_HOST" -P"$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" -nsLNE -e "select CONCAT(member_host, ':', member_port) as primary_host from performance_schema.replication_group_members where member_state='ONLINE' and member_id=(IF((select @grpm:=variable_value from performance_schema.global_status where variable_name='group_replication_primary_member') = '', member_id, @grpm)) limit 1" 2>/dev/null | grep -v '*')

        if [ -z "$metadata_exists" ]; then
		# Then let's create the innodb cluster metadata 
		output=$(mysqlsh --uri="$MYSQL_USER"@"$HOSTPORT" -p"$MYSQL_ROOT_PASSWORD" --no-wizard --js -i -e "dba.createCluster('${CLUSTER_NAME}', {adoptFromGR: true})")
	fi

        output=$(echo "$MYSQL_ROOT_PASSWORD" | mysqlrouter --bootstrap="$MYSQL_USER"@"$HOSTPORT" --user=mysql --name "$HOSTNAME" --force)

        if [ ! "$?" = "0" ]; then
		echo >&2 'error: could not bootstrap router:'
		echo >&2 "$output"
		exit 1
	fi
       
        # bug (?) in Router 2.1.3 didn't set file permissions based on --user value 
	chown -R mysql:mysql "/var/lib/mysqlrouter"

        # now that we've bootstrapped the setup, let's start the process
        CMD="mysqlrouter --user=mysql"

# Let's setup a mysql server instance normally 
else
	if [ -z "$BOOTSTRAP" -a -z "$GROUP_NAME" ]; then 
		echo >&2 'error: You must either use BOOTSTRAP=1 to start a new cluster--where a new group name UUID will be generated--or you must specify a valid UUID for the GROUP_NAME that you wish to join'
	        exit 1
	fi

        # let's generate a random server_id value; it can be any unsigned 32 bit int
        [ -z "$SERVER_ID" ] && SERVER_ID=$((RANDOM % 1000))

        CMD="mysqld"

        # We'll use this variable to manage the mysqld args 
        MYSQLD_ARGS="--server_id=$SERVER_ID"

	# Test we're able to startup without errors. We redirect stdout to /dev/null so
	# only the error messages are left.
	result=0
	output=$("$CMD" --verbose --help $MYSQLD_ARGS 2>&1 > /dev/null) || result=$?
	if [ ! "$result" = "0" ]; then
		echo >&2 'error: could not run mysql. This could be caused by a misconfigured my.cnf'
		echo >&2 "$output"
		exit 1
	fi

	# Get config
	DATADIR="$("$CMD" --verbose --help --log-bin-index=/tmp/tmp.index $MYSQLD_ARGS 2>/dev/null | awk '$1 == "datadir" { print $2; exit }')"

	# If no group name has been specified, let's see if one is in the config files
	[ -z "$GROUP_NAME" ] && GROUP_NAME="$(/usr/bin/my_print_defaults mysqld 2>/dev/null | awk -F "=" '$1 ~ /--[loose]*[_-]*group[_-]+replication[_-]+group[_-]+name/ { print $2; exit }')"

	GR_ARGS="--plugin-load=group_replication.so --group_replication_start_on_boot=ON --super_read_only=ON"

	if [ ! -z "$BOOTSTRAP" ]; then
		# Let's not blindly bootstrap the cluster if the datadir already exists
		# In that case we've likely restarted an existing container or are rebootstraping
		# the entire cluster (when the datadir exists and there are no seeds specified)
		if [ ! -d "$DATADIR/mysql" ] || [ -z "$GROUP_SEEDS" ]; then
			GR_ARGS="$GR_ARGS --group_replication_bootstrap_group=ON"

			# If a group name hasn't been specified anywhere, let's finally auto generate one 
			if [ -z "$GROUP_NAME" ]; then
				GROUP_NAME=$(uuidgen)

				# Let's persist the group_name since the env variable and config option was not set
				# This will allow for restarting the container w/o bootstrapping a new/second cluster
				echo "loose-group-replication-group-name=$GROUP_NAME" >> /etc/mysql/my.cnf
			fi	
		
			echo >&1 "info: Bootstrapping Group Replication cluster using --group_replication_group_name=$GROUP_NAME"
			echo >&1 "  You will need to specify GROUP_NAME=$GROUP_NAME if you want to add another node to this cluster"
		fi
	elif [ -z "$GROUP_SEEDS" ]; then
		echo >&2 'error: You must specify at least one valid IP/hostname:PORT URI value for GROUP_SEEDS in order to join an existing cluster'
	        exit 1
        else
		echo >&1 "info: attempting to join the $GROUP_NAME group using $GROUP_SEEDS as seeds"
	fi

	# Let's validate the group_name, as it needs to be a valid UUID 
	is_valid_uuid="$(echo $GROUP_NAME | tr '[:upper:]' '[:lower:]' | awk '$1 ~ /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/ { print $1; exit }')"
	if [ -z "$is_valid_uuid" ]; then
		echo >&2 'error: Specified GROUP_NAME is not a valid UUID'
        	exit 1
	fi

        GR_ARGS="$GR_ARGS --group_replication_group_name=$GROUP_NAME --group_replication_group_seeds=$GROUP_SEEDS"

        # You can use --hostname=<hostname> for each container or use the auto-generated one; 
        # we'll need to use the hostname for group_replication_local_address
        HOSTNAME=$(hostname)

	GR_ARGS="$GR_ARGS --group_replication_local_address=$HOSTNAME:6606"

	if [ ! -d "$DATADIR/mysql" ]; then
		if [ -z "$MYSQL_ROOT_PASSWORD" -a -z "$MYSQL_ALLOW_EMPTY_PASSWORD" -a -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
			echo >&2 'error: database is uninitialized and password option is not specified '
			echo >&2 '  You need to specify one of MYSQL_ROOT_PASSWORD, MYSQL_ALLOW_EMPTY_PASSWORD and MYSQL_RANDOM_ROOT_PASSWORD'
			exit 1
		fi
		mkdir -p "$DATADIR"
		chown -R mysql:mysql "$DATADIR"

		echo 'Initializing database'
		"$CMD" --initialize-insecure=on $MYSQLD_ARGS
		echo 'Database initialized'

		"$CMD" --skip-networking $MYSQLD_ARGS &
		pid="$!"

		mysql=( mysql --protocol=socket -uroot )

		for i in {30..0}; do
			if echo 'SELECT 1' | "${mysql[@]}" &> /dev/null; then
				break
			fi
			echo 'MySQL init process in progress...'
			sleep 1
		done
		if [ "$i" = 0 ]; then
			echo >&2 'MySQL init process failed.'
			exit 1
		fi

		mysql_tzinfo_to_sql /usr/share/zoneinfo | "${mysql[@]}" mysql
		
		if [ ! -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
			MYSQL_ROOT_PASSWORD="$(pwmake 128)"
			echo "GENERATED ROOT PASSWORD: $MYSQL_ROOT_PASSWORD"
		fi
		"${mysql[@]}" <<-EOSQL
			-- What's done in this file shouldn't be replicated
			SET @@SESSION.SQL_LOG_BIN=0;
			DELETE FROM mysql.user WHERE user NOT IN ('mysql.session', 'mysql.sys', 'mysqlxsys') OR host NOT IN ('localhost');
			CREATE USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}' ;
			GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION ;
			DROP DATABASE IF EXISTS test ;
			FLUSH PRIVILEGES ;
		EOSQL
		if [ ! -z "$MYSQL_ROOT_PASSWORD" ]; then
			mysql+=( -p"$MYSQL_ROOT_PASSWORD" )
		fi

		if [ "$MYSQL_DATABASE" ]; then
			echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` ;" | "${mysql[@]}"
			mysql+=( "$MYSQL_DATABASE" )
		fi

		if [ "$MYSQL_USER" -a "$MYSQL_PASSWORD" ]; then
			echo "CREATE USER '"$MYSQL_USER"'@'%' IDENTIFIED BY '"$MYSQL_PASSWORD"' ;" | "${mysql[@]}"

			if [ "$MYSQL_DATABASE" ]; then
				echo "GRANT ALL ON \`"$MYSQL_DATABASE"\`.* TO '"$MYSQL_USER"'@'%' ;" | "${mysql[@]}"
			fi

			echo 'FLUSH PRIVILEGES ;' | "${mysql[@]}"
		fi

		echo

		for f in /docker-entrypoint-initdb.d/*; do
			case "$f" in
				*.sh)  echo "$0: running $f"; . "$f" ;;
				*.sql) echo "$0: running $f"; "${mysql[@]}" < "$f" && echo ;;
				*)     echo "$0: ignoring $f" ;;
			esac
			echo
		done

                # let's remove any binary logs or GTID metadata that may have been generated 
                echo 'RESET MASTER ;' | "${mysql[@]}"

                # lastly we need to setup the recovery channel with a valid username/password
                echo "CHANGE MASTER TO MASTER_USER='root', MASTER_PASSWORD='$MYSQL_ROOT_PASSWORD' FOR CHANNEL 'group_replication_recovery' ;" | "${mysql[@]}"

		if ! kill -s TERM "$pid" || ! wait "$pid"; then
			echo >&2 'MySQL init process failed.'
			exit 1
		fi

		echo
		echo 'MySQL init process done. Ready for start up.'
		echo
	fi

	chown -R mysql:mysql "$DATADIR"

        CMD="mysqld $ARGS $GR_ARGS $MYSQLD_ARGS"
fi

# Let's store the account info for the healthcheck and general ease-of-use
touch "$HOME"/.my.cnf
cat > "$HOME/.my.cnf" <<EOCF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
EOCF

exec $CMD

