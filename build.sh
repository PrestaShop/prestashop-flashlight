#!/bin/bash
set -eu -o pipefail
cd "$(dirname "$0")"

# Available variables
# -------------------
declare PS_VERSION;      # -- PrestaShop version, defaults to latest
declare PHP_VERSION;     # -- PHP version, defaults to recommended version for PrestaShop
declare OS_FLAVOUR;      # -- either "alpine" (default) or "debian"
declare SERVER_FLAVOUR;  # -- not implemented, either "nginx" (default) or "apache"
declare PLATFORM;        # -- a comma separated list of target platforms (defaults to "linux/amd64")
declare TAG;             # -- overrides automatically generated tag for the docker image
declare TARGET_IMAGE;    # -- docker image name, defaults to "prestashop/prestashop-flashlight"
declare PUSH;            # -- set it to "true" if you want to push the resulting image

# Static configuration
# --------------------
DEFAULT_OS="alpine";
DEFAULT_SERVER="nginx";
DEFAULT_DOCKER_IMAGE=prestashop/prestashop-flashlight

function error {
  echo -e "\e[1;31m${1:-Unknown error}\e[0m"
  exit "${2:-1}"
}

function get_latest_prestashop_version {
  curl --silent --location --request GET \
    'https://api.github.com/repos/prestashop/prestashop/releases/latest' | jq -r '.tag_name'
}

function get_recommended_php_version {
  local PS_VERSION=$1;
  local RECOMMENDED_VERSION=;
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
   local OS_FLAVOUR=${1:-};
   local SERVER_FLAVOUR=${2:-};
   local PHP_VERSION=${3:-};
   jq -r '."'"${PHP_VERSION}"'".'"${OS_FLAVOUR}" <php-flavours.json;
}

function get_tag {
  local TAG=${1:-};
  local PS_VERSION=${2:-};
  local PHP_VERSION=${3:-};
  if [ "$PS_VERSION" == "latest" ] && [ "$PHP_VERSION" == "latest" ]; then
    echo "latest";
  elif [ -z "$PS_VERSION" ] && [ -z "$PHP_VERSION" ]; then
    echo "latest";
  elif [ -n "$TAG" ]; then
    echo "$TAG";
  else
    echo "auto"
  fi
}

function get_ps_version {
  local PS_VERSION=${1:-};
  if [ -z "$PS_VERSION" ] || [ "$PS_VERSION" == "latest" ] ; then
    get_latest_prestashop_version;
  else
    echo "$PS_VERSION";
  fi
}

function get_php_version {
  local PHP_VERSION=${1:-};
  local PS_VERSION=${2:-};
  if [ -z "$PHP_VERSION" ] || [ "$PHP_VERSION" == "latest" ] ; then
    get_recommended_php_version "$PS_VERSION"
  else 
    echo "$PHP_VERSION";
  fi
}

function get_target_images {
  local TAG=${1:-};
  local PHP_FLAVOUR=${2:-};
  local PS_VERSION=${3:-};
  local PHP_VERSION=${4:-};
  declare RES;
  [ "$TAG" == "latest" ] && RES="-t ${DEFAULT_DOCKER_IMAGE}:latest";
  [[ "$PHP_FLAVOUR" == *"$DEFAULT_OS" ]] && RES="${RES} -t ${DEFAULT_DOCKER_IMAGE}:${PS_VERSION}-${PHP_VERSION}";
  RES="${RES} -t ${DEFAULT_DOCKER_IMAGE}:${PS_VERSION}-${PHP_FLAVOUR}";
  echo "$RES";
}

# Applying configuration
# ----------------------
TAG=$(get_tag "${TAG}" "${PS_VERSION}" "${PHP_VERSION}");
PS_VERSION=$(get_ps_version "${PS_VERSION}");
PHP_VERSION=$(get_php_version "${PHP_VERSION}" "$PS_VERSION");
if [ -z "$PHP_VERSION" ]; then
  error "Could not find a recommended PHP version for PS_VERSION: ${PS_VERSION}" 2
fi
[ "$TAG" == "auto" ] && TAG="${PS_VERSION}-${PHP_VERSION}";
OS_FLAVOUR=${OS_FLAVOUR:-$DEFAULT_OS};
SERVER_FLAVOUR=${SERVER_FLAVOUR:-$DEFAULT_SERVER};
PHP_FLAVOUR=$(get_php_flavour "$OS_FLAVOUR" "$SERVER_FLAVOUR" "$PHP_VERSION");
if [ "$PHP_FLAVOUR" == "null" ]; then
  error "Could not find a PHP flavour for $OS_FLAVOUR + $SERVER_FLAVOUR + $PHP_VERSION" 2;
fi
if [ -z "${TARGET_IMAGE:+x}" ]; then
  read -ra TARGET_IMAGES <<<"$(get_target_images "$TAG" "$PHP_FLAVOUR" "$PS_VERSION" "$PHP_VERSION")"
else
  read -ra TARGET_IMAGES <<<"-t $TARGET_IMAGE"
fi

# Build the docker image
# ----------------------
docker buildx build \
  --file "./docker/${OS_FLAVOUR}.Dockerfile" \
  --platform "${PLATFORM:-linux/amd64}" \
  --build-arg PHP_FLAVOUR="${PHP_FLAVOUR}" \
  --build-arg PS_VERSION="${PS_VERSION}" \
  --build-arg PHP_VERSION="${PHP_VERSION}" \
  --label org.opencontainers.image.title="PrestaShop FlashLight" \
  --label org.opencontainers.image.description="PrestaShop FlashLight testing utility" \
  --label org.opencontainers.image.source=https://github.com/PrestaShop/prestashop-flashlight \
  --label org.opencontainers.image.url=https://github.com/PrestaShop/prestashop-flashlight \
  --label org.opencontainers.image.licenses=MIT \
  --label org.opencontainers.image.created="$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")" \
  "${TARGET_IMAGES[@]}" \
  "$([ "${PUSH}" == "true" ] && echo "--push" || echo "--load")" \
  .
