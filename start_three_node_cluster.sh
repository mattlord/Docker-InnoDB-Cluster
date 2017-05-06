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

	for i in {60..0}; do
		if docker logs $container_name | grep 'Ready for start up'; then
			break
		fi
		echo "Starting $container_name container..."
		sleep 1
	done

	if [ "$i" = 0 ]; then
		echo >&2 "Start of $container_name container failed."
		exit 1
	fi
}

# Allow the cluster to use a random password instead of a predefined one if desired
SECRET_PWD_FILE=secretpassword.txt

docker_run="docker run --network=grnet -v $PWD/$SECRET_PWD_FILE:/root/$SECRET_PWD_FILE -e MYSQL_ROOT_PASSWORD=/root/$SECRET_PWD_FILE"

# macOS only has shasum
if uname | grep '^Darwin$' >/dev/null 2>&1; then
	SHA_CHKSUM_BIN="shasum"
else
	SHA_CHKSUM_BIN="sha256sum"
fi

# This command will allow us to create a random password roughly equivalent to `pwmake 128` on linux, but should be available on all UNIX variants (including macOS)
# This will allow people to use validate_password_policy=[0,1,2] with mysqld 
RANDOM_PASSWORD=$(echo $RANDOM | "$SHA_CHKSUM_BIN" | base64 | head -c 28 )

if [ -z "$RANDOM_PASSWORD" ] ; then
    RANDOM_PASSWORD=$(date +%N%s)
fi
echo $RANDOM_PASSWORD > $SECRET_PWD_FILE

echo "Creating dedicated grnet network..."
create_network grnet

[ -z "$INNODB_CLUSTER_IMG" ] && INNODB_CLUSTER_IMG=mattalord/innodb-cluster

echo "Bootstrapping the cluster..."
$docker_run --name=mysqlgr1 --hostname=mysqlgr1 -e BOOTSTRAP=1 -itd $INNODB_CLUSTER_IMG

check_for_failure mysqlgr1
check_for_started_server mysqlgr1

echo "Getting GROUP_NAME..."
GROUP_PARAM=$(docker logs mysqlgr1 | awk 'BEGIN {RS=" "}; /GROUP_NAME/')

echo "Adding second node..."
$docker_run --name=mysqlgr2 --hostname=mysqlgr2 -e $GROUP_PARAM -e GROUP_SEEDS="mysqlgr1:6606" -itd $INNODB_CLUSTER_IMG

check_for_failure mysqlgr2
check_for_started_server mysqlgr2

echo "Adding third node..."
$docker_run --name=mysqlgr3 --hostname=mysqlgr3 -e $GROUP_PARAM -e GROUP_SEEDS="mysqlgr1:6606" -itd $INNODB_CLUSTER_IMG

check_for_failure mysqlgr3
check_for_started_server mysqlgr3

# let's give GR a few seconds to finish syncing up
DELAY=10
echo "Sleeping $DELAY seconds to give the cluster time to sync up"
sleep $DELAY

echo "Adding a router..."
$docker_run --name=mysqlrouter1 --hostname=mysqlrouter1 -e NODE_TYPE=router -e MYSQL_HOST=mysqlgr1 -itd $INNODB_CLUSTER_IMG
check_for_failure mysqlrouter1

echo "Done!"

echo "Connecting to the InnoDB cluster..."
echo
echo "Execute dba.getCluster().status() to see the current status"
echo

# if you want to view the command that's being executed, uncomment the set -x line
# set -x 
docker exec -it mysqlgr1 mysqlsh --uri=root:$(cat $SECRET_PWD_FILE)@mysqlgr1:3306

exit
