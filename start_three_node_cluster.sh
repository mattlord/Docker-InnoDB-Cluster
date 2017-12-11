#!/bin/bash

function create_network
{
	NETWORK_NAME=$1
	exist_network=$(docker network ls | grep -w $NETWORK_NAME)

	if [ -n "$exist_network" ]; then
		echo "# network $NETWORK_NAME already exists"
	else
		docker network create --driver bridge $NETWORK_NAME
	fi

	docker network ls | grep -w "$NETWORK_NAME\|^NETWORK"
}

function check_for_failure
{
	container_name=$1
	is_alive=$(docker ps -a | grep -w $container_name | grep -w Up)

	if [ -n "$is_alive" ]; then
		echo "Container $container_name is up at $(date)"
	fi

	is_dead=$(docker ps -a | grep -w $container_name | grep -w Exited)

	if [ -n "$is_dead" ]; then
		echo "Container $container_name is dead at ($date)"
		exit 1
	fi
}

function check_for_started_server
{
	container_name=$1

	echo -n "Starting $container_name container..."
	for i in {30..0}; do
		if [[ $(docker logs $container_name) =~ "Ready for start up" ]]; then
			echo " done."
			break
		fi
		echo -n "."
		sleep 2
	done

	if [ "$i" = 0 ]; then
		echo
		echo >&2 "Start of $container_name container failed."
		exit 1
	fi
}

# Allow the cluster to use a random password instead of a predefined one if desired
[ -z "$SECRET_PWD_FILE" ] && SECRET_PWD_FILE=secretpassword.txt

# Adding the current path as a volume (/opt/ic) in every node
docker_run="docker run --network=grnet -v $PWD/$SECRET_PWD_FILE:/root/$SECRET_PWD_FILE -e MYSQL_ROOT_PASSWORD=/root/$SECRET_PWD_FILE -v $PWD:/opt/ic"

if [ -f "$SECRET_PWD_FILE" ]; then
	echo "Password file exists! Please remove it ($SECRET_PWD_FILE) if you want a new one to be generated." 
else
	# macOS uses `shasum -a 256` rather than a separate sha256sum binary
	if uname | grep '^Darwin$' >/dev/null 2>&1; then
		SHA_CHKSUM_BIN="shasum -a 256"
	else
		SHA_CHKSUM_BIN="sha256sum"
	fi

	# This command will allow us to create a random password roughly equivalent to `pwmake 128` on linux, but should be available on all
	# UNIX variants (including macOS). It will allow the use of validate_password_policy=[0,1,2] with mysqld as we'll meet the strict requirements.
	# *But*, there seems to be an issue in how router handles the --uri parameter which prevents us from using non-alphanumberic characters...
	# So for now we'll pass the password to router via STDIN
	RANDOM_PASSWORD=$(head -c 128 /dev/urandom | LANG=C tr -cd "[:alpha:] [:punct:]" | tr -d "[:blank:] [:cntrl:] \;\` \* \"\'\\\\" | cut -c 1-27)

	if [ -z "$RANDOM_PASSWORD" ] ; then
		RANDOM_PASSWORD=$(date +%N%s)
	fi
	echo $RANDOM_PASSWORD > $SECRET_PWD_FILE
fi

echo "Creating dedicated grnet network..."
create_network grnet

[ -z "$INNODB_CLUSTER_IMG" ] && INNODB_CLUSTER_IMG=mattalord/innodb-cluster

echo "Bootstrapping the cluster..."
params="-e SERVER_ID=100 --name=mysqlgr1 --hostname=mysqlgr1 --network-alias=myinnodbcluster"
$docker_run $params -e BOOTSTRAP=1 -e GROUP_SEEDS="mysqlgr1:6606,mysqlgr2:6606,mysqlgr3:6606" -itd $INNODB_CLUSTER_IMG

check_for_failure mysqlgr1
check_for_started_server mysqlgr1

echo "Getting GROUP_NAME..."
GROUP_PARAM=$(docker logs mysqlgr1 | awk 'BEGIN {RS=" "}; /GROUP_NAME/')

echo "Adding second node..."
params="-e SERVER_ID=200 --name=mysqlgr2 --hostname=mysqlgr2 --network-alias=myinnodbcluster"
$docker_run $params -e $GROUP_PARAM -e GROUP_SEEDS="mysqlgr1:6606,mysqlgr2:6606,mysqlgr3:6606" -itd $INNODB_CLUSTER_IMG

check_for_failure mysqlgr2
check_for_started_server mysqlgr2

echo "Adding third node..."
params="-e SERVER_ID=300 --name=mysqlgr3 --hostname=mysqlgr3  --network-alias=myinnodbcluster"
$docker_run $params -e $GROUP_PARAM -e GROUP_SEEDS="mysqlgr1:6606,mysqlgr2:6606,mysqlgr3:6606" -itd $INNODB_CLUSTER_IMG

check_for_failure mysqlgr3
check_for_started_server mysqlgr3

# let's give GR a few seconds to finish syncing up
DELAY=10
echo "Sleeping $DELAY seconds to give the cluster time to sync up"
sleep $DELAY

echo "Adding a router..."
$docker_run --name=mysqlrouter1 --hostname=mysqlrouter1 -e NODE_TYPE=router -e MYSQL_HOST=myinnodbcluster -itd $INNODB_CLUSTER_IMG
check_for_failure mysqlrouter1

echo "Done!"

echo "Connecting to the InnoDB cluster..."
echo
echo "Executing dba.getCluster().status() to see the current status"
echo

DELAY=5
echo "Sleeping $DELAY seconds to give the router time to connect"
sleep $DELAY

./tests/check_cluster.sh 1

exit
