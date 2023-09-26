ARG PS_VERSION
ARG PHP_VERSION
ARG PHP_FLAVOUR
# ----------------------
# Flashlight base image
# ----------------------
FROM php:${PHP_VERSION}-${PHP_FLAVOUR} AS base-prestashop
ARG PS_VERSION
ARG PS_FOLDER=/var/www/html

# Install base tools
# RUN \
#   apk --no-cache add -U \
#   bash less vim geoip git tzdata zip curl \
#   nginx nginx-mod-http-headers-more nginx-mod-http-geoip \
#   nginx-mod-stream nginx-mod-stream-geoip ca-certificates \
#   libmcrypt gnu-libiconv-libs php-common \
#   && rm -rf /var/cache/apk/*
RUN apt update \
  && DEBIAN_FRONTEND=noninteractive apt install -qqy \
  bash less vim git tzdata zip curl netcat ca-certificates \
  lsb-release libgnutls30 gnupg ibmcrypt4 libiconv-hook1 \
  nginx libnginx-mod-http-headers-more-filter libnginx-mod-http-geoip libnginx-mod-http-geoip libnginx-mod-stream \
  && apt clean

# Install PHP requirements
# see: https://olvlvl.com/2019-06-install-php-ext-source
# see: https://stackoverflow.com/a/73834081
# https://packages.sury.org/php/dists/buster/
RUN curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg \
  && sh -c 'echo "deb [trusted=yes] https://packages.sury.org/php/ buster main" > /etc/apt/sources.list.d/php.list' \
  && rm /etc/apt/preferences.d/no-debian-php \
  && apt update \
  && DEBIAN_FRONTEND=noninteractive apt install -qqy php-gd
ENV GD_DEPS="libghc-zlib-dev libjpeg-dev libpng-dev"
ENV ZIP_DEPS="libzip-dev"
ENV INTL_DEPS="libicu-dev"
RUN apt update && DEBIAN_FRONTEND=noninteractive apt install -qqy $GD_DEPS $ZIP_DEPS $INTL_DEPS \
  && docker-php-ext-configure gd --with-jpeg \
  && docker-php-ext-install gd pdo_mysql zip intl;
# RUN apk add -U $GD_DEPS $ZIP_DEPS $INTL_DEPS \
#   && docker-php-ext-configure gd --with-jpeg \
#   && docker-php-ext-install gd pdo_mysql zip intl;
#   docker-php-ext-enable opcache

# Clean unused php-fpm configuration
RUN rm -rf /var/log/php* /etc/php*/php-fpm.conf /etc/php*/php-fpm.d

# Configure php-fpm and nginx
RUN mkdir -p /var/log/php /var/run/php /var/run/nginx /var/lib/nginx/tmp/client_body/ \
  && chown www-data:www-data /var/log/php /var/run/php \
  && adduser --group nginx \
  && adduser --system nginx \
  && chown nginx:nginx /var/run/nginx \ 
  && chown -R www-data:nginx /var/lib/nginx/tmp/client_body \
  && chmod g+w /var/lib/nginx/tmp/client_body
# ADD ./assets/php-fpm.conf /usr/local/etc/php-fpm.conf
ADD ./assets/php-fpm.conf /etc/php-fpm.conf
ADD ./assets/nginx.conf /etc/nginx/nginx.conf

# --------------------------------
# Flashlight install and dump SQL
# --------------------------------
FROM base-prestashop as build-and-dump
ARG PS_VERSION
ARG PHP_VERSION
ARG PS_FOLDER=/var/www/html

# Install and configure MariaDB
RUN adduser --group mysql && adduser --system mysql
# RUN apk add --update-cache --no-commit-hooks --no-scripts runuser mariadb-client mariadb;
RUN apt update && DEBIAN_FRONTEND=noninteractive apt install -qqy mariadb-client mariadb-server && apt clean;
ADD ./assets/mariadb-server.cnf /etc/mysql/my.cnf

# Get PrestaShop source code
ADD https://github.com/PrestaShop/PrestaShop/releases/download/${PS_VERSION}/prestashop_${PS_VERSION}.zip /tmp/prestashop.zip

# Extract the souces 
# TODO add a condition if the first zip contains a prestashop.zip or directly a prestashop folder.
RUN mkdir -p $PS_FOLDER /tmp/unzip-ps \
  && unzip -n -q /tmp/prestashop.zip -d /tmp/unzip-ps \
  && mv /tmp/unzip-ps/prestashop/* $PS_FOLDER \
  && chown -R www-data:www-data $PS_FOLDER \
  && rm -rf /tmp/prestashop.zip /tmp/unzip-ps

ENV DUMP_FILE="/dump.sql"
ADD ./assets/hydrate.sh /hydrate.sh
# RUN sh /hydrate.sh

# # Clean up install files
# RUN rm -rf ${PS_FOLDER}/install ${PS_FOLDER}/Install_PrestaShop.html

# # Create cache directories
# RUN mkdir -p ${PS_FOLDER}/var/cache/prod ${PS_FOLDER}/var/cache/dev

# -----------------------
# Flashlight final image
# -----------------------
FROM base-prestashop as optimize-prestashop
ARG PS_VERSION
ARG PHP_VERSION
ARG PS_FOLDER=/var/www/html
WORKDIR $PS_FOLDER

# Get the installed sources
COPY --chown=www-data:www-data --from=build-and-dump ${PS_FOLDER} ${PS_FOLDER}

# @TODO check opcache
# RUN echo '\
#   opcache.interned_strings_buffer=16\n\
#   opcache.load_comments=Off\n\
#   opcache.max_accelerated_files=16000\n\
#   opcache.save_comments=Off\n\
#   ' >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini

# Disable IPv6
RUN echo "net.ipv6.conf.all.disable_ipv6 = 1" | tee /etc/sysctl.conf

# Setup default env
ENV MYSQL_HOST=mysql
ENV MYSQL_USER=prestashop
ENV MYSQL_PASSWORD=prestashop
ENV MYSQL_PORT=3306
ENV MYSQL_DATABASE=prestashop
ENV DEBUG_MODE=false
ENV PS_FOLDER=$PS_FOLDER
ENV MYSQL_EXTRA_DUMP=

# Instal MySQL client and other handy tools
# RUN apk add -U mysql-client curl jq
RUN apt update \
  && apt install mysql-client curl jq \
  && apt clean 

# Ship the dump within the image
COPY --chown=www-data:www-data --from=build-and-dump /dump.sql /dump.sql

# Increase the memory limits
ADD ./assets/php.ini /usr/local/etc/php/php.ini

# The new default runner
ADD ./assets/run.sh /run.sh

EXPOSE 80
STOPSIGNAL SIGQUIT
ENTRYPOINT ["/run.sh"]
