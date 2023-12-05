#!/bin/bash
set -eu

# 1. Settings
PS_FOLDER=${PS_FOLDER:?missing PS_FOLDER}
PS_CACHE_DIR="${PS_FOLDER}/var/cache"
PS_LOGS_DIR="${PS_FOLDER}/var/logs"
PS_OPT_DIR=/var/opt/prestashop
DUMP_FILE=/dump.sql

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
  PS_FOLDER_ADMIN=admin-dev \
  DB_SOCKET=/run/mysqld/mysqld.sock

# 2. Start a MySQL server
mkdir -p /run/mysqld /var/lib/mysql/;
mysql_install_db \
  --user=root \
  --ldata=/var/lib/mysql/ > /dev/null;
nohup mysqld --user=root --skip-networking=0 --port=${DB_PORT} --socket=${DB_SOCKET} &
while [ ! -S ${DB_SOCKET} ]; do sleep 0.1; done
while ! nc -z localhost ${DB_PORT}; do sleep 0.1; done
echo "✅ MySQL started"

# 3. Setup the root password, add a PrestaShop database
mysql --user=root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_PASSWD}';"
mysql --user=root --password=${DB_PASSWD} -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME}";

# 4. Connectivity test (both the unix socket file and DB_SERVER:DB_PORT)
php -r "new PDO('mysql:unix_socket=""$DB_SOCKET"";dbname=""$DB_NAME""', '""$DB_USER""', '""$DB_PASSWD""');"
php -r "new PDO('mysql:host=""$DB_SERVER"";port=""$DB_PORT"";dbname=""$DB_NAME""', '""$DB_USER""', '""$DB_PASSWD""');"
echo "✅ PHP PDO connectivity test"

# 5. Set dev mode to debug the installation if it fails
sed -ie "s/define('_PS_MODE_DEV_', false);/define('_PS_MODE_DEV_',\ true);/g" "$PS_FOLDER/config/defines.inc.php"

# 6. Run the PrestaShop installer
# see: https://devdocs.prestashop-project.org/8/basics/installation/install-from-cli/
sudo -g www-data -u www-data -- \
  php -f "${PS_FOLDER}/install/index_cli.php" -- \
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

# 7. Swap off dev mode
sed -ie "s/define('_PS_MODE_DEV_', true);/define('_PS_MODE_DEV_',\ false);/g" "$PS_FOLDER/config/defines.inc.php"

# 8. Make a database dump
mysqldump -u ${DB_USER} --password=${DB_PASSWD} ${DB_NAME} > ${DUMP_FILE};
# TODO zip the dump and support both plain and zipped outputs from restoration to allow overrides
echo "✅ MySQL dump performed"

# 9. Cache clear
if [ -d "./bin/console" ]; then
  php -d memory_limit=-1 bin/console cache:clear;
else 
  # PrestaShop 1.6 only
  rm -rf "$PS_FOLDER/cache/*";
fi

# 10. Tear down mysql
killall mysqld;

# 11. Some clean up
mv "${PS_FOLDER}/admin" "${PS_FOLDER}/${PS_FOLDER_ADMIN}"
rm -rf \
  "$PS_FOLDER/install" \
  "$PS_FOLDER/Install_PrestaShop.html" \
  "$PS_CACHE_DIR" \
  "$PS_LOGS_DIR"
mkdir -p "$PS_CACHE_DIR" "$PS_LOGS_DIR"
chown -R www-data:www-data "$PS_CACHE_DIR" "$PS_LOGS_DIR"

# 12. Protect our settings against a volume mount on $PS_FOLDER
mkdir -p "$PS_OPT_DIR"
if [ -f "$PS_FOLDER/app/config/parameters.php" ]; then
  cp "$PS_FOLDER/app/config/parameters.php" "$PS_OPT_DIR/parameters.php"
elif [ -f "$PS_FOLDER/config/settings.inc.php" ]; then
  cp "$PS_FOLDER/config/settings.inc.php" "$PS_OPT_DIR/settings.inc.php"
fi
