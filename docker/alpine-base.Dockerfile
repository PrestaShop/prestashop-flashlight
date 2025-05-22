ARG PS_VERSION
ARG PHP_VERSION
ARG PHP_BASE_IMAGE=8.3-fpm-alpine
ARG GIT_SHA
ARG NODE_VERSION
ARG SERVER_FLAVOUR

# -------------------------------------
#  PrestaShop Flashlight: Alpine image
# -------------------------------------
FROM php:${PHP_BASE_IMAGE} AS alpine-base-prestashop
ARG PS_VERSION
ARG PHP_VERSION
ARG GIT_SHA
ARG NODE_VERSION
ARG SERVER_FLAVOUR
ENV PS_FOLDER=/var/www/html
ENV PHP_INI_DIR=/usr/local/etc/php
ENV COMPOSER_HOME=/var/composer
ENV PHP_ENV=development

COPY ./assets/php-fpm.conf /usr/local/etc/php-fpm.conf
COPY ./assets/nginx.conf /etc/nginx/nginx.conf
COPY ./assets/000-default.conf /etc/apache2/sites-available/000-default.conf
COPY ./php-flavours.json /tmp
COPY ./assets/php-configuration.sh /tmp/
COPY ./assets/alpine-base-install.sh /tmp/
COPY ./assets/ps-console-polyfill.php /tmp/
COPY ./assets/coding-standards /var/opt/prestashop/coding-standards
COPY ./assets/certs /usr/local/certs

RUN chmod -R 755 /usr/local/certs \
  && /tmp/alpine-base-install.sh \
  && rm -f /tmp/alpine-base-install.sh /tmp/php-configuration.sh

RUN version="$(php -r "echo PHP_MAJOR_VERSION.PHP_MINOR_VERSION;")" \
  && architecture=$(uname -m) \
  && curl -A "Docker" -o /tmp/blackfire-probe.tar.gz -D - -L -s "https://blackfire.io/api/v1/releases/probe/php/linux/$architecture/$version" \
  && mkdir -p /tmp/blackfire \
  && tar zxpf /tmp/blackfire-probe.tar.gz -C /tmp/blackfire \
  && mv /tmp/blackfire/blackfire-*.so "$(php -r "echo ini_get ('extension_dir');")"/blackfire.so \
  && printf "extension=blackfire.so\nblackfire.agent_socket=tcp://blackfire:8307\n" > $PHP_INI_DIR/conf.d/blackfire.ini \
  && rm -rf /tmp/blackfire /tmp/blackfire-probe.tar.gz

# Install and configure MariaDB
RUN adduser -D -s /sbin/nologin mysql \
  && apk --no-cache add -U --no-commit-hooks --no-scripts mariadb;
COPY ./assets/mariadb-server.cnf /etc/my.cnf.d/mariadb-server.cnf
