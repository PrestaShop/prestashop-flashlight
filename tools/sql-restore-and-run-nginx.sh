#!/bin/sh
set -euo pipefail

echo "Applying PS_DOMAIN ($PS_DOMAIN) to the dump"
sed -i s/replace-me.com/$PS_DOMAIN/g /dump.sql
##@TODO: make it configurable in a ./transform directory

echo "Restoring MySQL dump..."
mysql -u ${MYSQL_USER} --host=${MYSQL_HOST} --password=${MYSQL_PASSWORD} ${MYSQL_DATABASE} < /dump.sql
echo "Dump restored!"

echo "Starting Prestashop..."
nginx -g "daemon off;"
