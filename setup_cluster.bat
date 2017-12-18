title 3 Node Group Replication Cluster Setup

echo Creating dedicated network: grnet ...
docker network create --driver bridge grnet

echo Bootstrapping the cluster ...
docker run --rm --name=mysqlgr1 --hostname=mysqlgr1 --network=grnet -p 3391:3306 -e MYSQL_ROOT_PASSWORD=root -e BOOTSTRAP=1 -e GROUP_NAME="92bb4382-3bd1-11e7-a919-92ebcb67fe33" -itd mattalord/innodb-cluster
timeout 3 /NOBREAK

echo Adding second node to the cluster ...
docker run --rm --name=mysqlgr2 --hostname=mysqlgr2 --network=grnet -p 3392:3306 -e MYSQL_ROOT_PASSWORD=root -e GROUP_NAME="92bb4382-3bd1-11e7-a919-92ebcb67fe33" -e GROUP_SEEDS="mysqlgr1:6606" -itd mattalord/innodb-cluster
timeout 3 /NOBREAK

echo Adding a third node to the cluster ...
docker run --rm --name=mysqlgr3 --hostname=mysqlgr3 --network=grnet -p 3393:3306 -e MYSQL_ROOT_PASSWORD=root -e GROUP_NAME="92bb4382-3bd1-11e7-a919-92ebcb67fe33" -e GROUP_SEEDS="mysqlgr1:6606" -itd mattalord/innodb-cluster
timeout 3 /NOBREAK

echo Giving the cluster time to finish initializing and syncing up...
; the setup is *really* slow on Windows (at least for me)
timeout 30 /NOBREAK

echo Testing the cluster status ...
docker exec -it mysqlgr1 mysql -u root -proot -e "select * from performance_schema.replication_group_members"

echo Done!
