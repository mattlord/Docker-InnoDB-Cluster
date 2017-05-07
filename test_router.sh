#!/bin/bash

if [ "$(hostname)" != "mysqlrouter1" ] ; then
	echo "# This command must run in the router"
	echo "# e.g.: "
	echo "# docker exec -it mysqlrouter1 /opt/ic/test_router.sh"
	exit 1
fi

if [ ! -f "$HOME/.my.cnf" ] ; then
	echo "File $HOME/.my.cnf not found - aborting"
	exit 1
fi

mysql="mysql -u root -h localhost --protocol=tcp "

echo "Server ID of current master"
$mysql -P6446 -ve 'SELECT @@global.server_id'

echo "Create content using router"
$mysql -P6446 -ve 'create schema if not exists test'
$mysql -P6446  test -ve 'drop table if exists t1'
$mysql -P6446  test -ve 'create table t1(id int not null primary key, name varchar(50))'
$mysql -P6446  test -ve 'insert into t1 values (1, "aaa")'

sleep 3
echo "Server ID of A RO node"
$mysql -P6447 -ve 'SELECT @@global.server_id'

echo "retrieving contents using router"
$mysql -P6447 -ve 'SELECT * from test.t1'
