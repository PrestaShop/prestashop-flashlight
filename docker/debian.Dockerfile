# -------------------------------------
#  PrestaShop FlashLight: Debian image
# -------------------------------------
ARG PS_VERSION
ARG PHP_VERSION
ARG PHP_FLAVOUR
FROM php:${PHP_FLAVOUR} AS base-prestashop
ARG PS_VERSION
ENV PS_FOLDER=/var/www/html

# Install base tools
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -qqy \
  bash less vim git tzdata zip unzip curl jq netcat-traditional ca-certificates \
  lsb-release libgnutls30 gnupg libmcrypt4 libiconv-hook1 \
  nginx libnginx-mod-http-headers-more-filter libnginx-mod-http-geoip \
  libnginx-mod-http-geoip libnginx-mod-stream mariadb-client sudo

# Install PHP requirements
# see: https://olvlvl.com/2019-06-install-php-ext-source
# see: https://stackoverflow.com/a/73834081
# see: https://packages.sury.org/php/dists/
RUN curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg \
  && . /etc/os-release \
  && echo "deb [trusted=yes] https://packages.sury.org/php/ ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/php.list \
  && rm /etc/apt/preferences.d/no-debian-php;
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -qqy \
  php-gd libghc-zlib-dev libjpeg-dev libpng-dev libzip-dev libicu-dev \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && docker-php-ext-configure gd --with-gd --with-jpeg --with-jpeg-dir --with-zlib-dir \
  && docker-php-ext-install gd pdo_mysql zip intl;

# Configure php-fpm and nginx
RUN rm -rf /var/log/php* /etc/php*/php-fpm.conf /etc/php*/php-fpm.d \
  && mkdir -p /var/log/php /var/run/php /var/run/nginx \
  && adduser --group nginx \
  && adduser --system nginx \
  && chown nginx:nginx /var/run/nginx \
  && chown www-data:www-data /var/log/php /var/run/php
COPY ./assets/php-fpm.conf /usr/local/etc/php-fpm.conf
COPY ./assets/nginx.conf /etc/nginx/nginx.conf

# --------------------------------
# Flashlight install and dump SQL
# --------------------------------
FROM base-prestashop AS build-and-dump
ARG PS_VERSION
ARG PHP_VERSION
ARG PS_FOLDER=/var/www/html

# Get PrestaShop source code
ADD https://github.com/PrestaShop/PrestaShop/releases/download/${PS_VERSION}/prestashop_${PS_VERSION}.zip /tmp/prestashop.zip

# Extract the souces
RUN mkdir -p $PS_FOLDER /tmp/unzip-ps \
  && unzip -n -q /tmp/prestashop.zip -d /tmp/unzip-ps \
  && unzip -n -q /tmp/unzip-ps/prestashop.zip -d $PS_FOLDER \
  && chown -R www-data:www-data $PS_FOLDER \
  && rm -rf /tmp/prestashop.zip /tmp/unzip-ps

# Install and configure MariaDB
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -o DPkg::Options::="--force-confnew" -qqy mariadb-server \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*
COPY ./assets/mariadb-server.cnf /etc/mysql/my.cnf

# Hydrate the SQL dump
COPY ./assets/hydrate.sh /hydrate.sh
RUN sh /hydrate.sh

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

# Get the installed sources
COPY \
  --chown=www-data:www-data \
  --from=build-and-dump \
  ${PS_FOLDER} ${PS_FOLDER}

# Ship the dump within the image
COPY --chown=www-data:www-data \
  --from=build-and-dump \
  /dump.sql /dump.sql

# The new default runner
COPY ./assets/run.sh /run.sh

HEALTHCHECK --interval=30s --timeout=10s --retries=10 --start-period=10s \
  CMD curl -Isf http://localhost:80/robots.txt || exit 1
EXPOSE 80
STOPSIGNAL SIGQUIT
ENTRYPOINT ["/run.sh"]
