#!/bin/sh
set -eu

# Install base tools, PHP requirements and dev-tools
PHP_COMMON=$(apk search -a 'php-common' | awk 'NR==1{print $1}')
PHP_ICONV=$(apk search -a 'php-iconv' | awk 'NR==1{print $1}')
PHP_GD=$(apk search -a 'php-gd' | awk 'NR==1{print $1}')
packages="bash less vim geoip git tzdata zip curl jq autoconf findutils \
  ca-certificates \
  mariadb-client sudo libjpeg libxml2 \
  build-base linux-headers freetype-dev zlib-dev libjpeg-turbo-dev \
  libpng-dev oniguruma-dev libzip-dev icu-dev libmcrypt-dev libxml2-dev \
  openssh-client libcap shadow $PHP_COMMON $PHP_ICONV $PHP_GD"

if [ "$SERVER_FLAVOUR" = "nginx" ]; then
  packages="$packages nginx nginx-mod-http-headers-more nginx-mod-http-geoip nginx-mod-stream nginx-mod-stream-geoip"
else
  packages="$packages apache2 apache2-proxy"
fi

# shellcheck disable=SC2086
set -- $packages
apk --no-cache add -U "$@"

# Help mapping to Linux users' host
usermod -u 1000 www-data
groupmod -g 1000 www-data

# Configure php-fpm
/tmp/php-configuration.sh
rm -rf /var/log/php* /etc/php*/php-fpm.conf /etc/php*/php-fpm.d
mkdir -p /var/log/php /var/run/php
chown -R www-data:www-data /var/log/php /var/run/php "$PHP_INI_DIR" /var/opt/prestashop

# Configure server
if [ "$SERVER_FLAVOUR" = "nginx" ]; then
  rm -rf /etc/apache2

  NGINX_CONF="/etc/nginx/nginx.conf"

  if nginx -t 2>&1 | grep -q 'http2" directive is deprecated'; then
    sed -i '/listen 443 ssl http2;/d' "$NGINX_CONF"
    sed -i 's~# listen 443 ssl;~listen 443 ssl;~' "$NGINX_CONF"
    sed -i 's~# http2 on;~http2 on;~' "$NGINX_CONF"
  fi

  mkdir -p /var/run/nginx /var/log/nginx /var/tmp/nginx
  touch /var/log/nginx/access.log /var/log/nginx/error.log
  chown -R www-data:www-data /var/run/nginx /var/log/nginx /var/tmp/nginx /var/lib/nginx
  setcap cap_net_bind_service=+ep /usr/sbin/nginx
else

  a2enmod() {
    while test $# -gt 0; do
      MODULE="$1"
      echo "Enabling module $MODULE"
      sed -i "/^#LoadModule ${MODULE}_module/s/^#//g" /etc/apache2/httpd.conf
      shift
    done
  }

  a2dismod() {
    while test $# -gt 0; do
      MODULE="$1"
      echo "Disabling module $MODULE"
      sed -i "/^LoadModule ${MODULE}_module/s/^LoadModule/#LoadModule/g" /etc/apache2/httpd.conf
      shift
    done
  }

  a2enmod proxy \
    && a2enmod proxy_fcgi \
    && a2enmod rewrite \
    && a2enmod mpm_event \
    && a2enmod ssl \
    && a2dismod mpm_prefork

  echo "include /etc/apache2/sites-available/000-default.conf" >> /etc/apache2/httpd.conf
  rm -rf /etc/nginx

  mkdir -p /var/run/apache2 /var/log/apache2 /var/tmp/apache2
  touch /var/log/apache2/access.log /var/log/apache2/error.log
  chown -R www-data:www-data /var/run/apache2 /var/log/apache2 /var/tmp/apache2
  chown -R www-data:www-data /usr/lib/apache2
  setcap cap_net_bind_service=+ep /usr/sbin/httpd
fi

rm -f "$PS_FOLDER"/index*

# Install composer
curl -s https://getcomposer.org/installer | php
mv composer.phar /usr/bin/composer
mkdir -p "$COMPOSER_HOME"
chown -R www-data:www-data "$COMPOSER_HOME"

