#!/bin/bash

for node in 1 2 3 ; do
	docker exec -it mysqlgr$node /opt/ic/tests/test_node.sh
done
