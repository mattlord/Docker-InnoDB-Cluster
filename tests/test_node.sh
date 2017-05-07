#!/bin/bash
hostname=$(hostname)
in_node=0

for node in 1 2 3 ; do
	if [ "$hostname" = "mysqlgr$node" ]; then
		in_node=1
	fi
done

if [ "$in_node" = 0 ] ; then
	echo "# This command must run in one of the nodes. For example:"
	echo "# docker exec -it mysqlgr1 /opt/ic/tests/test_node.sh"
	exit 1
fi

if [ ! -f "$HOME/.my.cnf" ] ; then
	echo "File $HOME/.my.cnf not found - aborting"
	exit 1
fi

mysql="mysql -u root -h localhost --protocol=tcp "

echo "# Node $hostname"
$mysql -ve 'select * from performance_schema.replication_group_members\G'
$mysql -ve 'select * from performance_schema.replication_group_member_stats\G'
