#!/bin/bash

echo "Stopping and removing the mysqlgr1 container..."
docker stop mysqlgr1 >/dev/null 2>&1 && docker rm -v mysqlgr1 >/dev/null 2>&1

echo "Stopping and removing the mysqlgr2 container..."
docker stop mysqlgr2 >/dev/null 2>&1 && docker rm -v mysqlgr2 >/dev/null 2>&1

echo "Stopping and removing the mysqlgr3 container..."
docker stop mysqlgr3 >/dev/null 2>&1 && docker rm -v mysqlgr3 >/dev/null 2>&1

echo "Stopping and removing the mysqlrouter1 container..."
docker stop mysqlrouter1 >/dev/null 2>&1 && docker rm -v mysqlrouter1 >/dev/null 2>&1

echo "Removing the grnet network..."
docker network rm grnet >/dev/null 2>&1

echo "Done!"

echo
echo "If you also want to reclaim disk space and remove all docker volumes currently unused by any containers, then execute the following command:"
echo "docker volume prune -f"
echo

exit
