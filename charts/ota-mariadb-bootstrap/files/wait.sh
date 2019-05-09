#!/bin/bash

# From https://raw.githubusercontent.com/DreamItGetIT/wait-for-mysql/master/wait.sh

echo "Waiting for mysql"
until mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -uroot -p"$MYSQL_ROOT_PASSWORD" &> /dev/null
do
  echo "."
  sleep 1
done

echo -e "\nmysql ready"
