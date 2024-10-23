#!/bin/sh
set -eu

ALPINE_VERSIONS="$(jq -r 'to_entries | map(.value.alpine) | join(" ")' ./php-flavours.json)"
DEBIAN_VERSIONS="$(jq -r 'to_entries | map(.value.debian) | join(" ")' ./php-flavours.json)"

for PHP_FLAVOUR in $ALPINE_VERSIONS; do
  echo "Publishing Alpine Base" "$PHP_FLAVOUR"
  gh workflow run docker-base-publish.yml \
    --repo prestashop/prestashop-flashlight \
    --field target_platforms=linux/amd64,linux/arm64 \
    --field php_flavour="$PHP_FLAVOUR"
done

for PHP_FLAVOUR in $DEBIAN_VERSIONS; do
  echo "Publishing Debian Base" "$PHP_FLAVOUR"
  gh workflow run docker-base-publish.yml \
    --repo prestashop/prestashop-flashlight \
    --field target_platforms=linux/amd64,linux/arm64 \
    --field php_flavour="$PHP_FLAVOUR"
done
