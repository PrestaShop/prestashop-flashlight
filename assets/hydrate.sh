#!/bin/bash
set -eu -o pipefail

# 1. ENV vars configuration
MYSQL_DIR=/var/lib/mysql/
PS_FOLDER=${PS_FOLDER:?missing PS_FOLDER}
export PS_DOMAIN="replace-me.com" \
  DB_SERVER=127.0.0.1 \
  DB_PORT=3306 \
  DB_NAME=prestashop \
  DB_USER=prestashop \
  DB_PASSWD=prestashop \
  ADMIN_MAIL=admin@prestashop.com \
  ADMIN_PASSWD=prestashop \
  PS_LANGUAGE=en \
  PS_COUNTRY=GB \
  PS_FOLDER_ADMIN=ps-admin \
  DB_SOCKET=/run/mysqld/mysqld.sock

# 2. Start a MySQL server
if [ ! -d $MYSQL_DIR ]; then
  mkdir -p /run/mysqld ${MYSQL_DIR};
  mysql_install_db \
    --user=root \
    --ldata=${MYSQL_DIR} > /dev/null;
fi
nohup mysqld --user=root --skip-networking=0 --port=${DB_PORT} > /dev/null 2>&1 &
while [ ! -S ${DB_SOCKET} ]; do sleep 0.1; done
while ! nc -z localhost ${DB_PORT}; do sleep 0.1; done
echo "✅ MySQL started"

# 3. Setup the database and its user
mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '$DB_PASSWD';"
mysql -e "GRANT ALL PRIVILEGES ON * . * TO '${DB_USER}'@'localhost'; FLUSH PRIVILEGES;";
echo "✅ MySQL user ${DB_USER} and database ${DB_NAME} created"

# 4. Connectivity test (both the unix socket file and DB_SERVER:DB_PORT)
php -r "new PDO('mysql:unix_socket="${DB_SOCKET}";dbname="${DB_NAME}"', '"${DB_USER}"', '"${DB_PASSWD}"');"
php -r "new PDO('mysql:host=${DB_SERVER};port=${DB_PORT};dbname=${DB_NAME}', '${DB_USER}', '${DB_PASSWD}');"
echo "✅ PHP PDO connectivity test"

# Temp debug mode on for verbosity
sed -ie "s/define('_PS_MODE_DEV_', false);/define('_PS_MODE_DEV_',\ true);/g" $PS_FOLDER/config/defines.inc.php

# 5. Run the PrestaShop installer
# see: https://devdocs.prestashop-project.org/8/basics/installation/install-from-cli/
echo "Starting the PrestaShop installer..."
runuser -g www-data -u www-data -- \
  php \
    -d memory_limit=-1 \
    -d display_errors=1 \
    -d error_reporting=E_ALL \
  ${PS_FOLDER}/install/index_cli.php \
  --domain=$PS_DOMAIN \
  --db_create=1 \
  --db_server=${DB_SERVER}:${DB_PORT} \
  --db_port=$DB_PORT \
  --db_name=$DB_NAME \
  --db_user=$DB_USER \
  --db_password=$DB_PASSWD \
  --prefix=ps_ \
  --firstname=Admin \
  --lastname=PrestaShop \
  --password=$ADMIN_PASSWD \
  --email=$ADMIN_MAIL \
  --language=$PS_LANGUAGE \
  --country=$PS_COUNTRY \
  --all_languages=0 \
  --newsletter=0 \
  --send_email=0 \
  --ssl=0
echo "✅ PrestaShop installed"

# 6. Make a database dump
mysqldump -u ${DB_USER} --password=${DB_PASSWD} ${DB_NAME} > ${DUMP_FILE};
### TODO zip the dump and support both plain and zipped outputs from restoration to allow overrides
echo "✅ MySQL dump performed"

# 7. Cache clear
php -d memory_limit=-1 bin/console cache:clear

# 8. Tear down mysql
killall mysqld;

# 9. Some clean up
mv ${PS_FOLDER}/admin ${PS_FOLDER}/${PS_FOLDER_ADMIN}
