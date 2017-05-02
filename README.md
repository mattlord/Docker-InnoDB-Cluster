# 1. Create a private network for the containers 
docker network create --driver bridge grnet

# 2. Bootstrap the cluster
docker run --name=mysqlgr1 --hostname=mysqlgr1 --network=grnet -e MYSQL_ROOT_PASSWORD=root -e BOOTSTRAP=1 -itd 4f76fa36fdff

### this will spit out the GROUP_NAME to use for subsequent nodes, for example:
docker logs mysqlgr1 | grep GROUP_NAME
  You will need to specify GROUP_NAME="a94c5c6a-ecc6-4274-b6c1-70bd759ac27f" if you want to add another node to this cluster

# 3. Add a second node to the cluster via a seed node
docker run --name=mysqlgr2 --hostname=mysqlgr2 --network=grnet -e MYSQL_ROOT_PASSWORD=root -e GROUP_NAME="a94c5c6a-ecc6-4274-b6c1-70bd759ac27f" -e GROUP_SEEDS="mysqlgr1:6606" -itd 4f76fa36fdff

# 4. Add a third node to the cluster via a seed node
docker run --name=mysqlgr3 --hostname=mysqlgr3 --network=grnet -e MYSQL_ROOT_PASSWORD=root -e GROUP_NAME="a94c5c6a-ecc6-4274-b6c1-70bd759ac27f" -e GROUP_SEEDS="mysqlgr1:6606" -itd 4f76fa36fdff

# 5. Add a nth node...

# 6. Connect to one of the nodes via the mysql command-line client 
docker run -it --network=grnet --rm mysql sh -c 'exec mysql -hmysqlgr1 -uroot -proot'

# 7. View the cluster membership status 
select * from performance_schema.replication_group_members;

