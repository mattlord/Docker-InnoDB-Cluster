### You can use the example shell scripts to create a cluster (start_three_node_cluster.sh) and clean it up (cleanup_cluster.sh). Or you can do it by hand using the following steps:

# 1. Create a private network for the containers 
docker network create --driver bridge grnet

# 2. Bootstrap the cluster
docker run --name=mysqlgr1 --hostname=mysqlgr1 --network=grnet -e MYSQL_ROOT_PASSWORD=root -e BOOTSTRAP=1 -itd mattalord/innodb-cluster && docker logs mysqlgr1 | grep GROUP_NAME

##### This will spit out the GROUP_NAME to use for subsequent nodes, for example:
  You will need to specify GROUP_NAME=a94c5c6a-ecc6-4274-b6c1-70bd759ac27f if you want to add another node to this cluster

# 3. Add a second node to the cluster via a seed node
docker run --name=mysqlgr2 --hostname=mysqlgr2 --network=grnet -e MYSQL_ROOT_PASSWORD=root -e GROUP_NAME="a94c5c6a-ecc6-4274-b6c1-70bd759ac27f" -e GROUP_SEEDS="mysqlgr1:6606" -itd mattalord/innodb-cluster

# 4. Add a third node to the cluster via a seed node
docker run --name=mysqlgr3 --hostname=mysqlgr3 --network=grnet -e MYSQL_ROOT_PASSWORD=root -e GROUP_NAME="a94c5c6a-ecc6-4274-b6c1-70bd759ac27f" -e GROUP_SEEDS="mysqlgr1:6606" -itd mattalord/innodb-cluster

# 5. Add a nth node...

# 6. Connect to the cluster via the mysql command line client or MySQL Shell on one of the nodes
docker exec -it mysqlgr1 mysql -hmysqlgr1 -uroot -proot

There you can view the cluster membership status with:
select * from performance_schema.replication_group_members;

docker exec -it mysqlgr1 mysqlsh --uri=root:root@mysqlgr1:3306

There you can view the cluster status with:
dba.getCluster().status()

# 7. To test the router instance
docker exec -it mysqlrouter1 bash

To test the RW port, which always goes to the PRIMARY node:
mysql -u root -proot -h localhost --protocol=tcp -P6446 -e 'select @@global.server_uuid'

To test the RO port, which is round-robin load balanced to the SECONDARY nodes:
mysql -u root -proot -h localhost --protocol=tcp -P6447 -e 'select @@global.server_uuid'
