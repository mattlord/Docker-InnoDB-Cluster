#!/bin/bash
node=$1
[ -z "$node" ] && node=1

PWD_FILE=secretpassword.txt
if [ ! -f $PWD_FILE ] ; then
    # if the script is executed in the sub folder, the password file is one level up
    PWD_FILE=../$PWD_FILE
fi
# if you want to view the command that's being executed, uncomment the set -x line
# set -x 
docker exec -it mysqlgr$node mysqlsh \
    --uri=root@mysqlgr$node:3306 \
    -p$(cat $PWD_FILE) \
    -i -e 'dba.getCluster().status()'

