#!/bin/sh
set -eu

DRY_RUN=${DRY_RUN:-false}
DEBUG_MODE=${DEBUG_MODE:-false}
INIT_ON_RESTART=${INIT_ON_RESTART:-false}
DUMP_ON_RESTART=${DUMP_ON_RESTART:-false}
INSTALL_MODULES_ON_RESTART=${INSTALL_MODULES_ON_RESTART:-false}
INIT_SCRIPTS_ON_RESTART=${INIT_SCRIPTS_ON_RESTART:-false}
SSL_REDIRECT=${SSL_REDIRECT:-false}
ON_INIT_SCRIPT_FAILURE=${ON_INIT_SCRIPT_FAILURE:-fail}
MYSQL_VERSION=${MYSQL_VERSION:-5.7}

INIT_LOCK=flashlight-init.lock
DUMP_LOCK=flashlight-dump.lock
MODULES_INSTALLED_LOCK=flashlight-modules-installed.lock
INIT_SCRIPTS_LOCK=flashlight-init-scripts.lock

if [ ! -f $INIT_LOCK ] || [ "$INIT_ON_RESTART" = "true" ]; then
  if [ -z "${PS_DOMAIN:-}" ] && [ -z "${NGROK_TUNNEL_AUTO_DETECT:-}" ]; then
    echo "Missing PS_DOMAIN or NGROK_TUNNEL_AUTO_DETECT. Exiting"
    sleep 3
    exit 2
  fi

  # Check if a tunnel autodetection mechanism should be involved
  if [ -n "${NGROK_TUNNEL_AUTO_DETECT+x}" ]; then
    echo "* Auto-detecting domain with ngrok client api on ${NGROK_TUNNEL_AUTO_DETECT}..."
    TUNNEL_API="${NGROK_TUNNEL_AUTO_DETECT}/api/tunnels"
    until curl --output /dev/null --max-time 5 --silent --head --fail "$TUNNEL_API"; do
      echo "* retrying in 5s..."
      sleep 5
    done
    PUBLIC_URL=$(curl -s "$TUNNEL_API" | jq -r .tunnels[0].public_url)
    PS_DOMAIN=$(echo "$PUBLIC_URL" | sed 's/https\?:\/\///')
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
  export PS_DOMAIN="$PS_DOMAIN"

  if [ "$SSL_REDIRECT" = "true" ]; then
    echo "* Enabling SSL redirect to the dump..."
    sed -i "s/'PS_SSL_ENABLED','0'/'PS_SSL_ENABLED','1'/" /dump.sql
    sed -i "s/'PS_SSL_ENABLED_EVERYWHERE','0'/'PS_SSL_ENABLED_EVERYWHERE','1'/" /dump.sql
  fi

  echo "* Checking MySQL connectivity..."
  is_mysql_ready () {
    if [ "$DRY_RUN" = "true" ]; then
      echo "(skipped)";
    else
      php -r "new PDO('mysql:host=""${MYSQL_HOST}"";port=""${MYSQL_PORT}"";dbname=""${MYSQL_DATABASE}""', '""${MYSQL_USER}""', '""${MYSQL_PASSWORD}""');"
    fi
  }
  while ! is_mysql_ready; do echo "Cannot connect to MySQL, retrying in 1s..."; sleep 1; done
  echo "* PHP PDO connectivity checked"

  if [ -f "$PS_FOLDER/app/config/parameters.php" ]; then
    sed -i \
        -e "s/host' => '127.0.0.1'/host' => '$MYSQL_HOST'/" \
        -e "s/port' => ''/port' => '$MYSQL_PORT'/" \
        -e "s/name' => 'prestashop'/name' => '$MYSQL_DATABASE'/" \
        -e "s/user' => 'root'/user' => '$MYSQL_USER'/" \
        -e "s/password' => 'prestashop'/password' => '$MYSQL_PASSWORD'/" \
        -e "s/database_engine' => 'InnoDB',/database_engine' => 'InnoDB',\n    'server_version' => '$MYSQL_VERSION',/" \
      "$PS_FOLDER/app/config/parameters.php"
  elif [ -f "$PS_FOLDER/config/settings.inc.php" ]; then
    sed -i \
        -e "s/127.0.0.1:3306/$MYSQL_HOST:$MYSQL_PORT/" \
        -e "s/_DB_NAME_', 'prestashop/_DB_NAME_', '$MYSQL_DATABASE/" \
        -e "s/_DB_USER_', 'root/_DB_USER_', '$MYSQL_USER/" \
        -e "s/_DB_PASSWD_', 'prestashop/_DB_PASSWD_', '$MYSQL_PASSWORD/" \
      "$PS_FOLDER/config/settings.inc.php"
  else
    echo "Error: could not configure PrestaShop (config file not found). Exiting"
    sleep 3
    exit 4
  fi
  echo "* PrestaShop MySQL client configuration set"

  # If debug mode is enabled
  if [ "$DEBUG_MODE" = "true" ]; then
    sed -ie "s/define('_PS_MODE_DEV_', false);/define('_PS_MODE_DEV_',\ true);/g" "$PS_FOLDER/config/defines.inc.php"
    echo "* Debug mode set"
  fi
  touch $INIT_LOCK
