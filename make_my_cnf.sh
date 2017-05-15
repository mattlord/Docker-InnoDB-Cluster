#!/bin/bash

echo '[client]'   > ~/.my.cnf
echo 'user=root' >> ~/.my.cnf
echo "password='$(cat /root/secretpassword.txt)'" >> ~/.my.cnf

