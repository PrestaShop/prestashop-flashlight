#!/bin/sh
set -euo pipefail
cd $(dirname "$0")

function error {
  echo -e "\e[1;31m${1:-Unknown error}\e[0m"
  exit "${2:-1}"
}

function get_latest_prestashop_version {
  curl --silent --location --request GET \
    'https://api.github.com/repos/prestashop/prestashop/releases/latest' | jq -r '.tag_name'
}

function get_recommended_php_version {
  PS_VERSION=$1; RECOMMENDED_VERSION=
  REGEXP_LIST=$(jq -r 'keys_unsorted | .[]' <prestashop-versions.json)
  while IFS= read -r regExp; do
    if [[ $PS_VERSION =~ $regExp ]]; then
      RECOMMENDED_VERSION=$(jq -r '."'"${regExp}"'".php.recommended' <prestashop-versions.json)
      break;
    fi
  done <<<"$REGEXP_LIST"
  echo "$RECOMMENDED_VERSION";
}

# Configuration
PS_VERSION="${PS_VERSION:-$(get_latest_prestashop_version)}"
RECOMMENDED_VERSION=$(get_recommended_php_version "$PS_VERSION")
PHP_VERSION="${PHP_VERSION:-$RECOMMENDED_VERSION}"
if [[ -z $PHP_VERSION ]]; then
  error "Could not find a recommended PHP version for ${PS_VERSION}" 2
fi
PS_FOLDER="/var/www/html"
FLASHLIGHT_IMAGE="prestashop/flashlight:${PS_VERSION}-${PHP_VERSION}"

# Build builder common docker image
docker build --no-cache \
  -f ./Dockerfile \
  --build-arg PS_VERSION=${PS_VERSION} \
  --build-arg PHP_VERSION=${PHP_VERSION} \
  --build-arg PS_FOLDER=${PS_FOLDER} \
  -t ${FLASHLIGHT_IMAGE} \
  .
