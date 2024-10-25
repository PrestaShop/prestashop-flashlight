ARG PS_VERSION
ARG PHP_VERSION
ARG PHP_BASE_IMAGE=8.3-fpm-bookworm
ARG GIT_SHA
ARG NODE_VERSION
ARG ZIP_SOURCE

# -------------------------------------
#  PrestaShop Flashlight: Debian image
# -------------------------------------
FROM php:${PHP_BASE_IMAGE} AS debian-base-prestashop
ARG PS_VERSION
ARG PHP_VERSION
ARG GIT_SHA
ARG NODE_VERSION
ENV PS_FOLDER=/var/www/html
ENV COMPOSER_HOME=/var/composer
ENV PHP_ENV=development

COPY ./assets/php-fpm.conf /usr/local/etc/php-fpm.conf
COPY ./assets/nginx.conf /etc/nginx/nginx.conf
COPY ./php-flavours.json /tmp
COPY ./assets/php-configuration.sh /tmp/
COPY ./assets/debian-base-install.sh /tmp/
COPY ./assets/ps-console-polyfill.php /tmp/
COPY ./assets/coding-standards /var/opt/prestashop/coding-standards

RUN /tmp/debian-base-install.sh \
  && rm -f /tmp/debian-base-install.sh /tmp/php-configuration.sh

RUN version="$(php -r "echo PHP_MAJOR_VERSION.PHP_MINOR_VERSION;")" \
  && architecture=$(uname -m) \
  && curl -A "Docker" -o /tmp/blackfire-probe.tar.gz -D - -L -s "https://blackfire.io/api/v1/releases/probe/php/linux/$architecture/$version" \
  && mkdir -p /tmp/blackfire \
  && tar zxpf /tmp/blackfire-probe.tar.gz -C /tmp/blackfire \
  && mv /tmp/blackfire/blackfire-*.so "$(php -r "echo ini_get ('extension_dir');")"/blackfire.so \
  && printf "extension=blackfire.so\nblackfire.agent_socket=tcp://blackfire:8307\n" > $PHP_INI_DIR/conf.d/blackfire.ini \
  && rm -rf /tmp/blackfire /tmp/blackfire-probe.tar.gz

# Install and configure MariaDB
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -o DPkg::Options::="--force-confnew" -qqy mariadb-server \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*
COPY ./assets/mariadb-server.cnf /etc/mysql/my.cnf
