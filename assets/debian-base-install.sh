#!/bin/bash -v
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
VERSION_CODENAME=""
# shellcheck disable=SC1091
. /etc/os-release
if [ "$VERSION_ID" = 8 ]; then
  export VERSION_CODENAME="jessie";
elif [ "$VERSION_ID" = 9 ]; then
  export VERSION_CODENAME="stretch";
fi

# https://unix.stackexchange.com/a/743874
if [ "$VERSION_CODENAME" = "jessie"  ]; then
  echo "deb [check-valid-until=no] http://archive.debian.org/debian/ jessie main contrib non-free" > /etc/apt/sources.list
elif [ "$VERSION_CODENAME" = "stretch"  ]; then
  sed -i s/deb.debian.org/archive.debian.org/g /etc/apt/sources.list
  sed -i s/security.debian.org/archive.debian.org/g /etc/apt/sources.list
  sed -i s/stretch-updates/stretch/g /etc/apt/sources.list
fi

# Update certificates and install base deps
export DEBIAN_FRONTEND=noninteractive
curl -s -L -H "Content-Type: application/octet-stream" \
  --data-binary "@/etc/apt/trusted.gpg.d/php.gpg" \
  "https://packages.sury.org/php/apt.gpg"
apt-get update
apt-get install --no-install-recommends --force-yes -qqy apt-transport-https ca-certificates
LIB_GNUTLS=$(apt-cache search '^libgnutls' | awk 'NR==1{print $1}')
packages=(bash less vim git sudo mariadb-client \
  tzdata zip unzip curl wget make jq netcat-traditional build-essential \
  lsb-release "$LIB_GNUTLS" gnupg libiconv-hook1 libonig-dev openssh-client libcap2-bin)
if [ "$SERVER_FLAVOUR" = "nginx" ]; then
  packages+=(nginx-full)
else
  packages+=(apache2)
fi

apt-get install --no-install-recommends -o Dpkg::Options::="--force-confold" --force-yes -qqy "${packages[@]}"

if [ "$VERSION_CODENAME" = "bookworm" ] && [ "$VERSION_CODENAME" = "bullseye" ]; then
  echo "deb [trusted=yes] https://packages.sury.org/php/ $VERSION_CODENAME main" > /etc/apt/sources.list.d/php.list
else
  echo "[WARNING] The sury repository does not support debian jessie or stretch any more."
  echo "This build is likely to fail, please use an alpine build if you can."
  echo "see: https://packages.sury.org/php/dists/"
  exit 6
fi
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
else
  a2enmod proxy \
    && a2enmod proxy_fcgi \
    && a2enmod rewrite
  rm -rf /etc/nginx
fi
if [ "$SERVER_FLAVOUR" = "nginx" ]; then
  mkdir -p /var/run/nginx /var/log/nginx /var/tmp/nginx
  touch /var/log/nginx/access.log /var/log/nginx/error.log
  chown -R www-data:www-data /var/run/nginx /var/log/nginx /var/tmp/nginx /var/lib/nginx
  setcap cap_net_bind_service=+ep /usr/sbin/nginx
else
  mkdir -p /var/run/apache2 /var/log/apache2 /var/tmp/apache2
  touch /var/log/apache2/access.log /var/log/apache2/error.log
  chown -R www-data:www-data /var/run/apache2 /var/log/apache2 /var/tmp/apache2 /var/lib/apache2
  setcap cap_net_bind_service=+ep /usr/sbin/apache2
fi

rm -f "$PS_FOLDER"/index*

# Install composer
curl -s https://getcomposer.org/installer | php
mv composer.phar /usr/bin/composer
mkdir -p "$COMPOSER_HOME"
chown -R www-data:www-data "$COMPOSER_HOME"

# Install PrestaShop tools required by prestashop coding-standards
composer require nikic/php-parser --working-dir=/var/opt

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