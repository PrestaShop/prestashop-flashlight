#!/bin/sh
set -eu

export BLACKFIRE_ENABLED="${BLACKFIRE_ENABLED:-false}"
export DEBUG_MODE="${DEBUG_MODE:-false}"
export DRY_RUN="${DRY_RUN:-false}"
export DUMP_ON_RESTART="${DUMP_ON_RESTART:-false}"
export INIT_ON_RESTART="${INIT_ON_RESTART:-false}"
export INIT_SCRIPTS_DIR="${INIT_SCRIPTS_DIR:-/tmp/init-scripts/}"
export INIT_SCRIPTS_ON_RESTART="${INIT_SCRIPTS_ON_RESTART:-false}"
export INIT_SCRIPTS_USER="${INIT_SCRIPTS_USER:-www-data}"
export INSTALL_MODULES_DIR="${INSTALL_MODULES_DIR:-}"
export INSTALL_MODULES_ON_RESTART="${INSTALL_MODULES_ON_RESTART:-false}"
export MYSQL_VERSION="${MYSQL_VERSION:-5.7}"
export ON_INIT_SCRIPT_FAILURE="${ON_INIT_SCRIPT_FAILURE:-fail}"
export ON_INSTALL_MODULES_FAILURE="${ON_INSTALL_MODULES_FAILURE:-fail}"
export POST_SCRIPTS_DIR="${POST_SCRIPTS_DIR:-/tmp/post-scripts/}"
export POST_SCRIPTS_ON_RESTART="${POST_SCRIPTS_ON_RESTART:-false}"
export POST_SCRIPTS_USER="${POST_SCRIPTS_USER:-www-data}"
export PS_PROTOCOL="${PS_PROTOCOL:-http}"
export SSL_REDIRECT="${SSL_REDIRECT:-false}"
export XDEBUG_ENABLED="${XDEBUG_ENABLED:-false}"

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
  if [ -n "${PS_DOMAIN:-}" ]; then
    case "$PS_DOMAIN" in
      http*) echo "PS_DOMAIN is not expected to be an URI"; sleep 3; exit 2 ;;
    esac
  elif [ -z "${NGROK_TUNNEL_AUTO_DETECT:-}" ]; then
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
  sed -i "s~localhost:80~$PS_DOMAIN~g" /dump.sql
  export PS_DOMAIN="$PS_DOMAIN"

  # Note: use PS_TRUSTED_PROXIES for PrestaShop > 9 since bbdee4b6d07cf4c40787c95b8c948b04506208fd
  # Note: PS_SSL_ENABLED_EVERYWHERE was missing in ps_configuration in 1.7.2.5
  [ "$SSL_REDIRECT" = "true" ] && PS_PROTOCOL="https";
  if [ "$PS_PROTOCOL" = "https" ]; then
    echo "* Enabling SSL redirection and any local proxy..."
cat >> /dump.sql << END
INSERT INTO ps_configuration (id_configuration, id_shop_group, id_shop, name, value, date_add, date_upd)
VALUES (NULL, NULL, NULL, "PS_SSL_ENABLED", "1", NOW(), NOW()),
(NULL, NULL, NULL, "PS_SSL_ENABLED_EVERYWHERE", "1", NOW(), NOW()),
(NULL, NULL, NULL, "PS_TRUSTED_PROXIES", "127.0.0.1,REMOTE_ADDR", NOW(), NOW())
ON DUPLICATE KEY UPDATE
  value = VALUES(value),
  date_upd = VALUES(date_upd);
