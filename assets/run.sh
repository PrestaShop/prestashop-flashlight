#!/bin/sh
set -eu

DRY_RUN=${DRY_RUN:-false}
DEBUG_MODE=${DEBUG_MODE:-false}
INIT_ON_RESTART=${INIT_ON_RESTART:-false}
DUMP_ON_RESTART=${DUMP_ON_RESTART:-false}
INSTALL_MODULES_ON_RESTART=${INSTALL_MODULES_ON_RESTART:-false}
INIT_SCRIPTS_ON_RESTART=${INIT_SCRIPTS_ON_RESTART:-false}
POST_SCRIPTS_ON_RESTART=${POST_SCRIPTS_ON_RESTART:-false}
SSL_REDIRECT=${SSL_REDIRECT:-false}
ON_INIT_SCRIPT_FAILURE=${ON_INIT_SCRIPT_FAILURE:-fail}
ON_INSTALL_MODULES_FAILURE=${ON_INSTALL_MODULES_FAILURE:-fail}
MYSQL_VERSION=${MYSQL_VERSION:-5.7}
INIT_SCRIPTS_DIR=${INIT_SCRIPTS_DIR:-/tmp/init-scripts/}
POST_SCRIPTS_DIR=${POST_SCRIPTS_DIR:-/tmp/post-scripts/}

INIT_LOCK=/tmp/flashlight-init.lock
DUMP_LOCK=/tmp/flashlight-dump.lock
MODULES_INSTALLED_LOCK=/tmp/flashlight-modules-installed.lock
INIT_SCRIPTS_LOCK=/tmp/flashlight-init-scripts.lock
POST_SCRIPTS_LOCK=/tmp/flashlight-post-scripts.lock

