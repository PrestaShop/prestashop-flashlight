ARG PS_VERSION
ARG PHP_VERSION
ARG PHP_FLAVOUR
ARG GIT_SHA
ARG NODE_VERSION

# -------------------------------------
#  PrestaShop Flashlight: Debian image
# -------------------------------------
FROM php:${PHP_FLAVOUR} AS base-prestashop
ARG PS_VERSION
ARG PHP_VERSION
ARG GIT_SHA
ARG NODE_VERSION
ENV PS_FOLDER=/var/www/html
ENV COMPOSER_HOME=/var/composer

# Update certificates
RUN export DEBIAN_FRONTEND=noninteractive \
  && apt-get update \
  && apt-get install --no-install-recommends -qqy \
  ca-certificates bash less vim git tzdata zip unzip curl wget make jq netcat-traditional \
  lsb-release libgnutls30 gnupg libiconv-hook1 libonig-dev \
  nginx libnginx-mod-http-headers-more-filter libnginx-mod-http-geoip \
  libnginx-mod-http-geoip libnginx-mod-stream mariadb-client sudo \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# PHP requirements and dev-tools
ENV PHP_ENV=development

COPY ./assets/php-configuration.sh /tmp/
RUN . /etc/os-release \
  && echo "deb [trusted=yes] https://packages.sury.org/php/ ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/php.list \
  && rm /etc/apt/preferences.d/no-debian-php \
  && export DEBIAN_FRONTEND=noninteractive \
  && apt-get update \
  && apt-get install --no-install-recommends -qqy \
  php-gd \
  libghc-zlib-dev \
  libjpeg-dev \
  libpng-dev \
  libzip-dev \
  libicu-dev \
  libmcrypt-dev \
  libxml2-dev \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && /tmp/php-configuration.sh

# Configure php-fpm and nginx
RUN rm -rf /var/log/php* /etc/php*/php-fpm.conf /etc/php*/php-fpm.d \
  && mkdir -p /var/log/php /var/run/php /var/run/nginx \
  && adduser --group nginx \
  && adduser --system nginx \
  && chown nginx:nginx /var/run/nginx \
  && chown www-data:www-data /var/log/php /var/run/php
COPY ./assets/php-fpm.conf /usr/local/etc/php-fpm.conf
COPY ./assets/nginx.conf /etc/nginx/nginx.conf
COPY ./php-flavours.json /tmp

# Install composer
RUN curl -s https://getcomposer.org/installer | php \
  && mv composer.phar /usr/bin/composer

# Install phpunit
RUN PHPUNIT_VERSION=$(jq -r '."'"${PHP_VERSION}"'".phpunit' < /tmp/php-flavours.json) \
  && wget -q -O /usr/bin/phpunit "https://phar.phpunit.de/phpunit-${PHPUNIT_VERSION}.phar" \
  && chmod +x /usr/bin/phpunit

# Install phpstan
RUN PHPSTAN_VERSION=$(jq -r '."'"${PHP_VERSION}"'".phpstan' < /tmp/php-flavours.json) \
  && wget -q -O /usr/bin/phpstan "https://github.com/phpstan/phpstan/raw/${PHPSTAN_VERSION}/phpstan.phar" \
  && chmod a+x /usr/bin/phpstan

# Install php-cs-fixer
RUN PHP_CS_FIXER=$(jq -r '."'"${PHP_VERSION}"'".php_cs_fixer' < /tmp/php-flavours.json) \
  && wget -q -O /usr/bin/php-cs-fixer "https://github.com/PHP-CS-Fixer/PHP-CS-Fixer/releases/download/${PHP_CS_FIXER}/php-cs-fixer.phar" \
  && chmod a+x /usr/bin/php-cs-fixer

# Install Node.js and pnpm (yarn and npm are included)
RUN if [ "0.0.0" = "$NODE_VERSION" ]; then exit 0; fi \
  && export DEBIAN_FRONTEND=noninteractive \
  && apt-get update \
  && apt-get install --no-install-recommends -qqy nodejs python3 npm \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && npm install -g yarn@latest pnpm@latest --force

# --------------------------------
# Flashlight install and dump SQL
# --------------------------------
FROM base-prestashop AS build-and-dump
ARG PS_VERSION
ARG PHP_VERSION
ARG GIT_SHA
ARG PS_FOLDER=/var/www/html

# Get PrestaShop source code
ADD https://github.com/PrestaShop/PrestaShop/releases/download/${PS_VERSION}/prestashop_${PS_VERSION}.zip /tmp/prestashop.zip

# Extract the souces
RUN mkdir -p "$PS_FOLDER" /tmp/unzip-ps \
  && unzip -n -q /tmp/prestashop.zip -d /tmp/unzip-ps \
  && ([ -f /tmp/unzip-ps/prestashop.zip ] \
  && unzip -n -q /tmp/unzip-ps/prestashop.zip -d "$PS_FOLDER" \
  || mv /tmp/unzip-ps/prestashop/* "$PS_FOLDER") \
  && chown -R www-data:www-data "$PS_FOLDER" \
  && rm -rf /tmp/prestashop.zip /tmp/unzip-ps

# Install and configure MariaDB
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -o DPkg::Options::="--force-confnew" -qqy mariadb-server \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*
COPY ./assets/mariadb-server.cnf /etc/mysql/my.cnf

# Ship a VERSION file
RUN echo "PrestaShop $PS_VERSION" > "$PS_FOLDER/VERSION" \
  && echo "PHP $PHP_VERSION" >> "$PS_FOLDER/VERSION" \
  && echo "Flashlight $GIT_SHA" >> "$PS_FOLDER/VERSION"

# Hydrate the SQL dump
COPY ./assets/hydrate.sh /hydrate.sh
RUN sh /hydrate.sh

# Extra patches to the PrestaShop sources
COPY ./assets/patch.sh /patch.sh
RUN sh /patch.sh

# -----------------------
# Flashlight final image
# -----------------------
FROM base-prestashop AS prestashop-flashlight
ARG PS_VERSION
ARG PHP_VERSION
ARG PHP_FLAVOUR
ARG PS_FOLDER=/var/www/html
WORKDIR $PS_FOLDER

# Setup default env
ENV MYSQL_HOST=mysql
ENV MYSQL_USER=prestashop
ENV MYSQL_PASSWORD=prestashop
ENV MYSQL_PORT=3306
ENV MYSQL_DATABASE=prestashop
ENV DEBUG_MODE=false
ENV PS_FOLDER=$PS_FOLDER
ENV MYSQL_EXTRA_DUMP=

RUN mkdir -p $COMPOSER_HOME \
  && chown www-data:www-data $COMPOSER_HOME

# Get the installed sources
COPY \
  --chown=www-data:www-data \
  --from=build-and-dump \
  ${PS_FOLDER} ${PS_FOLDER}

# Ship the dump within the image
COPY --chown=www-data:www-data \
  --from=build-and-dump \
  /dump.sql /dump.sql

# Opt directory
COPY --from=build-and-dump \
  /var/opt/prestashop /var/opt/prestashop

# The new default runner
COPY ./assets/run.sh /run.sh

HEALTHCHECK --interval=5s --timeout=5s --retries=10 --start-period=10s \
  CMD curl -Isf http://localhost:80/admin-dev/robots.txt || exit 1
EXPOSE 80
STOPSIGNAL SIGQUIT
ENTRYPOINT ["/run.sh"]
