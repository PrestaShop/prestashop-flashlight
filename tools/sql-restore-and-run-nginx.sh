#!/bin/sh
set -e -o pipefail

echo "Restoring MySQL dump..."
mysql -u ${DB_USER} --password=${DB_PASSWD} ${DB_NAME} < /dump.sql
echo "Dump restored!"

echo "Starting Prestashop..."
EXPOSE 8000

STOPSIGNAL SIGQUIT

CMD ["nginx", "-g", "daemon off;"]