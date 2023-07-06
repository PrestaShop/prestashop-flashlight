#!/bin/sh
set -euo pipefail

DEBUG_MODE=${DEBUG_MODE:-false}
INIT_ON_RESTART=${INIT_ON_RESTART:-false}
DUMP_ON_RESTART=${DUMP_ON_RESTART:-false}
INSTALL_MODULES_ON_RESTART=${INSTALL_MODULES_ON_RESTART:-false}
INIT_SCRIPTS_ON_RESTART=${INIT_SCRIPTS_ON_RESTART:-false}
SSL_REDIRECT=${SSL_REDIRECT:-false}

INIT_LOCK=flashlight-init.lock
DUMP_LOCK=flashlight-dump.lock
MODULES_INSTALLED_LOCK=flashlight-modules-installed.lock
INIT_SCRIPTS_LOCK=flashlight-init-scripts.lock

if [ ! -f $INIT_LOCK ] || [ "$INIT_ON_RESTART" == "true" ]; then
  if [ -z "${PS_DOMAIN:-}" ] && [ -z "${NGROK_TUNNEL_AUTO_DETECT:-}" ]; then
    echo "Missing PS_DOMAIN or NGROK_TUNNEL_AUTO_DETECT. Exiting"
    sleep 3
    exit 2
  fi

  # Check if a tunnel autodetection mechanism should be involded
  if [ -n "${NGROK_TUNNEL_AUTO_DETECT+x}" ]; then
    echo "* Auto-detecting domain with ngrok client api on ${NGROK_TUNNEL_AUTO_DETECT}..."
    TUNNEL_API="${NGROK_TUNNEL_AUTO_DETECT}/api/tunnels"
    until $(curl --output /dev/null --max-time 5 --silent --head --fail ${TUNNEL_API}); do
      echo "* retrying in 5s..."
      sleep 5
    done
    PUBLIC_URL=$(curl -s ${TUNNEL_API} | jq -r .tunnels[0].public_url)
    PS_DOMAIN=$(echo $PUBLIC_URL | sed 's/https\?:\/\///')
    case $PUBLIC_URL in https*)
      SSL_REDIRECT="true"
    esac
    if [ -z "${PS_DOMAIN:-}" ]; then
      echo "Error: cannot guess ngrok domain. Exiting"
      sleep 3
      exit 3
    else
      echo "* ngrok tunnel found running on ${PS_DOMAIN}"
    fi
  fi

  echo "* Applying PS_DOMAIN ($PS_DOMAIN) to the dump..."
  sed -i "s/replace-me.com/$PS_DOMAIN/g" /dump.sql
  export PS_DOMAIN=$PS_DOMAIN

  if [ "$SSL_REDIRECT" == "true" ]; then
    echo "* Enabling SSL redirect to the dump..."
    sed -i "s/'PS_SSL_ENABLED','0'/'PS_SSL_ENABLED','1'/" /dump.sql
    sed -i "s/'PS_SSL_ENABLED_EVERYWHERE','0'/'PS_SSL_ENABLED_EVERYWHERE','1'/" /dump.sql
  fi

  # Configure the DBO parameters
  MYSQL_VERSION=${MYSQL_VERSION:-5.7}
  sed -i \
      -e "s/host' => '127.0.0.1'/host' => '$MYSQL_HOST'/" \
      -e "s/port' => ''/port' => '$MYSQL_PORT'/" \
      -e "s/name' => 'prestashop'/name' => '$MYSQL_DATABASE'/" \
      -e "s/user' => 'root'/user' => '$MYSQL_USER'/" \
      -e "s/password' => 'prestashop'/password' => '$MYSQL_PASSWORD'/" \
      -e "s/database_engine' => 'InnoDB',/database_engine' => 'InnoDB',\n    'server_version' => '$MYSQL_VERSION',/" \
    $PS_FOLDER/app/config/parameters.php

  # If debug mode is enabled
  CACHE_DIR=/var/www/html/var/cache
  if [ "$DEBUG_MODE" == "true" ]; then
    sed -ie "s/define('_PS_MODE_DEV_', false);/define('_PS_MODE_DEV_',\ true);/g" $PS_FOLDER/config/defines.inc.php
    CACHE_DIR=${CACHE_DIR}/dev
  else
    CACHE_DIR=${CACHE_DIR}/prod
  fi
  mkdir -p ${CACHE_DIR} && chown -R www-data:www-data ${CACHE_DIR}

  touch $INIT_LOCK
else
  echo "* Init already performed (see INIT_ON_RESTART)"
fi

# Restoring MySQL dump and extras dumps if any
if [ ! -f $DUMP_LOCK ] || [ "$DUMP_ON_RESTART" == "true" ]; then
  echo "* Restoring MySQL dump..."
  mysql -u ${MYSQL_USER} --host=${MYSQL_HOST} --password=${MYSQL_PASSWORD} ${MYSQL_DATABASE} < /dump.sql
  echo "* MySQL dump restored!"
  if [ -n "$MYSQL_EXTRA_DUMP" ]; then
    echo "* Restoring MySQL EXTRA dump(s)..."
    mysql -u ${MYSQL_USER} --host=${MYSQL_HOST} --password=${MYSQL_PASSWORD} ${MYSQL_DATABASE} < $MYSQL_EXTRA_DUMP
  fi
  touch $DUMP_LOCK
else
  echo "* Dump already performed (see DUMP_ON_RESTART)"
fi

# Eventually install some modules
if [ ! -f $MODULES_INSTALLED_LOCK ] || [ "$INSTALL_MODULES_ON_RESTART" ]; then
  if [ -n "${INSTALL_MODULES_DIR+x}" ]; then
    INSTALL_COMMAND="/var/www/html/bin/console prestashop:module --no-interaction install"
    for file in $(ls ${INSTALL_MODULES_DIR}/*.zip); do
      module=$(basename ${file} | tr "-" "\n" | head -n 1)
      echo "--> unzipping and installing ${module} from ${file}..."
      rm -rf "/var/www/html/modules/${module:-something-at-least}"
      unzip -qq ${file} -d /var/www/html/modules
      php $INSTALL_COMMAND ${module}
    done;
    chown -R www-data:www-data /var/www/html/modules /var/www/html/var/cache
  fi
  touch $MODULES_INSTALLED_LOCK
else
  echo "* Module installation already performed (see INSTALL_MODULES_ON_RESTART)"
fi

# Custom init scripts
if [ ! -f $INIT_SCRIPTS_LOCK ] || [ "$INIT_SCRIPTS_ON_RESTART" == "true" ]; then
  if [ -d /tmp/init-scripts/ ]; then
    echo "* Running init script(s)..."
    for i in `ls /tmp/init-scripts/`;do
      /tmp/init-scripts/$i
    done
  else
    echo "* No init script found, let's continue..."
  fi
  touch $INIT_SCRIPTS_LOCK
else
  echo "* Init scripts already run (see INIT_SCRIPTS_ON_RESTART)"
fi

echo "* Starting php-fpm..."
su www-data -s /usr/local/sbin/php-fpm -c '-D'

echo "* Starting nginx..."
nginx -g "daemon off;"
