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

echo "Creating dedicated grnet network..."
create_network grnet

INNODB_CLUSTER_IMG=mattalord/innodb-cluster

echo "Bootstrapping the cluster..."
docker run --name=mysqlgr1 --hostname=mysqlgr1 --network=grnet -e MYSQL_ROOT_PASSWORD=root -e BOOTSTRAP=1 -itd $INNODB_CLUSTER_IMG

check_for_failure mysqlgr1
check_for_started_server mysqlgr1

echo "Getting GROUP_NAME..."
GROUP_PARAM=$(docker logs mysqlgr1 | awk 'BEGIN {RS=" "}; /GROUP_NAME/')

echo "Adding second node..."
docker run --name=mysqlgr2 --hostname=mysqlgr2 --network=grnet -e MYSQL_ROOT_PASSWORD=root -e $GROUP_PARAM -e GROUP_SEEDS="mysqlgr1:6606" -itd $INNODB_CLUSTER_IMG

check_for_failure mysqlgr2
check_for_started_server mysqlgr2

echo "Adding third node..."
docker run --name=mysqlgr3 --hostname=mysqlgr3 --network=grnet -e MYSQL_ROOT_PASSWORD=root -e $GROUP_PARAM -e GROUP_SEEDS="mysqlgr1:6606" -itd $INNODB_CLUSTER_IMG

check_for_failure mysqlgr3
check_for_started_server mysqlgr3

# let's give GR a few seconds to finish syncing up
DELAY=10
echo "Sleeping $DELAY seconds to give the cluster time to sync up"
sleep $DELAY

echo "Adding a router..."
docker run --name=mysqlrouter1 --hostname=mysqlrouter1 --network=grnet -e NODE_TYPE=router -e MYSQL_HOST=mysqlgr1 -e MYSQL_ROOT_PASSWORD=root -itd $INNODB_CLUSTER_IMG
check_for_failure mysqlrouter1

echo "Done!"

echo "Connecting to the InnoDB cluster..."
echo
echo "Execute dba.getCluster().status() to see the current status"
echo
#docker exec -it mysqlgr1 mysql -hmysqlgr1 -uroot -proot
docker exec -it mysqlgr1 mysqlsh --uri=root:root@mysqlgr1:3306

exit
