# --------------------------------
# Flashlight install and dump SQL
# --------------------------------
ARG BASE_DOCKER_IMAGE
ARG SERVER_FLAVOUR
FROM ${BASE_DOCKER_IMAGE} AS build-and-dump
ARG PS_VERSION
ARG PHP_VERSION
ARG GIT_SHA
ARG PS_FOLDER=/var/www/html
ARG ZIP_SOURCE

# Get PrestaShop source code
# hadolint ignore=DL3020
ADD ${ZIP_SOURCE} /tmp/prestashop.zip

# Extract the sources
RUN mkdir -p "$PS_FOLDER" /tmp/unzip-ps \
  && unzip -n -q /tmp/prestashop.zip -d /tmp/unzip-ps \
  && ([ -f /tmp/unzip-ps/prestashop.zip ] \
  && unzip -n -q /tmp/unzip-ps/prestashop.zip -d "$PS_FOLDER" \
  || mv /tmp/unzip-ps/prestashop/* "$PS_FOLDER") \
  && chown -R www-data:www-data "$PS_FOLDER" \
  && rm -rf /tmp/prestashop.zip /tmp/unzip-ps

# Ship a VERSION file
RUN echo "PrestaShop $PS_VERSION" > "$PS_FOLDER/VERSION" \
  && echo "PHP $PHP_VERSION" >> "$PS_FOLDER/VERSION" \
  && echo "PHP Base image $PHP_BASE_IMAGE" >> "$PS_FOLDER/VERSION" \
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
ARG BASE_DOCKER_IMAGE
ARG SERVER_FLAVOUR
FROM ${BASE_DOCKER_IMAGE} AS prestashop-flashlight
ARG PS_VERSION
ARG PHP_VERSION
ARG PHP_BASE_IMAGE
ARG SERVER_FLAVOUR
ARG PS_FOLDER=/var/www/html
WORKDIR $PS_FOLDER

ENV PHP_BASE_IMAGE=$PHP_BASE_IMAGE
ENV PHP_VERSION=$PHP_VERSION
ENV PS_VERSION=$PS_VERSION
ENV PS_FOLDER=$PS_FOLDER
ENV SERVER_FLAVOUR=$SERVER_FLAVOUR

RUN mkdir -p "$COMPOSER_HOME" \
  && chown -R www-data:www-data "$COMPOSER_HOME"

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

USER www-data
HEALTHCHECK --interval=5s --timeout=5s --retries=10 --start-period=10s \
  CMD curl -Isf http://localhost:80/admin-dev/robots.txt || exit 1
EXPOSE 80
STOPSIGNAL SIGQUIT
ENTRYPOINT ["/run.sh"]
