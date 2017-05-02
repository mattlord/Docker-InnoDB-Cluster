#!/bin/bash
set -e


# if command starts with an option, save them as CMD arguments
if [ "${1:0:1}" = '-' ]; then
        ARGS="$@"
fi

# If we're setting up a router 
if [ "$NODE_TYPE" = 'router' ]; then

        echo 'Setting up a new router instance...'

        # we need to ensure that they've specified a boostrap URI 
        if [ -z "$BOOTSTRAP" ]; then
                echo >&2 'error: a valid mysqld URI must be specified via the BOOTSTRAP env variable when setting up a router'
                exit 1
        fi

        CMD="mysqlrouter --bootstrap=$BOOTSTRAP"

# Let's setup a mysql server instance normally 
else
	if [ -z "$BOOTSTRAP" -a -z "$GROUP_NAME" ]; then 
		echo >&2 'error: You must either BOOTSTRAP a new cluster--where a new group name UUID will be generated--or you must specify a value for the GROUP_NAME that you wish to join'
	        exit 1
	fi

        # let's generate a random server_id value; it can be any unsigned 32 bit int
        SERVER_ID=$((RANDOM % 1000))

        # We'll use this variable to manage the mysqld args 
        MYSQLD_ARGS="--server_id=$SERVER_ID"

	# if we're bootstrapping a new group then let's just generate a new group_name / UUID	
	if [ ! -z "$BOOTSTRAP" ]; then
		GROUP_NAME=$(uuidgen)
		echo >&1 "info: Bootstrapping new Group Replication cluster using --group_replication_bootstrap_group=\"$GROUP_NAME\""
		echo >&1 "  You will need to specify GROUP_NAME=\"$GROUP_NAME\" if you want to add another node to this cluster"

		MYSQLD_ARGS="$MYSQLD_ARGS --group_replication_bootstrap_group=ON"
 	fi

        # You can use --hostname=<hostname> for each container or use the auto-generated one; 
        # we'll need to use the hostname for group_replication_local_address
        HOSTNAME=$(hostname)

	MYSQLD_ARGS="$MYSQLD_ARGS --group_replication_group_name=\"${GROUP_NAME}\" --group_replication_local_address=\"$HOSTNAME:6606\""

	# Test we're able to startup without errors. We redirect stdout to /dev/null so
	# only the error messages are left.
	result=0
	output=$("$@" --verbose --help 2>&1 > /dev/null) || result=$?
	if [ ! "$result" = "0" ]; then
		echo >&2 'error: could not run mysql. This could be caused by a misconfigured my.cnf'
		echo >&2 "$output"
		exit 1
	fi

	# Get config
	DATADIR="$("$@" --verbose --help --log-bin-index=/tmp/tmp.index 2>/dev/null | awk '$1 == "datadir" { print $2; exit }')"

	if [ ! -d "$DATADIR/mysql" ]; then
		if [ -z "$MYSQL_ROOT_PASSWORD" -a -z "$MYSQL_ALLOW_EMPTY_PASSWORD" -a -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
			echo >&2 'error: database is uninitialized and password option is not specified '
			echo >&2 '  You need to specify one of MYSQL_ROOT_PASSWORD, MYSQL_ALLOW_EMPTY_PASSWORD and MYSQL_RANDOM_ROOT_PASSWORD'
			exit 1
		fi
		# If the password variable is a filename we use the contents of the file
		if [ -f "$MYSQL_ROOT_PASSWORD" ]; then
			MYSQL_ROOT_PASSWORD="$(cat $MYSQL_ROOT_PASSWORD)"
		fi
		mkdir -p "$DATADIR"
		chown -R mysql:mysql "$DATADIR"

		echo 'Initializing database'
		"$@" --initialize-insecure=on
		echo 'Database initialized'

		"$@" --skip-networking &
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
			--  or products like mysql-fabric won't work
			SET @@SESSION.SQL_LOG_BIN=0;
			DELETE FROM mysql.user WHERE user NOT IN ('mysql.sys', 'mysqlxsys');
			CREATE USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}' ;
			GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION ;
			DROP DATABASE IF EXISTS test ;
			FLUSH PRIVILEGES ;
		EOSQL
		if [ ! -z "$MYSQL_ROOT_PASSWORD" ]; then
			mysql+=( -p"${MYSQL_ROOT_PASSWORD}" )
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

		if [ ! -z "$MYSQL_ONETIME_PASSWORD" ]; then
			"${mysql[@]}" <<-EOSQL
				ALTER USER 'root'@'%' PASSWORD EXPIRE;
			EOSQL
		fi
		if ! kill -s TERM "$pid" || ! wait "$pid"; then
			echo >&2 'MySQL init process failed.'
			exit 1
		fi

		echo
		echo 'MySQL init process done. Ready for start up.'
		echo
	fi

	chown -R mysql:mysql "$DATADIR"

        CMD="mysqld $ARGS $MYSQLD_ARGS"
fi

exec $CMD

