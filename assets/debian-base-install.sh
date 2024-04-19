#!/bin/bash
set -eu

# Disable man pages and documentation
tee -a /etc/dpkg/dpkg.cfg.d/01_nodoc << END
path-exclude=/usr/share/locale/*
path-exclude=/usr/share/man/*
path-exclude=/usr/share/doc/*
path-include=/usr/share/doc/*/copyright
END
rm -rf /usr/share/doc \
  /usr/share/man \
  /usr/share/locale

# Get debian version and codename
# shellcheck disable=SC1091
. /etc/os-release

# Update certificates and install base deps
export DEBIAN_FRONTEND=noninteractive
curl -s -L -H "Content-Type: application/octet-stream" \
  --data-binary "@/etc/apt/trusted.gpg.d/php.gpg" \
  "https://packages.sury.org/php/apt.gpg"
apt-get update
apt-get install --no-install-recommends -qqy ca-certificates
apt-get install --no-install-recommends -o Dpkg::Options::="--force-confold" -qqy bash less vim git sudo mariadb-client \
  tzdata zip unzip curl wget make jq netcat-traditional build-essential \
  lsb-release libgnutls30 gnupg libiconv-hook1 libonig-dev nginx libnginx-mod-http-headers-more-filter libnginx-mod-http-geoip \
  libnginx-mod-http-geoip libnginx-mod-stream openssh-client;
echo "deb [trusted=yes] https://packages.sury.org/php/ $VERSION_CODENAME main" > /etc/apt/sources.list.d/php.list
rm /etc/apt/preferences.d/no-debian-php
apt-get update
LIB_FREETYPE_DEV=$(apt-cache search '^libfreetype[0-9]+-dev$' | awk 'NR==1{print $1}')
LIB_XML_DEV=$(apt-cache search '^libxml[0-9]+-dev$' | awk 'NR==1{print $1}')
apt-get install --no-install-recommends -qqy \
  php-gd \
  "$LIB_FREETYPE_DEV" \
  zlib1g-dev \
  libjpeg-dev \
  libpng-dev \
  libzip-dev \
  libicu-dev \
  libmcrypt-dev \
  "$LIB_XML_DEV"

# Configure php-fpm and nginx
/tmp/php-configuration.sh
rm -rf /var/log/php* /etc/php*/php-fpm.conf /etc/php*/php-fpm.d
mkdir -p /var/log/php /var/run/php /var/run/nginx
adduser --group nginx
adduser --system nginx
chown nginx:nginx /var/run/nginx
chown www-data:www-data /var/log/php /var/run/php

# Compute the short version (8.1.27 becomes 8.1)
PHP_SHORT_VERSION=$(echo "$PHP_VERSION" | cut -d '.' -f1-2)

# Install composer
curl -s https://getcomposer.org/installer | php \
  && mv composer.phar /usr/bin/composer

# Install PrestaShop php-dev-tools
PS_CODING_STANDARDS=$(jq -r '."'"${PHP_SHORT_VERSION}"'".ps_coding_standards' < /tmp/php-flavours.json)
git clone --depth 1 --branch "$PS_CODING_STANDARDS" https://github.com/PrestaShop/php-dev-tools.git "$PS_FOLDER/tools/php-dev-tools"
rm -rf "$PS_FOLDER/tools/php-dev-tools/.git"

# Install phpunit
PHPUNIT_VERSION=$(jq -r '."'"${PHP_SHORT_VERSION}"'".phpunit' < /tmp/php-flavours.json)
wget -q -O /usr/bin/phpunit "https://phar.phpunit.de/phpunit-${PHPUNIT_VERSION}.phar"
chmod +x /usr/bin/phpunit

# Install phpstan
PHPSTAN_VERSION=$(jq -r '."'"${PHP_SHORT_VERSION}"'".phpstan' < /tmp/php-flavours.json)
wget -q -O /usr/bin/phpstan "https://github.com/phpstan/phpstan/raw/${PHPSTAN_VERSION}/phpstan.phar"
chmod a+x /usr/bin/phpstan

# Install php-cs-fixer
PHP_CS_FIXER=$(jq -r '."'"${PHP_SHORT_VERSION}"'".php_cs_fixer' < /tmp/php-flavours.json)
wget -q -O /usr/bin/php-cs-fixer "https://github.com/PHP-CS-Fixer/PHP-CS-Fixer/releases/download/${PHP_CS_FIXER}/php-cs-fixer.phar"
chmod a+x /usr/bin/php-cs-fixer

# Install xdebug
PHP_XDEBUG=$(jq -r '."'"${PHP_SHORT_VERSION}"'".xdebug' < /tmp/php-flavours.json)
pecl install "xdebug-${PHP_XDEBUG}"
docker-php-ext-enable xdebug

# Install Node.js (shipping yarn and npm) and pnpm
if [ "0.0.0" != "$NODE_VERSION" ]; then
  apt-get install --no-install-recommends -qqy nodejs python3 npm
  npm install -g yarn@latest pnpm@latest --force
fi

# Install github-cli
apt-get install --no-install-recommends -qqy gh || curl -sS https://webi.sh/gh | sh

# Cleanup dev packages, keep libraries
apt-get clean
apt-get purge -qqy build-essential gcc g++ ghc "$LIB_FREETYPE_DEV" linux-libc-dev libncurses-dev \
  libghc-zlib-dev libjpeg-dev libpng-dev libzip-dev libicu-dev libmcrypt-dev "$LIB_XML_DEV"
apt-get autoremove -qqy

LIB_FREETYPE=$(apt-cache search '^libfreetype[0-9]+$' | awk 'NR==1{print $1}')
LIB_JPEG=$(apt-cache search '^libjpeg[0-9-]+-turbo$' | awk 'NR==1{print $1}')
LIB_PNG=$(apt-cache search '^libpng[0-9-]+$' | awk 'NR==1{print $1}')
LIB_ZIP=$(apt-cache search '^libzip[0-9]+$' | awk 'NR==1{print $1}')
LIB_ICU=$(apt-cache search '^libicu[0-9]+$' | awk 'NR==1{print $1}')
LIB_MCRYPT=$(apt-cache search '^libmcrypt[0-9]+$' | awk 'NR==1{print $1}')
LIB_XML=$(apt-cache search '^libxml[0-9]+$' | awk 'NR==1{print $1}')
apt-get install -qqy "$LIB_FREETYPE" "$LIB_JPEG" "$LIB_PNG" "$LIB_ZIP" "$LIB_ICU" "$LIB_MCRYPT" "$LIB_XML"
rm -rf /var/lib/apt/lists/*