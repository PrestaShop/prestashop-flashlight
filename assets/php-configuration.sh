#!/bin/sh
set -eu

# Install PHP extensions
# @see https://olvlvl.com/2019-06-install-php-ext-source
# @see https://stackoverflow.com/a/73834081
# @see https://packages.sury.org/php/dists/

error() {
  printf "\e[1;31m%s\e[0m" "${1:-Unknown error}"
  exit "${2:-1}"
}

[ -z "$PHP_ENV" ] && error "PHP_ENV is not set" 2
[ -z "$PHP_VERSION" ] && error "PHP_VERSION is not set" 3

PS_PHP_EXT="gd pdo_mysql zip intl fileinfo mbstring simplexml soap bcmath"
PHP_GD_CONFIG="--with-jpeg --with-freetype";

if [ "7.1" = "$PHP_VERSION" ]; then
  PS_PHP_EXT="$PS_PHP_EXT mcrypt";
  PHP_GD_CONFIG="--with-gd --with-jpeg --with-jpeg-dir --with-zlib-dir --with-freetype-dir";
elif [ "7.2" = "$PHP_VERSION" ] || [ "7.3" = "$PHP_VERSION" ]; then
  PHP_GD_CONFIG="--with-jpeg-dir --with-zlib-dir --with-freetype-dir";
fi

# shellcheck disable=SC2086
docker-php-ext-configure gd $PHP_GD_CONFIG
# shellcheck disable=SC2086
docker-php-ext-install $PS_PHP_EXT;

if [ "production" = "$PHP_ENV" ]; then
  mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
  rm -f "$PHP_INI_DIR/php.ini-development";
else
  mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"
  rm -f "$PHP_INI_DIR/php.ini-production";
fi
pear config-set php_ini "$PHP_INI_DIR/php.ini"

# Flashlight is a testinf platform, keep things simple
sed -i 's/memory_limit = .*/memory_limit = -1/' "$PHP_INI_DIR/php.ini"
sed -i 's/upload_max_filesize = .*/upload_max_filesize = 40M/' "$PHP_INI_DIR/php.ini"
sed -i 's/post_max_size = .*/post_max_size = 40M/' "$PHP_INI_DIR/php.ini"

# Remove php assets that might have been installed by package unaware of $PHP_INI_DIR
rm -rf /etc/php* /usr/lib/php*
