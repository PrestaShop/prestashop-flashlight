#!/bin/bash
set -eu

# 1. Settings
PS_FOLDER=${PS_FOLDER:?missing PS_FOLDER}
PS_CACHE_DIR="${PS_FOLDER}/var/cache"
PS_LOGS_DIR="${PS_FOLDER}/var/logs"
DUMP_FILE=/dump.sql

export PS_DOMAIN="localhost:80" \
  DB_SERVER=127.0.0.1 \
  DB_PORT=3306 \
  DB_NAME=prestashop \
  DB_USER=prestashop \
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
nohup mysqld --user=root --bind-address="$DB_SERVER" --port="$DB_PORT" --socket="$DB_SOCKET" &

while [ ! -S "$DB_SOCKET" ]; do sleep 0.1; done
while ! nc -z "$DB_SERVER" "$DB_PORT"; do sleep 0.1; done
echo "✅ MySQL started"

# 3. Setup the root password, add a PrestaShop database
mysql --user=root -e "CREATE DATABASE IF NOT EXISTS $DB_NAME";
mysql --user=root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWD';";
mysql --user=root -e "GRANT ALL PRIVILEGES ON *.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"

# 4. Connectivity test (both the unix socket file and DB_SERVER:DB_PORT)
php -r "new PDO('mysql:unix_socket=""$DB_SOCKET"";dbname=""$DB_NAME""', '""$DB_USER""', '""$DB_PASSWD""');"
php -r "new PDO('mysql:host=""$DB_SERVER"";port=""$DB_PORT"";dbname=""$DB_NAME""', '""$DB_USER""', '""$DB_PASSWD""');"
echo "✅ PHP PDO connectivity test"

# 5. Set dev mode to debug the installation if it fails
sed -ie "s/define('_PS_MODE_DEV_', false);/define('_PS_MODE_DEV_',\ true);/g" "$PS_FOLDER/config/defines.inc.php"

# 6. Run the PrestaShop installer
# prevent the installer from moving the admin folder
[ -d "${PS_FOLDER}/admin" ] && mv "${PS_FOLDER}/admin" "${PS_FOLDER}/${PS_FOLDER_ADMIN}"
# see: https://devdocs.prestashop-project.org/8/basics/installation/install-from-cli/
echo "* Starting the installer..."
sudo php -f "${PS_FOLDER}/install/index_cli.php" -- \
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
  --ssl=0 \
  "$([ "$INSTALL_MODULES" == "true" ] && echo "--modules=$(find "$PS_FOLDER"/modules/* -maxdepth 0 -type d -exec basename {} \; | paste -s -d ',')" || echo "" )"
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
killall mysqld | true

# 11. Copy the PrestaShop settings against a volume mount on $PS_FOLDER
PS_OPT_DIR=/var/opt/prestashop
mkdir -p "$PS_OPT_DIR"
if echo "$PS_VERSION" | grep "^1.6" > /dev/null; then
  cp "$PS_FOLDER/config/settings.inc.php" "$PS_OPT_DIR/settings.inc.php"
else
  mkdir -p "$PS_OPT_DIR"
  cp "$PS_FOLDER/app/config/parameters.php" "$PS_OPT_DIR/parameters.php"
fi

# 12. Some clean up
rm -rf \
  "$PS_FOLDER/install" \
  "$PS_FOLDER/Install_PrestaShop.html" \
  "$PS_CACHE_DIR" \
  "$PS_LOGS_DIR"
mkdir -p "$PS_CACHE_DIR" "$PS_LOGS_DIR"
chown -R www-data:www-data "$PS_CACHE_DIR" "$PS_LOGS_DIR"
