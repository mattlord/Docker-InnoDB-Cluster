#!/bin/bash

echo "Killing mysqlgr1 node..."
docker rm -f mysqlgr1
sleep 10 

echo "Checking cluster status now..."
docker exec -it mysqlgr2 mysqlsh --uri=root@myinnodbcluster:3306 -p$(cat secretpassword.txt) -i -e "dba.getCluster().status()"
sleep 2

echo "Killing and removing the original router..."
docker rm -f mysqlrouter1
sleep 2

echo "Creating another router instance..."
docker run -v $PWD/secretpassword.txt:/root/secretpassword.txt -e MYSQL_ROOT_PASSWORD=/root/secretpassword.txt -v $PWD:/opt/ic --name=mysqlrouter1 --hostname=mysqlrouter1 --network=grnet -e NODE_TYPE=router -e MYSQL_HOST=myinnodbcluster -itd mattalord/innodb-cluster

echo "Waiting 10 seconds for router bootstrap process to complete..."
sleep 10

echo "Testing the new router..."
docker exec -it mysqlrouter1 /opt/ic/tests/test_router.sh

exit
