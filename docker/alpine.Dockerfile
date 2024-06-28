ARG PS_VERSION
ARG PHP_VERSION
ARG PHP_FLAVOUR
ARG GIT_SHA
ARG NODE_VERSION
ARG ZIP_SOURCE
ARG PRE_INSTALLED_MODULES

# -------------------------------------
#  PrestaShop Flashlight: Alpine image
# -------------------------------------
FROM php:${PHP_FLAVOUR} AS alpine-base-prestashop
ARG PS_VERSION
ARG PHP_VERSION
ARG NODE_VERSION
ENV PS_FOLDER=/var/www/html
ENV PHP_INI_DIR=/usr/local/etc/php
ENV COMPOSER_HOME=/var/composer

ENV PHP_ENV=development
COPY ./assets/php-fpm.conf /usr/local/etc/php-fpm.conf
COPY ./assets/nginx.conf /etc/nginx/nginx.conf
COPY ./php-flavours.json /tmp
COPY ./assets/php-configuration.sh /tmp/
COPY ./assets/alpine-base-install.sh /tmp/
COPY ./assets/coding-standards /var/opt/prestashop/coding-standards

RUN /tmp/alpine-base-install.sh \
  && rm -f /tmp/alpine-base-install.sh /tmp/php-configuration.sh

RUN version="$(php -r "echo PHP_MAJOR_VERSION.PHP_MINOR_VERSION;")" \
  && architecture=$(uname -m) \
  && curl -A "Docker" -o /tmp/blackfire-probe.tar.gz -D - -L -s "https://blackfire.io/api/v1/releases/probe/php/linux/$architecture/$version" \
  && mkdir -p /tmp/blackfire \
  && tar zxpf /tmp/blackfire-probe.tar.gz -C /tmp/blackfire \
  && mv /tmp/blackfire/blackfire-*.so "$(php -r "echo ini_get ('extension_dir');")"/blackfire.so \
  && printf "extension=blackfire.so\nblackfire.agent_socket=tcp://blackfire:8307\n" > $PHP_INI_DIR/conf.d/blackfire.ini \
  && rm -rf /tmp/blackfire /tmp/blackfire-probe.tar.gz

# --------------------------------
# Flashlight install and dump SQL
# --------------------------------
FROM alpine-base-prestashop AS build-and-dump
ARG PS_VERSION
ARG PHP_VERSION
ARG GIT_SHA
ARG PS_FOLDER=/var/www/html
ARG ZIP_SOURCE
ARG PRE_INSTALLED_MODULES
ENV PRE_INSTALLED_MODULES=$PRE_INSTALLED_MODULES

# Get PrestaShop source code
# hadolint ignore=DL3020
ADD ${ZIP_SOURCE} /tmp/prestashop.zip

# Extract the souces
RUN mkdir -p "$PS_FOLDER" /tmp/unzip-ps \
  && unzip -n -q /tmp/prestashop.zip -d /tmp/unzip-ps \
  && ([ -f /tmp/unzip-ps/prestashop.zip ] \
  && unzip -n -q /tmp/unzip-ps/prestashop.zip -d "$PS_FOLDER" \
  || mv /tmp/unzip-ps/prestashop/* "$PS_FOLDER") \
  && chown -R www-data:www-data "$PS_FOLDER" \
  && rm -rf /tmp/prestashop.zip /tmp/unzip-ps

# Install and configure MariaDB
RUN adduser --system mysql \
  && apk --no-cache add -U --no-commit-hooks --no-scripts mariadb;
COPY ./assets/mariadb-server.cnf /etc/my.cnf.d/mariadb-server.cnf

# Ship a VERSION file
RUN echo "PrestaShop $PS_VERSION" > "$PS_FOLDER/VERSION" \
  && echo "PHP $PHP_VERSION" >> "$PS_FOLDER/VERSION" \
  && echo "Flashlight $GIT_SHA" >> "$PS_FOLDER/VERSION"

# Extra patches to the PrestaShop sources
COPY ./assets/patch.sh /patch.sh
RUN sh /patch.sh

# Hydrate the SQL dump
COPY ./assets/hydrate.sh /hydrate.sh
RUN sh /hydrate.sh

# -----------------------
# Flashlight final image
# -----------------------
FROM alpine-base-prestashop AS prestashop-flashlight
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

RUN mkdir -p "$COMPOSER_HOME" \
  && chown www-data:www-data "$COMPOSER_HOME"

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
