#!/bin/sh
set -eu

# Install base tools, PHP requirements and dev-tools
apk --no-cache add -U \
  bash less vim geoip git tzdata zip curl jq autoconf \
  nginx nginx-mod-http-headers-more nginx-mod-http-geoip \
  nginx-mod-stream nginx-mod-stream-geoip ca-certificates \
  php-common php-iconv php-gd mariadb-client sudo libjpeg libxml2 \
  build-base linux-headers freetype-dev zlib-dev libjpeg-turbo-dev \
  libpng-dev oniguruma-dev libzip-dev icu-dev libmcrypt-dev libxml2-dev \
  openssh-client libcap

# Configure php-fpm and nginx
/tmp/php-configuration.sh
rm -rf /var/log/php* /etc/php*/php-fpm.conf /etc/php*/php-fpm.d
mkdir -p /var/log/php /var/run/php /var/run/nginx /var/log/nginx
touch /var/log/nginx/access.log /var/log/nginx/error.log
chown -R www-data:www-data /var/log/php /var/run/php "$PHP_INI_DIR" \
 /var/run/nginx /var/log/nginx /var/lib/nginx
setcap cap_net_bind_service=+ep /usr/sbin/nginx

# Compute the short version (8.1.27 becomes 8.1)
PHP_SHORT_VERSION=$(echo "$PHP_VERSION" | cut -d '.' -f1-2)

# Install composer
curl -s https://getcomposer.org/installer | php
mv composer.phar /usr/bin/composer
mkdir -p "$COMPOSER_HOME"
chown -R www-data:www-data "$COMPOSER_HOME"

# Install PrestaShop tools required by prestashop coding-standards
composer require nikic/php-parser --working-dir=/var/opt || true

# Install phpunit
PHPUNIT_VERSION=$(jq -r '."'"${PHP_SHORT_VERSION}"'".phpunit' < /tmp/php-flavours.json)
if [ "$PHPUNIT_VERSION" != "null" ]; then
  wget -q -O /usr/bin/phpunit "https://phar.phpunit.de/phpunit-${PHPUNIT_VERSION}.phar"
  chmod +x /usr/bin/phpunit
fi

# Install phpstan
PHPSTAN_VERSION=$(jq -r '."'"${PHP_SHORT_VERSION}"'".phpstan' < /tmp/php-flavours.json)
if [ "$PHPSTAN_VERSION" != "null" ]; then
  wget -q -O /usr/bin/phpstan "https://github.com/phpstan/phpstan/raw/${PHPSTAN_VERSION}/phpstan.phar"
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

# Install Node.js (shipping yarn and npm) and pnpm
if [ "0.0.0" != "$NODE_VERSION" ]; then
  apk --no-cache add -U python3 nodejs npm yarn
  npm install -g pnpm@latest
fi

# Install github-cli
apk --no-cache add -U github-cli || curl -sS https://webi.sh/gh | sh

# Cleanup dev packages, keep libraries
apk --no-cache del -U build-base autoconf gcc g++ libgcc nginx-vim mariadb xz-dev musl-dev linux-headers freetype-dev zlib-dev libjpeg-turbo-dev libpng-dev oniguruma-dev libzip-dev icu-dev libmcrypt-dev libxml2-dev
apk --no-cache add -U make mariadb-client freetype zlib libjpeg-turbo libpng oniguruma libzip icu libmcrypt libxml2
rm -rf /var/cache/apk/*
