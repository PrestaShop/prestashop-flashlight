#!/bin/sh
set -euo pipefail

# 0. Configuration
PS_FOLDER=${PS_FOLDER:?missing PS_FOLDER}
export PS_DOMAIN="replace-me.com" \
  DB_SERVER=127.0.0.1 \
  DB_PORT=3306 \
  DB_NAME=prestashop \
  DB_USER=root \
  DB_PASSWD=prestashop \
  DB_PREFIX=ps_ \
  ADMIN_MAIL=admin@prestashop.com \
  ADMIN_PASSWD=prestashop \
  PS_LANGUAGE=en \
  PS_COUNTRY=GB \
  PS_ALL_LANGUAGES=0 \
  PS_INSTALL_AUTO=1 \
  PS_ERASE_DB=1 \
  PS_INSTALL_DB=1 \
  PS_ENABLE_SSL=0 \
  PS_FOLDER_ADMIN=ps-admin \
  PS_FOLDER_INSTALL=${PS_FOLDER}/install

# 1. Install MySQL
apk add -U \
  runuser \
  mysql \
  mysql-client

# 2. Start a MySQL server
# enable a socket + ip configuration
cat <<EOT >> /etc/my.cnf.d/mariadb-server.cnf
[server]
[mysqld]
bind-address = 127.0.0.1
skip-networking = 0
datadir = /var/lib/mysql/
EOT
mysql_install_db \
  --user=mysql \
  --ldata=/var/lib/mysql/ > /dev/null;
mkdir -p /run/mysqld;
nohup /usr/bin/mysqld --user=root &
while ! nc -z localhost ${DB_PORT}; do sleep 0.1; done
echo "✅ MySQL started"

# 3. Setup the root password, add a PrestaShop database and test the PDO link
mysql -u ${DB_USER} --password= -e "ALTER USER '"${DB_USER}"'@localhost IDENTIFIED BY '"${DB_PASSWD}"'; flush privileges;";
mysql -u ${DB_USER} --password=${DB_PASSWD} -e "CREATE DATABASE ${DB_NAME};";

# 4. Connectivity test
php -r "new PDO('mysql:unix_socket=/run/mysqld/mysqld.sock;dbname=prestashop', 'root', 'prestashop');"
php -r "new PDO('mysql:host=127.0.0.1;dbname=prestashop', 'root', 'prestashop');"
echo "✅ PHP PDO connectivity test"

# 5. Run the PrestaShop installer
# see: https://devdocs.prestashop-project.org/8/basics/installation/install-from-cli/
runuser -g www-data -u www-data -- \
  php -d memory_limit=-1 $PS_FOLDER_INSTALL/index_cli.php \
  --domain=$PS_DOMAIN \
  --db_create=1 \
  --db_server=$DB_SERVER \
  --db_name=$DB_NAME \
  --db_user=$DB_USER \
  --db_password=$DB_PASSWD \
  --prefix=$DB_PREFIX \
  --firstname=Admin \
  --lastname=PrestaShop \
  --password=$ADMIN_PASSWD \
  --email=$ADMIN_MAIL \
  --language=$PS_LANGUAGE \
  --country=$PS_COUNTRY \
  --all_languages=$PS_ALL_LANGUAGES \
  --newsletter=0 \
  --send_email=0 \
  --ssl=$PS_ENABLE_SSL;
echo "✅ PrestaShop installed"

# 6. Make a database dump
mysqldump -u ${DB_USER} --password=${DB_PASSWD} ${DB_NAME} > ${DUMP_FILE};
echo "✅ MySQL dump performed"

# 7. Tear down mysql
killall mysqld;

# 8. Cache clear
php -d memory_limit=-1 bin/console cache:clear

# 9. Some clean up
mv ${PS_FOLDER}/admin ${PS_FOLDER}/${PS_FOLDER_ADMIN}
