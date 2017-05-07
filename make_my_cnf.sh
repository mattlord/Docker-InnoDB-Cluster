#!/bin/bash

echo '[client]'   > ~/.my.cnf
echo 'user=root' >> ~/.my.cnf
echo -n 'password=' >> ~/.my.cnf
cat /root/secretpassword.txt >> ~/.my.cnf

