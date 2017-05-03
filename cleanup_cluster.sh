#!/bin/sh

echo "Stopping and removing mysqlgr1..."
docker stop mysqlgr1 && docker rm mysqlgr1 

echo "Stopping and removing mysqlgr2..."
docker stop mysqlgr2 && docker rm mysqlgr2

echo "Stopping and removing mysqlgr3..."
docker stop mysqlgr3 && docker rm mysqlgr3

echo "Removing grnet network..."
docker network rm grnet

echo "Done!"

exit
