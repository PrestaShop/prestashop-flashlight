#!/bin/sh
set -e -o pipefail

echo "Restoring MySQL dump..."
mysql -u ${MYSQL_USER} --host=${MYSQL_HOST} --password=${MYSQL_PASSWORD} ${MYSQL_DATABASE} < /dump.sql
echo "Dump restored!"

echo "Starting Prestashop..."
nginx -g "daemon off;"
