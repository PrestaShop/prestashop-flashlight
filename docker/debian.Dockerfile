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
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -qqy \
  ca-certificates bash less vim git tzdata zip unzip curl wget make jq netcat-traditional \
  lsb-release libgnutls30 gnupg libiconv-hook1 \
  nginx libnginx-mod-http-headers-more-filter libnginx-mod-http-geoip \
  libnginx-mod-http-geoip libnginx-mod-stream mariadb-client sudo

# PHP requirements and dev-tools
# see: https://olvlvl.com/2019-06-install-php-ext-source
# see: https://stackoverflow.com/a/73834081
# see: https://packages.sury.org/php/dists/
RUN . /etc/os-release \
  && echo "deb [trusted=yes] https://packages.sury.org/php/ ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/php.list \
  && rm /etc/apt/preferences.d/no-debian-php \
  && DEBIAN_FRONTEND=noninteractive apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -qqy \
  php-gd libghc-zlib-dev libjpeg-dev libpng-dev libzip-dev libicu-dev libmcrypt-dev libxml2-dev \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && export PS_PHP_EXT="gd pdo_mysql zip intl fileinfo simplexml" \
  && if [ "7.1" = "$PHP_VERSION" ]; \
  then docker-php-ext-configure gd --with-gd --with-jpeg --with-jpeg-dir --with-zlib-dir \
  && docker-php-ext-install $PS_PHP_EXT mcrypt; \
  else \
  docker-php-ext-configure gd --with-jpeg \
  && docker-php-ext-install $PS_PHP_EXT; \
  fi \
  && mv $PHP_INI_DIR/php.ini-development $PHP_INI_DIR/php.ini \
  && sed -i 's/memory_limit = .*/memory_limit = -1/' $PHP_INI_DIR/php.ini \
  && rm -rf /etc/php* /usr/lib/php*

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
ENV PATH "$PATH:/usr/local/lib/nodejs/bin"
RUN if [ "0.0.0" = "$NODE_VERSION" ]; then exit 0; fi \
  && if [ "$(arch)" = "x86_64" ]; \
  then export DISTRO="linux-x64"; \
  else export DISTRO="linux-arm64"; \
  fi \
  && curl --silent --show-error --fail --location --output /tmp/node.tar.xz \
  "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-${DISTRO}.tar.xz" \
  && mkdir -p /tmp/nodejs && tar -xJf /tmp/node.tar.xz -C /tmp/nodejs \
  && mv "/tmp/nodejs/node-v${NODE_VERSION}-${DISTRO}" /usr/local/lib/nodejs \
  && rm -rf /tmp/nodejs /tmp/node.tar.xz \
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
RUN mkdir -p $PS_FOLDER /tmp/unzip-ps \
  && unzip -n -q /tmp/prestashop.zip -d /tmp/unzip-ps \
  && ([ -f /tmp/unzip-ps/prestashop.zip ] && unzip -n -q /tmp/unzip-ps/prestashop.zip -d $PS_FOLDER || mv /tmp/unzip-ps/prestashop/* $PS_FOLDER) \
  && chown -R www-data:www-data $PS_FOLDER \
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
