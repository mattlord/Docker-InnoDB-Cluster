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

exit
