#!/bin/sh
set -euo pipefail

# Check if a tunnel autodetection mechanism should be involded
if [ ! -z "$NGROK_TUNNEL_AUTO_DETECT" ]; then
  echo "* Auto-detecting Ngrok on ${NGROK_TUNNEL_AUTO_DETECT}..."
  PS_DOMAIN=$( \
    curl -s 'http://ngrok:4040/api/tunnels' \
    | jq -r .tunnels[0].public_url \
    | sed 's/https\?:\/\///' \
  )
  if [ -z "$PS_DOMAIN" ]; then
    echo "Error: cannot guess ngrok domain. Exiting" && exit 2;
  else
    echo "* ngrok tunnel running on ${$PS_DOMAIN}"
  fi
# Static PS_DOMAIN assignment
else if [[ ! -z "$PS_DOMAIN" ]]; then
  echo "* Applying PS_DOMAIN ($PS_DOMAIN) to the dump"
  sed -i s/replace-me.com/$PS_DOMAIN/g /dump.sql
else
  echo "Missing $PS_DOMAIN or $NGROK_TUNNEL_AUTO_DETECT variable. Exiting"
  sleep 1
  exit 2
fi

# Configure the DBO parameters
sed -i \
    -e "s/host' => '127.0.0.1'/host' => '$MYSQL_HOST'/" \
    -e "s/port' => ''/port' => '$MYSQL_PORT'/" \
    -e "s/name' => 'prestashop'/name' => '$MYSQL_DATABASE'/" \
    -e "s/user' => 'root'/user' => '$MYSQL_USER'/" \
    -e "s/password' => 'prestashop'/password' => '$MYSQL_PASSWORD'/" \
  $PS_FOLDER/app/config/parameters.php

# Restoring MySQL dump
mysql -u ${MYSQL_USER} --host=${MYSQL_HOST} --password=${MYSQL_PASSWORD} ${MYSQL_DATABASE} < /dump.sql
echo "* MySQL dump restored!"

# Restoring extra MySQL dump if any
if [ -n "$MYSQL_EXTRA_DUMP" ]; then
  echo "* Restoring MySQL EXTRA dump(s)..."
  mysql -u ${MYSQL_USER} --host=${MYSQL_HOST} --password=${MYSQL_PASSWORD} ${MYSQL_DATABASE} < $MYSQL_EXTRA_DUMP
fi

# Debug mode if enabled
if [ "$DEBUG_MODE" == "true" ] || [ "$DEBUG_MODE" == "1" ]; then
  sed -ie "s/define('_PS_MODE_DEV_', false);/define('_PS_MODE_DEV_',\ true);/g" $PS_FOLDER/config/defines.inc.php
fi;

# Init scripts
if [ -d /tmp/init-scripts/ ]; then
  echo "* Running init script(s)..."
  for i in `ls /tmp/init-scripts/`;do
    /tmp/init-scripts/$i
  done
else
  echo "* No init script found, let's continue..."
fi

# Eventually install some modules
if [ ! -z "$INSTALL_MODULES_DIR" ]; then
  INSTALL_COMMAND="/var/www/html/bin/console prestashop:module --no-interaction install"
  for file in $(ls ${INSTALL_MODULES_DIR}/*.zip); do
    module=$(basename ${file} | tr "-" "\n" | head -n 1);
    echo "--> unzipping ${module} from ${file}...";
    rm -rf "/var/www/html/modules/${module:-something-at-least}"
    unzip -qq ${file} -d /var/www/html/modules
    echo "--> installing ${module}...";
    php $INSTALL_COMMAND ${module}
  done;
  chown -R www-data:www-data /var/www/html/modules
fi

echo "* Starting php-fpm..."
# su www-data -s /usr/local/sbin/php-fpm -c '-D'
php-fpm -D --allow-to-run-as-root

echo "* Starting nginx..."
nginx -g "daemon off;"