# Runs everything as www-data
run_user () {
  sudo -g www-data -u www-data -- "$@"
}

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
      run_user php -r "new PDO('mysql:host=""${MYSQL_HOST}"";port=""${MYSQL_PORT}"";dbname=""${MYSQL_DATABASE}""', '""${MYSQL_USER}""', '""${MYSQL_PASSWORD}""');" 2> /dev/null;
    fi
  }
  while ! is_mysql_ready; do echo "Cannot connect to MySQL, retrying in 1s..."; sleep 1; done
  echo "* PHP PDO connectivity checked"

  echo "* Editing PrestaShop configuration..."
  PS_CONFIG_PARAMETERS="$PS_FOLDER/app/config/parameters.php"
  PS_16_CONFIG_PARAMETERS="$PS_FOLDER/config/settings.inc.php"

  # User is probably doing a volume mount on $PS_FOLDER
  if [ ! -f "$PS_FOLDER/app/config/parameters.php" ] && [ ! -f "$PS_FOLDER/config/settings.inc.php" ]; then 
    echo "Warning: could not configure PrestaShop (config file not found). Using our backup plan!"
    if [ -d "$(dirname "$PS_CONFIG_PARAMETERS")" ]; then
      cp /var/opt/prestashop/parameters.php "$PS_CONFIG_PARAMETERS"
    else 
      cp /var/opt/prestashop/parameters.php "$PS_16_CONFIG_PARAMETERS"
    fi
  fi

  if [ -f "$PS_CONFIG_PARAMETERS" ]; then
    [ ! -f "$PS_CONFIG_PARAMETERS.bak" ] && cp "$PS_CONFIG_PARAMETERS" "$PS_CONFIG_PARAMETERS.bak";
    run_user sed -i \
        -e "s/host' => '127.0.0.1'/host' => '$MYSQL_HOST'/" \
        -e "s/port' => ''/port' => '$MYSQL_PORT'/" \
        -e "s/name' => 'prestashop'/name' => '$MYSQL_DATABASE'/" \
        -e "s/user' => 'root'/user' => '$MYSQL_USER'/" \
        -e "s/password' => 'prestashop'/password' => '$MYSQL_PASSWORD'/" \
        -e "s/database_engine' => 'InnoDB',/database_engine' => 'InnoDB',\n    'server_version' => '$MYSQL_VERSION',/" \
      "$PS_FOLDER/app/config/parameters.php"
  elif [ -f "$PS_16_CONFIG_PARAMETERS" ]; then
    [ ! -f "$PS_16_CONFIG_PARAMETERS.bak" ] && cp "$PS_16_CONFIG_PARAMETERS" "$PS_16_CONFIG_PARAMETERS.bak";
    run_user sed -i \
        -e "s/127.0.0.1:3306/$MYSQL_HOST:$MYSQL_PORT/" \
        -e "s/_DB_NAME_', 'prestashop/_DB_NAME_', '$MYSQL_DATABASE/" \
        -e "s/_DB_USER_', 'root/_DB_USER_', '$MYSQL_USER/" \
        -e "s/_DB_PASSWD_', 'prestashop/_DB_PASSWD_', '$MYSQL_PASSWORD/" \
      "$PS_16_CONFIG_PARAMETERS"
  fi
  echo "* PrestaShop MySQL configuration set"

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
    if [ -f "$PS_FOLDER/bin/console" ]; then
      for file in "$INSTALL_MODULES_DIR"/*.zip; do
        module=$(basename "$file" | tr "-" "\n" | head -n 1)
        echo "--> Unzipping and installing $module from $file..."
        rm -rf "/var/www/html/modules/${module:-something-at-least}"
        run_user unzip -qq "$file" -d /var/www/html/modules
        if [ "$ON_INSTALL_MODULES_FAILURE" = "continue" ]; then
          (run_user php -d memory_limit=-1 bin/console prestashop:module --no-interaction install "$module") || { echo "x module installation failed. Skipping."; }
        else
          (run_user php -d memory_limit=-1 bin/console prestashop:module --no-interaction install "$module") || { echo "x module installation failed. Sleep and exit."; sleep 10; exit 6; }
        fi
      done;
    else
      echo "Auto-installing modules with PrestaShop v1.6 is not yet supported";
    fi
  fi
  touch $MODULES_INSTALLED_LOCK
else
  echo "* Module installation already performed (see INSTALL_MODULES_ON_RESTART)"
fi

# Init scripts
if [ ! -f $INIT_SCRIPTS_LOCK ] || [ "$INIT_SCRIPTS_ON_RESTART" = "true" ]; then
  if [ -d "$INIT_SCRIPTS_DIR" ]; then
    printf "* Running init script(s)..."
    # shellcheck disable=SC2016
    find "$INIT_SCRIPTS_DIR" -maxdepth 1 -executable -type f -print0 | sort -z | xargs -0 -n1 sh -c '
      printf "\n--> Running $1...\n"
      if [ "$ON_INIT_SCRIPT_FAILURE" = "continue" ]; then
        (sudo -E -g www-data -u www-data -- $1) || { echo "x $1 execution failed. Skipping."; }
      else
        (sudo -E -g www-data -u www-data -- $1) || { echo "x $1 execution failed. Sleep and exit."; sleep 10; exit 7; }
      fi
    ' sh | awk 'BEGIN{RS="\n";ORS="\n  "}1';
    printf "\n";
  else
    echo "* No init script(s) found"
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
run_user php-fpm -D

echo "* Starting nginx..."
nginx -g "daemon off;" &
NGINX_PID=$!
sleep 1;
echo "* Nginx started"

# Post-run scripts
if [ ! -f $POST_SCRIPTS_LOCK ] || [ "$POST_SCRIPTS_ON_RESTART" = "true" ]; then
  if [ -d "$POST_SCRIPTS_DIR" ]; then
    printf "* Running post script(s)..."
    # shellcheck disable=SC2016
    find "$POST_SCRIPTS_DIR" -maxdepth 1 -executable -type f -print0 | sort -z | xargs -0 -n1 sh -c '
      printf "\n--> Running $1...\n"
      if [ "$ON_POST_SCRIPT_FAILURE" = "continue" ]; then
        (sudo -E -g www-data -u www-data -- $1) || { echo "x $1 execution failed. Skipping."; }
      else
        (sudo -E -g www-data -u www-data -- $1) || { echo "x $1 execution failed. Sleep and exit."; sleep 10; exit 8; }
      fi
    ' sh | awk 'BEGIN{RS="\n";ORS="\n  "}1';
    printf "\n";
  else
    echo "* No post script(s) found"
  fi
  touch $POST_SCRIPTS_LOCK
else
  echo "* Post scripts already run (see POST_SCRIPTS_ON_RESTART)"
fi

# set back nginx to front process
wait $NGINX_PID