else
  echo "* Init already performed (see INIT_ON_RESTART)"
fi

# Restoring MySQL dumps
if [ ! -f $DUMP_LOCK ] || [ "$DUMP_ON_RESTART" = "true" ]; then
  echo "* Restoring MySQL dump..."
  [ ! -f "/dump.sql" ] && echo "Error: missing dump. Exiting" && exit 5
  if [ "$DRY_RUN" = "true" ]; then
    echo "(skipped)";
  else
    mysql -u "$MYSQL_USER" --host="$MYSQL_HOST" --password="$MYSQL_PASSWORD" "$MYSQL_DATABASE" < /dump.sql
  fi
  echo "* MySQL dump restored!"
  if [ -n "$MYSQL_EXTRA_DUMP" ]; then
    echo "* Restoring MySQL EXTRA dump(s)..."
    mysql -u "$MYSQL_USER" --host="$MYSQL_HOST" --password="$MYSQL_PASSWORD" "$MYSQL_DATABASE" < "$MYSQL_EXTRA_DUMP"
  fi
  touch $DUMP_LOCK
else
  echo "* Dump already performed (see DUMP_ON_RESTART)"
fi

# Eventually install some modules
if [ ! -f $MODULES_INSTALLED_LOCK ] || [ "$INSTALL_MODULES_ON_RESTART" = "true" ]; then
  if [ -n "${INSTALL_MODULES_DIR+x}" ]; then
    INSTALL_COMMAND="/var/www/html/bin/console prestashop:module --no-interaction install"
    for file in "$INSTALL_MODULES_DIR"/*.zip; do
      module=$(basename "$file" | tr "-" "\n" | head -n 1)
      echo "--> Unzipping and installing ${module} from ${file}..."
      rm -rf "/var/www/html/modules/${module:-something-at-least}"
      su www-data -s /bin/sh -c "unzip -qq ${file} -d /var/www/html/modules"
      su www-data -s /bin/sh -c "php $INSTALL_COMMAND ${module}"
    done;
  fi
  touch $MODULES_INSTALLED_LOCK
else
  echo "* Module installation already performed (see INSTALL_MODULES_ON_RESTART)"
fi

# Custom init scripts
if [ ! -f $INIT_SCRIPTS_LOCK ] || [ "$INIT_SCRIPTS_ON_RESTART" = "true" ]; then
  if [ -d /tmp/init-scripts/ ]; then
    echo "* Running init script(s)..."
    find /tmp/init-scripts -maxdepth 1 -executable -type f -exec sh -c '
      echo "--> Running $1..."
      if [ "$ON_INIT_SCRIPT_FAILURE" = "continue" ]; then
        ( $1 ) || { echo "x $1 execution failed. Skipping."; }
      else
        $1 || { echo "x $1 execution failed. Sleep and exit."; sleep 10; exit 6; }
      fi
    ' sh {} \; print;
  else
    echo "* No init script found, let's continue..."
  fi
  touch $INIT_SCRIPTS_LOCK
else
  echo "* Init scripts already run (see INIT_SCRIPTS_ON_RESTART)"
fi

if [ "$DRY_RUN" = "true" ]; then
  echo "* Dry run is sucessful! Exiting."
  exit 0
fi

echo "* Starting php-fpm..."
su www-data -s /usr/local/sbin/php-fpm -c '-D'

echo "* Starting nginx..."
nginx -g "daemon off;"
