#!/bin/bash

echo "Killing mysqlgr1 node..."
docker rm -f mysqlgr1

echo "Checking cluster status now..."
docker exec -it mysqlgr2 mysqlsh --uri=root@myinnodbcluster:3306 -p$(cat secretpassword.txt) -i -e "dba.getCluster().status()"

echo "Killing and removing the original router..."
docker rm -f mysqlrouter1

echo "Creating another router instance..."
docker run -v $PWD/secretpassword.txt:/root/secretpassword.txt -e MYSQL_ROOT_PASSWORD=/root/secretpassword.txt -v $PWD:/opt/ic --name=mysqlrouter1 --hostname=mysqlrouter1 --network=grnet -e NODE_TYPE=router -e MYSQL_HOST=myinnodbcluster -itd mattalord/innodb-cluster

echo "Testing the new router..."
./tests/test_router.sh

exit