END
    export SSL_REDIRECT="true";
    export PS_TRUSTED_PROXIES="127.0.0.1,REMOTE_ADDR";
    touch "$PS_FOLDER/.env"
    echo 'SSL_REDIRECT=true' >> "$PS_FOLDER/.env"
    echo 'PS_TRUSTED_PROXIES=127.0.0.1,REMOTE_ADDR' >> "$PS_FOLDER/.env"
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
    echo "⚠ Warning: PrestaShop config file not found, using our backup plan!"
    if [ -d "$(dirname "$PS_CONFIG_PARAMETERS")" ]; then
      cp /var/opt/prestashop/parameters.php "$PS_CONFIG_PARAMETERS"
    else
      cp /var/opt/prestashop/settings.inc.php "$PS_16_CONFIG_PARAMETERS"
    fi
  fi

  if [ -f "$PS_CONFIG_PARAMETERS" ]; then
    [ ! -f "$PS_CONFIG_PARAMETERS.bak" ] && cp "$PS_CONFIG_PARAMETERS" "$PS_CONFIG_PARAMETERS.bak";
    run_user sed -i \
        -e "s~host' => '127.0.0.1'~host' => '$MYSQL_HOST'~" \
        -e "s~port' => ''~port' => '$MYSQL_PORT'~" \
        -e "s~name' => 'prestashop'~name' => '$MYSQL_DATABASE'~" \
        -e "s~user' => 'root'~user' => '$MYSQL_USER'~" \
        -e "s~password' => 'prestashop'~password' => '$MYSQL_PASSWORD'~" \
        -e "s~database_engine' => 'InnoDB',~database_engine' => 'InnoDB',\n    'server_version' => '$MYSQL_VERSION',~" \
      "$PS_FOLDER/app/config/parameters.php"
  elif [ -f "$PS_16_CONFIG_PARAMETERS" ]; then
    [ ! -f "$PS_16_CONFIG_PARAMETERS.bak" ] && cp "$PS_16_CONFIG_PARAMETERS" "$PS_16_CONFIG_PARAMETERS.bak";
    run_user sed -i \
        -e "s~127.0.0.1:3306~$MYSQL_HOST:$MYSQL_PORT~" \
        -e "s~_DB_NAME_', 'prestashop~_DB_NAME_', '$MYSQL_DATABASE~" \
        -e "s~_DB_USER_', 'root~_DB_USER_', '$MYSQL_USER~" \
        -e "s~_DB_PASSWD_', 'prestashop~_DB_PASSWD_', '$MYSQL_PASSWORD~" \
      "$PS_16_CONFIG_PARAMETERS"
  fi
  echo "* PrestaShop MySQL configuration set"

  # If debug mode is enabled
  if [ "$DEBUG_MODE" = "true" ]; then
    sed -ie "s~define('_PS_MODE_DEV_', false);~define('_PS_MODE_DEV_',\ true);~g" "$PS_FOLDER/config/defines.inc.php"
    echo "* Debug mode set"
  fi

  # If Xdebug is enabled
  if [ "$XDEBUG_ENABLED" = "true" ]; then
    sed -ie 's~^;~~g' "$PHP_INI_DIR/conf.d/docker-php-ext-xdebug.ini"
    echo "* Xdebug enabled"
  fi

  if [ "$BLACKFIRE_ENABLED" = "true" ]; then
    sed -i 's~^;$~~g' "$PHP_INI_DIR/conf.d/blackfire.ini"
    echo "* Blackfire enabled"
  else
    sed -i -E 's~^(.+)$~;\1~g' "$PHP_INI_DIR/conf.d/blackfire.ini"
    echo "* Blackfire disabled"
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
  if [ -d "$INSTALL_MODULES_DIR" ]; then
    if [ -f "$PS_FOLDER/bin/console" ]; then
      for file in "$INSTALL_MODULES_DIR"/*.zip; do
        module=$(unzip -l "$file" | awk 'NR==4{print $4}' | sed 's/\/$//' | tr "-" "\n" | head -n 1)
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
if [ -d "$INIT_SCRIPTS_DIR" ]; then
  if [ ! -f $INIT_SCRIPTS_LOCK ] || [ "$INIT_SCRIPTS_ON_RESTART" = "true" ]; then
    printf "* Running init-script(s)..."
    # shellcheck disable=SC2016
    find "$INIT_SCRIPTS_DIR" -maxdepth 1 -executable -type f -print0 | sort -z | xargs -0 -n1 sh -c '
      printf "\n--> Running $1...\n"
      if [ "$ON_INIT_SCRIPT_FAILURE" = "continue" ]; then
        (sudo -E -g '"$INIT_SCRIPTS_USER"' -u '"$INIT_SCRIPTS_USER"' -- $1) || { echo "x $1 execution failed. Skipping."; }
      else
        (sudo -E -g '"$INIT_SCRIPTS_USER"' -u '"$INIT_SCRIPTS_USER"' -- $1) || { echo "x $1 execution failed. Sleep and exit."; sleep 10; exit 7; }
      fi
    ' sh | awk 'BEGIN{RS="\n";ORS="\n  "}1';
    printf "\n";
  else
    echo "* Init scripts already run (see INIT_SCRIPTS_ON_RESTART)"
  fi
  touch $INIT_SCRIPTS_LOCK
else
  echo "* No init-script(s) found"
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
if [ -d "$POST_SCRIPTS_DIR" ]; then
  if [ ! -f $POST_SCRIPTS_LOCK ] || [ "$POST_SCRIPTS_ON_RESTART" = "true" ]; then
    printf "* Running post-script(s)..."
    # shellcheck disable=SC2016
    find "$POST_SCRIPTS_DIR" -maxdepth 1 -executable -type f -print0 | sort -z | xargs -0 -n1 sh -c '
      printf "\n--> Running $1...\n"
      if [ "$ON_POST_SCRIPT_FAILURE" = "continue" ]; then
        (sudo -E -g '"$POST_SCRIPTS_USER"' -u '"$POST_SCRIPTS_USER"' -- $1) || { echo "x $1 execution failed. Skipping."; }
      else
        (sudo -E -g '"$POST_SCRIPTS_USER"' -u '"$POST_SCRIPTS_USER"' -- $1) || { echo "x $1 execution failed. Sleep and exit."; sleep 10; exit 8; }
      fi
    ' sh | awk 'BEGIN{RS="\n";ORS="\n  "}1';
    printf "\n";
  else
    echo "* Post scripts already run (see POST_SCRIPTS_ON_RESTART)"
  fi
  touch $POST_SCRIPTS_LOCK
else
  echo "* No post-script(s) found"
fi

# set back nginx to front process
wait $NGINX_PID
