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

for PHP_VERSION in $PHP_VERSIONS; do
  echo "Publishing Debian Base for $PHP_VERSION"
  gh workflow run docker-base-publish.yml \
    --repo prestashop/prestashop-flashlight \
    --field target_platforms=linux/amd64,linux/arm64 \
    --field os_flavour="debian" \
    --field php_base_image="$PHP_VERSION"
done
