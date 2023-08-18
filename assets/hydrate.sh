#!/bin/sh
set -euo pipefail

# 1. ENV vars configuration
PS_FOLDER=${PS_FOLDER:?missing PS_FOLDER}
export PS_DOMAIN="replace-me.com" \
  DB_SERVER=127.0.0.1 \
  DB_PORT=3306 \
  DB_NAME=prestashop \
  DB_USER=root \
  DB_PASSWD=prestashop \
  ADMIN_MAIL=admin@prestashop.com \
  ADMIN_PASSWD=prestashop \
  PS_LANGUAGE=en \
  PS_COUNTRY=GB \
  PS_FOLDER_ADMIN=ps-admin \
  DB_SOCKET=/run/mysqld/mysqld.sock

# 2. Start a MySQL server
mkdir -p /run/mysqld /var/lib/mysql/;
mysql_install_db \
  --user=root \
  --ldata=/var/lib/mysql/ > /dev/null;
nohup /usr/bin/mysqld --user=root --skip-networking=0 --port=${DB_PORT} --socket=${DB_SOCKET} &
while [ ! -S ${DB_SOCKET} ]; do sleep 0.1; done
while ! nc -z localhost ${DB_PORT}; do sleep 0.1; done
echo "✅ MySQL started"

# 3. Setup the root password, add a PrestaShop database
mysqladmin --no-defaults --protocol=socket --user=root --password= password ${DB_PASSWD}
mysqladmin --no-defaults --protocol=socket --user=root --password=${DB_PASSWD} create ${DB_NAME}

# 4. Connectivity test (both the unix socket file and DB_SERVER:DB_PORT)
php -r "new PDO('mysql:unix_socket="${DB_SOCKET}";dbname="${DB_NAME}"', '"${DB_USER}"', '"${DB_PASSWD}"');"
php -r "new PDO('mysql:host="${DB_SERVER}";port="${DB_PORT}";dbname="${DB_NAME}"', '"${DB_USER}"', '"${DB_PASSWD}"');"
echo "✅ PHP PDO connectivity test"

# 5. Run the PrestaShop installer
# see: https://devdocs.prestashop-project.org/8/basics/installation/install-from-cli/
runuser -g www-data -u www-data -- \
  php -d memory_limit=-1 ${PS_FOLDER}/install/index_cli.php \
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
