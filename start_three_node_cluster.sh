#!/bin/sh

echo "Creating dedicated grnet network..."
docker network create --driver bridge grnet

echo "Bootstrapping the cluster..."
docker run --name=mysqlgr1 --hostname=mysqlgr1 --network=grnet -e MYSQL_ROOT_PASSWORD=root -e BOOTSTRAP=1 -itd mattalord/innodb-cluster

for i in {60..0}; do
	if docker logs mysqlgr1 | grep 'Ready for start up'; then
        	break
        fi
        echo 'Starting mysqlgr1 container...'
        sleep 1
done

if [ "$i" = 0 ]; then
	echo >&2 'Start of mysqlgr1 container failed.'
	exit 1
fi

echo "Getting GROUP_NAME..."
GROUP_PARAM=$(docker logs mysqlgr1 | awk 'BEGIN {RS=" "}; /GROUP_NAME/')

echo "Adding second node..."
docker run --name=mysqlgr2 --hostname=mysqlgr2 --network=grnet -e MYSQL_ROOT_PASSWORD=root -e $GROUP_PARAM -e GROUP_SEEDS="mysqlgr1:6606" -itd mattalord/innodb-cluster

for i in {60..0}; do
        if docker logs mysqlgr2 | grep 'Ready for start up'; then
                break           
        fi              
        echo 'Starting mysqlgr2 container...'
        sleep 1         
done    

if [ "$i" = 0 ]; then
        echo >&2 'Start of mysqlgr2 container failed.'
        exit 1
fi  

echo "Adding third node..."
docker run --name=mysqlgr3 --hostname=mysqlgr3 --network=grnet -e MYSQL_ROOT_PASSWORD=root -e $GROUP_PARAM -e GROUP_SEEDS="mysqlgr1:6606" -itd mattalord/innodb-cluster

for i in {60..0}; do
        if docker logs mysqlgr3 | grep 'Ready for start up'; then
                break           
        fi              
        echo 'Starting mysqlgr3 container...'
        sleep 1         
done    

if [ "$i" = 0 ]; then
        echo >&2 'Start of mysqlgr3 container failed.'
        exit 1
fi  

echo "Done!"

echo "Connecting to the InnoDB cluster..."
docker run -it --network=grnet --rm mysql sh -c 'exec mysql -hmysqlgr1 -uroot -proot'

exit
