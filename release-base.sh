#!/bin/sh
set -eu

PHP_VERSIONS="$(jq -r 'keys | join(" ")' ./php-flavours.json)"
for PHP_VERSION in $PHP_VERSIONS; do
  echo "Publishing Alpine Base for $PHP_VERSION"
  gh workflow run docker-base-publish.yml \
    --repo prestashop/prestashop-flashlight \
    --field target_platforms=linux/amd64,linux/arm64 \
    --field os_flavour="alpine" \
    --field php_version="$PHP_VERSION"
done

PHP_DEBIAN_VERSIONS="8.0 8.1 8.2 8.3"
for PHP_VERSION in $PHP_DEBIAN_VERSIONS; do
  echo "Publishing Debian Base for $PHP_VERSION"
  gh workflow run docker-base-publish.yml \
    --repo prestashop/prestashop-flashlight \
    --field target_platforms=linux/amd64,linux/arm64 \
    --field os_flavour="debian" \
    --field php_version="$PHP_VERSION"
done
