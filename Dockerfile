ARG PS_VERSION
ARG PHP_VERSION

# ----------------------
# Flashlight base image
# ----------------------
FROM php:${PHP_VERSION}-fpm-alpine AS base-prestashop
ARG PS_VERSION
ARG PS_FOLDER=/var/www/html

# Install base tools
RUN \
  apk --no-cache add -U \
  bash less vim geoip git tzdata zip curl \
  nginx nginx-mod-http-headers-more nginx-mod-http-geoip \
  nginx-mod-stream nginx-mod-stream-geoip ca-certificates \
  libmcrypt gnu-libiconv-libs php-common \
  && rm -rf /var/cache/apk/*

# Install PHP requirements
# see: https://olvlvl.com/2019-06-install-php-ext-source
ENV GD_DEPS="zlib-dev libjpeg-turbo-dev libpng-dev"
ENV ZIP_DEPS="libzip-dev"
ENV INTL_DEPS="icu-dev"
RUN apk add -U $GD_DEPS $ZIP_DEPS $INTL_DEPS \
  && docker-php-ext-configure gd --with-jpeg \
  && docker-php-ext-install gd pdo_mysql zip intl;
#   docker-php-ext-enable opcache

# Clean unused php-fpm configuration
RUN rm -rf /var/log/php* /etc/php*/php-fpm.conf /etc/php*/php-fpm.d

# Configure php-fpm and nginx
RUN mkdir -p /var/log/php /var/run/php /var/run/nginx \
  && chown www-data:www-data /var/log/php /var/run/php \
  && chown nginx:nginx /var/run/nginx
ADD ./assets/php-fpm.conf /usr/local/etc/php-fpm.conf
ADD ./assets/nginx.conf /etc/nginx/nginx.conf

# --------------------------------
# Flashlight install and dump SQL
# --------------------------------
FROM base-prestashop as build-and-dump
ARG PS_VERSION
ARG PHP_VERSION
ARG PS_FOLDER=/var/www/html

# Get PrestaShop source code
ADD https://github.com/PrestaShop/PrestaShop/releases/download/${PS_VERSION}/prestashop_${PS_VERSION}.zip /tmp/prestashop.zip

# Extract the souces
RUN mkdir -p $PS_FOLDER \
  && unzip -n -q /tmp/prestashop.zip -d $PS_FOLDER \
  && mv $PS_FOLDER/prestashop.zip /tmp/prestashop.zip \
  && unzip -n -q /tmp/prestashop.zip -d $PS_FOLDER \
  && chown www-data:www-data -R $PS_FOLDER \
  && rm -rf /tmp/prestashop.zip

ENV DUMP_FILE="/dump.sql"
ADD ./tools/auto-install-and-dump.sh /auto-install-and-dump.sh
RUN sh /auto-install-and-dump.sh

# Clean up install files
RUN rm -rf ${PS_FOLDER}/install ${PS_FOLDER}/Install_PrestaShop.html

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
ENV DB_SERVER=mysql
ENV DB_PORT=3306
ENV DB_NAME=prestashop
ENV DB_USER=root
ENV DB_PASSWD=prestashop
ENV DB_PREFIX=ps_
ENV ADMIN_MAIL=admin@prestashop.com
ENV ADMIN_PASSWD=prestashop
ENV PS_LANGUAGE=en
ENV PS_COUNTRY=GB
ENV PS_ALL_LANGUAGES=0
ENV PS_INSTALL_AUTO=1
ENV PS_ERASE_DB=1
ENV PS_INSTALL_DB=1
ENV PS_ENABLE_SSL=0
ENV PS_FOLDER_ADMIN=ps-admin
ENV PS_FOLDER_INSTALL=${PS_FOLDER}/install

# Instal mysql tools
RUN apk add -U mysql-client

# Ship the dump within the image
COPY --chown=www-data:www-data --from=build-and-dump /dump.sql /dump.sql

# The new default runner
ADD ./tools/sql-restore-and-run-nginx.sh /run.sh

EXPOSE 80
STOPSIGNAL SIGQUIT
ENTRYPOINT ["/run.sh"]
