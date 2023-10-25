# -------------------------------------
#  PrestaShop Flashlight: Alpine image
# -------------------------------------
ARG PS_VERSION
ARG PHP_VERSION
ARG PHP_FLAVOUR
FROM php:${PHP_FLAVOUR} AS base-prestashop
ARG PS_VERSION
ARG PHP_VERSION
ENV PS_FOLDER=/var/www/html

# Install base tools
RUN apk --no-cache add -U \
  bash less vim geoip git tzdata zip curl jq \
  nginx nginx-mod-http-headers-more nginx-mod-http-geoip \
  nginx-mod-stream nginx-mod-stream-geoip ca-certificates \
  libmcrypt gnu-libiconv php-common mariadb-client sudo

# Install PHP requirements
# see: https://olvlvl.com/2019-06-install-php-ext-source
RUN apk --no-cache add -U zlib-dev libjpeg-turbo-dev libpng-dev libzip-dev icu-dev \
  && ([ "7.1" = "$PHP_VERSION" ] && docker-php-ext-configure gd --with-gd --with-jpeg --with-jpeg-dir --with-zlib-dir || docker-php-ext-configure gd --with-jpeg) \
  && docker-php-ext-install gd pdo_mysql zip intl;

# TODO check opcache configuration
# RUN docker-php-ext-enable opcache
# RUN echo '\
#   opcache.interned_strings_buffer=16\n\
#   opcache.load_comments=Off\n\
#   opcache.max_accelerated_files=16000\n\
#   opcache.save_comments=Off\n\
#   ' >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini

# Configure php-fpm and nginx
RUN rm -rf /var/log/php* /etc/php*/php-fpm.conf /etc/php*/php-fpm.d \
  && mkdir -p /var/log/php /var/run/php /var/run/nginx \
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
  && ([ -f /tmp/unzip-ps/prestashop.zip ] && unzip -n -q /tmp/unzip-ps/prestashop.zip -d $PS_FOLDER || mv /tmp/unzip-ps/prestashop/* $PS_FOLDER) \
  && chown -R www-data:www-data $PS_FOLDER \
  && rm -rf /tmp/prestashop.zip /tmp/unzip-ps

# Install and configure MariaDB
RUN adduser --system mysql; \
  apk --no-cache add -U --no-commit-hooks --no-scripts mariadb;
COPY ./assets/mariadb-server.cnf /etc/my.cnf.d/mariadb-server.cnf

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
