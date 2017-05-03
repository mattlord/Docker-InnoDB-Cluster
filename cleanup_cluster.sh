#!/bin/sh

echo "Stopping and removing mysqlgr1..."
docker stop mysqlgr1 >/dev/null 2>&1 && docker rm mysqlgr1 >/dev/null 2>&1

echo "Stopping and removing mysqlgr2..."
docker stop mysqlgr2 >/dev/null 2>&1 && docker rm mysqlgr2 >/dev/null 2>&1

echo "Stopping and removing mysqlgr3..."
docker stop mysqlgr3 >/dev/null 2>&1 && docker rm mysqlgr3 >/dev/null 2>&1

echo "Removing grnet network..."
docker network rm grnet >/dev/null 2>&1

echo "Done!"

exit
