#!/bin/bash
set -eu -o pipefail
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

function get_php_flavour {
   OS_FLAVOUR=${1:-}; SERVER_FLAVOUR=${2:-}; PHP_VERSION=${3:-};
   echo $(jq -r '."'${PHP_VERSION}'".'${SERVER_FLAVOUR}'.'${OS_FLAVOUR} <php-flavours.json);
}

function get_tag {
  TAG=${1:-}; PS_VERSION=${2:-}; PHP_VERSION=${3:-};
  if [ "$PS_VERSION" == "latest" ] && [ "$PHP_VERSION" == "latest" ]; then
    echo "latest";
  elif [ -z "$PS_VERSION" ] && [ -z "$PHP_VERSION" ]; then
    echo "latest";
  elif [ -n "$TAG" ]; then
    echo $TAG;
  else
    echo "auto"
  fi
}

function get_ps_version {
  PS_VERSION=${1:-};
  if [ -z $PS_VERSION ] || [ "$PS_VERSION" == "latest" ] ; then
    echo $(get_latest_prestashop_version);
  else
    echo $PS_VERSION;
  fi
}

function get_php_version {
  PHP_VERSION=${1:-}; PS_VERSION=${2:-}
  if [ -z $PHP_VERSION ] || [ "$PHP_VERSION" == "latest" ] ; then
    echo $(get_recommended_php_version $PS_VERSION)
  fi
  echo $PHP_VERSION;
}

# Configuration
# -------------
TAG=$(get_tag "${TAG:-}" "${PS_VERSION:-}" "${PHP_VERSION:-}");
PS_VERSION=$(get_ps_version "${PS_VERSION:-}");
PHP_VERSION=$(get_php_version "${PHP_VERSION:-}" "$PS_VERSION");
if [ -z $PHP_VERSION ]; then
  error "Could not find a recommended PHP version for PS_VERSION: ${PS_VERSION}" 2
fi
[ "$TAG" == "auto" ] && TAG="${PS_VERSION}-${PHP_VERSION}";
if [ "$TAG" == "latest" ]; then
  EXTRA_TAG="${PS_VERSION}-${PHP_VERSION}";
  EXTRA_TARGET_IMAGE=${TARGET_IMAGE:-"prestashop/prestashop-flashlight:${EXTRA_TAG}"}
fi
OS_FLAVOUR=${OS_FLAVOUR:-alpine}
SERVER_FLAVOUR=${SERVER_FLAVOUR:-nginx}
PHP_FLAVOUR=$(get_php_flavour "$OS_FLAVOUR" "$SERVER_FLAVOUR" "$PHP_VERSION");
if [ "$PHP_FLAVOUR" == "null" ]; then
  error "Could not find a PHP flavour for $OS_FLAVOUR + $SERVER_FLAVOUR + $PHP_VERSION" 2
fi
echo $PHP_FLAVOUR
exit 1;
TARGET_IMAGE=${TARGET_IMAGE:-"prestashop/prestashop-flashlight:${TAG}"}

# Build the docker image
# ----------------------
docker buildx build \
  --file "./docker/${PHP_FLAVOUR}.Dockerfile" \
  --platform "${PLATFORM:-linux/amd64}" \
  --build-arg PS_VERSION="${PS_VERSION}" \
  --build-arg PHP_VERSION="${PHP_VERSION}" \
  --label org.opencontainers.image.title="PrestaShop FlashLight" \
  --label org.opencontainers.image.description="PrestaShop FlashLight testing utility" \
  --label org.opencontainers.image.source=https://github.com/PrestaShop/prestashop-flashlight \
  --label org.opencontainers.image.url=https://github.com/PrestaShop/prestashop-flashlight \
  --label org.opencontainers.image.licenses=MIT \
  --label org.opencontainers.image.created="$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")" \
  -t "${TARGET_IMAGE}" \
  "$([ -n "${EXTRA_TAG+x}" ] && echo "-t ${EXTRA_TARGET_IMAGE}" \
  "$([ -n "${PUSH+x}" ] && echo "--push" || echo "--load")" \
  .