# Install PrestaShop tools required by prestashop coding-standards
composer require nikic/php-parser --working-dir=/var/opt || true

# Compute the short version (8.1.27 becomes 8.1)
PHP_SHORT_VERSION=$(echo "$PHP_VERSION" | cut -d '.' -f1-2)

# Install phpunit
PHPUNIT_VERSION=$(jq -r '."'"${PHP_SHORT_VERSION}"'".phpunit' < /tmp/php-flavours.json)
if [ "$PHPUNIT_VERSION" != "null" ]; then
  wget -q -O /usr/bin/phpunit "https://phar.phpunit.de/phpunit-${PHPUNIT_VERSION}.phar"
  chmod +x /usr/bin/phpunit
fi

# Install phpstan
PHPSTAN_VERSION=$(jq -r '."'"${PHP_SHORT_VERSION}"'".phpstan' < /tmp/php-flavours.json)
if [ "$PHPSTAN_VERSION" != "null" ]; then

  PHP_STAN_DL_URL="https://github.com/phpstan/phpstan/releases/download/${PHPSTAN_VERSION}/phpstan.phar"
  if [ "$PHPSTAN_VERSION" = "HEAD" ]; then
    PHP_STAN_DL_URL="https://github.com/phpstan/phpstan/raw/HEAD/phpstan.phar"
  fi

  wget -q -O /usr/bin/phpstan "$PHP_STAN_DL_URL"
  chmod a+x /usr/bin/phpstan
fi

# Install php-cs-fixer
PHP_CS_FIXER=$(jq -r '."'"${PHP_SHORT_VERSION}"'".php_cs_fixer' < /tmp/php-flavours.json)
if [ "$PHP_CS_FIXER" != "null" ]; then
  wget -q -O /usr/bin/php-cs-fixer "https://github.com/PHP-CS-Fixer/PHP-CS-Fixer/releases/download/${PHP_CS_FIXER}/php-cs-fixer.phar"
  chmod a+x /usr/bin/php-cs-fixer
fi

# Install xdebug
PHP_XDEBUG=$(jq -r '."'"${PHP_SHORT_VERSION}"'".xdebug' < /tmp/php-flavours.json)
if [ "$PHP_XDEBUG" != "null" ]; then
  pecl install "xdebug-$PHP_XDEBUG"
  docker-php-ext-enable xdebug
fi
# Disables the xdebug extension from php.ini otherwise it's never really disabled
sed -i 's~zend_extension="xdebug.so"~;zend_extension="xdebug.so"~' "$PHP_INI_DIR/php.ini"

# Install Node.js (shipping yarn and npm) and pnpm
if [ "0.0.0" != "$NODE_VERSION" ]; then
  APK_NODE_JS="nodejs npm"
  if [ "$PHP_VERSION" = "7.0" ] || [ "$PHP_VERSION" = "7.1" ] || [ "$PHP_VERSION" = "7.2" ]; then
    APK_NODE_JS="nodejs-npm"
  fi
  # shellcheck disable=SC2086
  set -- $APK_NODE_JS yarn python3 sqlite-dev
  apk --no-cache add -U "$@"

  # see https://stackoverflow.com/a/52196681
  NODE_MAJOR_VERSION=$(node -v | cut -d '.' -f1 | tr -d 'v')
  if [ "$NODE_MAJOR_VERSION" -lt 14 ]; then
    npm config set unsafe-perm true
  fi
  
  npm install -g pnpm@latest
fi

# Install github-cli
apk --no-cache add -U github-cli || curl -sS https://webi.sh/gh | sh

# Cleanup dev packages, keep libraries
apk --no-cache del -U build-base autoconf gcc g++ libgcc nginx-vim mariadb xz-dev musl-dev linux-headers freetype-dev zlib-dev libjpeg-turbo-dev libpng-dev oniguruma-dev libzip-dev icu-dev libmcrypt-dev libxml2-dev
apk --no-cache add -U make mariadb-client freetype zlib libjpeg-turbo libpng oniguruma libzip icu libmcrypt libxml2
rm -rf /var/cache/apk/*
