#!/bin/bash

set -e

cat /tmp/sql/create_databases.sql.tpl | envsubst > /tmp/create_databases.sql
cat /tmp/sql/install_plugins.sql.tpl | envsubst > /tmp/install_plugins.sql

mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD < /tmp/install_plugins.sql || true
mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD < /tmp/create_databases.sql
