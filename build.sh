#!/bin/bash
set -eo pipefail
cd "$(dirname "$0")"

# Available variables
# -------------------
declare BASE_ONLY;             # -- only build the base image (OS_FLAVOUR) without shipping PrestaShop
declare REBUILD_BASE;          # -- force the rebuild of the base image
declare DRY_RUN;               # -- if used, won't really build the image. Useful to check tags compliance
declare OS_FLAVOUR;            # -- either "alpine" (default) or "debian"
declare PHP_VERSION;           # -- PHP version, defaults to recommended version for PrestaShop
declare PS_VERSION;            # -- PrestaShop version, defaults to latest
declare PUSH;                  # -- set it to "true" if you want to push the resulting image
declare SERVER_FLAVOUR;        # -- either "nginx" (default) or "apache"
declare TARGET_IMAGE;          # -- docker image name, defaults to "prestashop/prestashop-flashlight"
declare TARGET_PLATFORM;       # -- a comma separated list of target platforms (defaults to "linux/amd64")
declare PLATFORM;              # -- alias for $TARGET_PLATFORM
declare ZIP_SOURCE;            # -- the zip to unpack in flashlight
declare CUSTOM_LABELS;         # -- A comma separated list of key=value pairs, for overriding official flashlight labels"
declare CUSTOM_BASE_IMAGE;     # -- A name for overriding the base docker image. Usefull if you need to build the base to a custom repo


# Static configuration
# --------------------
DEFAULT_BASE_DOCKER_IMAGE=prestashop/prestashop-flashlight
DEFAULT_OS="alpine";
DEFAULT_PLATFORM=$(docker system info --format '{{.OSType}}/{{.Architecture}}')
DEFAULT_SERVER="nginx";
GIT_SHA=$(git rev-parse HEAD)

error() {
  echo "$(tput bold)$(tput setaf 1)${1:-Unknown error}$(tput sgr0)"
  exit "${2:-1}"
}

help() {
  echo "$(tput bold)Usage:$(tput sgr0) $0 [options]"
  echo
  echo "$(tput bold)Options:$(tput sgr0)"
  echo "  --help            Display this help message"
  echo "  --base-only       Only build the base image (OS_FLAVOUR) without shipping PrestaShop"
  echo "  --dry-run         Don't really build the image. Useful to check tags compliance"
  echo "  --os-flavour      Either 'alpine' (default) or 'debian'"
  echo "  --php-version     PHP version, defaults to recommended version for PrestaShop"
  echo "  --platform        Alias for --target-platform"
  echo "  --ps-version      PrestaShop version, defaults to latest"
  echo "  --push            Push the resulting image to the registry"
  echo "  --rebuild-base    Force the rebuild of the base image"
  echo "  --server-flavour  Either 'nginx' (default) or 'apache'"
  echo "  --target-image    Docker image name, defaults to 'prestashop/prestashop-flashlight'"
  echo "  --custom-labels   A comma separated list of key=value pairs, for overriding official flashlight labels"
  echo "  --target-platform A comma separated list of target platforms (defaults to 'linux/amd64')"
  echo "  --zip-source      The zip containing the PrestaShop release to build a docker image upon (defaults to PrestaShop source code)"
  echo "  --custom-base-image A name for overriding the base docker image. Usefull if you need to build the base to a custom repo"
  echo ""
  echo "$(tput bold)Environment variables:$(tput sgr0)"
  echo "  BASE_ONLY         Only build the base image (OS_FLAVOUR) without shipping PrestaShop"
  echo "  DRY_RUN           Don't really build the image. Useful to check tags compliance"
  echo "  OS_FLAVOUR        Either 'alpine' (default) or 'debian'"
  echo "  PHP_VERSION       PHP version, defaults to recommended version for PrestaShop"
  echo "  PS_VERSION        PrestaShop version, defaults to latest"
  echo "  PUSH              Set it to 'true' if you want to push the resulting image"
  echo "  REBUILD_BASE      Force the rebuild of the base image"
  echo "  SERVER_FLAVOUR    Either 'nginx' (default) or 'apache'"
  echo "  TARGET_IMAGE      Docker image name, defaults to 'prestashop/prestashop-flashlight'"
  echo "  CUSTOM_LABELS     A comma separated list of key=value pairs, for overriding official flashlight labels"
  echo "  TARGET_PLATFORM   A comma separated list of target platforms (defaults to 'linux/amd64')"
  echo "  ZIP_SOURCE        The zip containing the PrestaShop release to build a docker image upon (defaults to PrestaShop source code)"
  echo "  CUSTOM_BASE_IMAGE A name for overriding the base docker image. Usefull if you need to build the base to a custom repo"
}

# Parsing input arguments
# -----------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help) help; exit 0;;
    --base-only) BASE_ONLY=true; shift;;
    --dry-run) DRY_RUN=true; shift;;
    --os-flavour) OS_FLAVOUR="$2"; shift; shift;;
    --php-version) PHP_VERSION="$2"; shift; shift;;
    --platform) TARGET_PLATFORM="$2"; shift; shift;;
    --ps-version) PS_VERSION="$2"; shift; shift;;
    --push) PUSH=true; shift;;
    --rebuild-base) REBUILD_BASE=true; shift;;
    --server-flavour) SERVER_FLAVOUR="$2"; shift; shift;;
    --target-image) TARGET_IMAGE="$2"; shift; shift;;
    --custom-labels) CUSTOM_LABELS="$2"; shift; shift;;
    --zip-source) ZIP_SOURCE="$2"; shift; shift;;
    --custom-base-image) CUSTOM_BASE_IMAGE="$2"; shift; shift;;
    *) error "Unknown option: $1" 2;;
  esac
done

# Default configuration
# ---------------------
PUSH=${PUSH:-false}
BASE_ONLY=${BASE_ONLY:-false}
REBUILD_BASE=${REBUILD_BASE:-$BASE_ONLY}
DRY_RUN=${DRY_RUN:-false}
TARGET_PLATFORM="${TARGET_PLATFORM:-${PLATFORM:-$DEFAULT_PLATFORM}}"
BASE_DOCKER_IMAGE="${CUSTOM_BASE_IMAGE:-${DEFAULT_BASE_DOCKER_IMAGE}}"
LABELS=(
  "--label" "org.opencontainers.image.title=\"Prestashop Flashlight\""
  "--label" "org.opencontainers.image.description=\"PrestaShop Flashlight testing utility\""
  "--label" "org.opencontainers.image.source=\"https://github.com/PrestaShop/prestashop-flashlight\""
  "--label" "org.opencontainers.image.url=\"https://github.com/PrestaShop/prestashop-flashlight\""
  "--label" "org.opencontainers.image.licenses=\"MIT\""
  "--label" "org.opencontainers.image.created=\"$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")\""
);

get_latest_prestashop_version() {
  curl --silent --show-error --fail --location --request GET \
    'https://api.github.com/repos/prestashop/prestashop/releases/latest' | jq -r '.tag_name'
}

get_recommended_php_version() {
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

get_recommended_nodejs_version() {
  local PS_VERSION=$1;
  local RECOMMENDED_VERSION=;
  REGEXP_LIST=$(jq -r 'keys_unsorted | .[]' <prestashop-versions.json)
  while IFS= read -r regExp; do
    if [[ $PS_VERSION =~ $regExp ]]; then
      RECOMMENDED_VERSION=$(jq -r '."'"${regExp}"'" | if has("nodejs") then .nodejs.recommended else "0.0.0" end' <prestashop-versions.json)
      break;
    fi
  done <<<"$REGEXP_LIST"
  echo "$RECOMMENDED_VERSION";
}

get_php_base_image() {
   local OS_FLAVOUR=${1:-};
   local SERVER_FLAVOUR=${2:-};
   local PHP_VERSION=${3:-};
   jq -r '."'"${PHP_VERSION}"'".'"${OS_FLAVOUR}" <php-flavours.json;
}

get_ps_version() {
  local PS_VERSION=${1:-};
  if [ -z "$PS_VERSION" ] || [ "$PS_VERSION" == "latest" ] ; then
    get_latest_prestashop_version;
  else
    echo "$PS_VERSION";
  fi
}

get_php_version() {
  local PHP_VERSION=${1:-};
  local PS_VERSION=${2:-};
  if [ -z "$PHP_VERSION" ] || [ "$PHP_VERSION" == "latest" ] ; then
    get_recommended_php_version "$PS_VERSION"
  else
    echo "$PHP_VERSION";
  fi
}

#
# if the build is for the latest image of the default OS with the recommended PHP version, these tags will be like:
# * latest
# * php-8.2
# * 8.1.1
# * 8.1.1-8.2
# * 8.1.1-8.2-alpine
#
get_target_images() {
  local PHP_BASE_IMAGE=${1:-};
  local PS_VERSION=${2:-};
  local PHP_VERSION=${3:-};
  local OS_FLAVOUR=${4:-};
  declare RES;
  if [ "$PS_VERSION" == "nightly" ]; then
    if [ "$OS_FLAVOUR" = "$DEFAULT_OS" ]; then
      RES="-t ${BASE_DOCKER_IMAGE}:nightly-${SERVER_FLAVOUR}";
    else 
      RES="-t ${BASE_DOCKER_IMAGE}:nightly-${OS_FLAVOUR}-${SERVER_FLAVOUR}";
    fi
  else
    if [ "$PS_VERSION" = "$(get_latest_prestashop_version)" ] \
      && [ "$OS_FLAVOUR" = "$DEFAULT_OS" ] \
      && [ "$PHP_VERSION" = "$(get_recommended_php_version "$PS_VERSION")" ] \
      && [ "$SERVER_FLAVOUR" = "$DEFAULT_SERVER" ]; then
      RES="-t ${BASE_DOCKER_IMAGE}:latest";
    fi
    if [ "$OS_FLAVOUR" = "$DEFAULT_OS" ]; then
      RES="${RES} -t ${BASE_DOCKER_IMAGE}:${PS_VERSION}-${PHP_VERSION}-${SERVER_FLAVOUR}";
      if [ "$PHP_VERSION" = "$(get_recommended_php_version "$PS_VERSION")" ]; then
        RES="${RES} -t ${BASE_DOCKER_IMAGE}:${PS_VERSION}-${SERVER_FLAVOUR}";
        RES="${RES} -t ${BASE_DOCKER_IMAGE}:php-${PHP_VERSION}-${SERVER_FLAVOUR}";
      fi
    fi
    RES="${RES} -t ${BASE_DOCKER_IMAGE}:${PS_VERSION}-${PHP_BASE_IMAGE}-${SERVER_FLAVOUR}";
    RES="${RES} -t ${BASE_DOCKER_IMAGE}:${PS_VERSION}-${OS_FLAVOUR}-${SERVER_FLAVOUR}";
  fi
  echo "$RES";
}

# Applying configuration
# ----------------------
PS_VERSION=$(get_ps_version "$PS_VERSION");
PHP_VERSION=$(get_php_version "$PHP_VERSION" "$PS_VERSION");
if [ -z "$PHP_VERSION" ]; then
  error "Could not find a recommended PHP version for PS_VERSION: $PS_VERSION" 2
fi
OS_FLAVOUR=${OS_FLAVOUR:-$DEFAULT_OS};
SERVER_FLAVOUR=${SERVER_FLAVOUR:-$DEFAULT_SERVER};
PHP_BASE_IMAGE=$(get_php_base_image "$OS_FLAVOUR" "$SERVER_FLAVOUR" "$PHP_VERSION");
NODE_VERSION=$(get_recommended_nodejs_version "$PS_VERSION");
if [ "$PHP_BASE_IMAGE" == "null" ]; then
  error "Could not find a PHP flavour for $OS_FLAVOUR + $SERVER_FLAVOUR + $PHP_VERSION" 2;
fi
if [ -z "${TARGET_IMAGE:+x}" ]; then
  read -ra TARGET_IMAGES <<<"$(get_target_images "$PHP_BASE_IMAGE" "$PS_VERSION" "$PHP_VERSION" "$OS_FLAVOUR")"
else
  read -ra TARGET_IMAGES <<<"-t $TARGET_IMAGE"
fi

# If ZIP_SOURCE is not defined, set it based on PS_VERSION
if [ -z "$ZIP_SOURCE" ]; then
  if [ "$PS_VERSION" == "nightly" ]; then
    ZIP_SOURCE="https://storage.googleapis.com/prestashop-core-nightly/nightly.zip"
  else
    ZIP_SOURCE="https://github.com/PrestaShop/PrestaShop/releases/download/${PS_VERSION}/prestashop_${PS_VERSION}.zip"
  fi
fi

# Build image labels
# ------------------
if [ -n "$CUSTOM_LABELS" ]; then
  LABELS=()
  IFS="," read -ra labels <<< "$(echo "$CUSTOM_LABELS" | sed -E 's/^[\x27\x22]|[\x27\x22]$//g')" # We don't need starting or ending quotes
  for label in "${labels[@]}"; do
    IFS="=" read -ra parts <<< "$label"
    LABELS+=("--label" "${parts[0]}=\"${parts[1]}\"")
  done
fi

# Build the docker image
# ----------------------
CACHE_IMAGE=$BASE_DOCKER_IMAGE:base-${PHP_BASE_IMAGE}-${SERVER_FLAVOUR}
if [ "$DRY_RUN" == "true" ]; then
  docker() {
    echo docker "$@"
  }
fi

docker pull "$CACHE_IMAGE" 2> /dev/null || REBUILD_BASE='true';

if [ "$REBUILD_BASE" == "true" ]; then
  echo "building base for $PHP_BASE_IMAGE $SERVER_FLAVOUR ($TARGET_PLATFORM)"
  docker buildx build \
    --progress=plain \
    --file "./docker/$OS_FLAVOUR-base.Dockerfile" \
    --platform "$TARGET_PLATFORM" \
    --cache-from type=registry,ref="$CACHE_IMAGE" \
    --cache-to type=inline \
    --build-arg PHP_BASE_IMAGE="$PHP_BASE_IMAGE" \
    --build-arg PHP_VERSION="$PHP_VERSION" \
    --build-arg NODE_VERSION="$NODE_VERSION" \
    --build-arg GIT_SHA="$GIT_SHA" \
    --build-arg SERVER_FLAVOUR="$SERVER_FLAVOUR" \
    "${LABELS[@]}" \
    --tag "$BASE_DOCKER_IMAGE:base-${PHP_BASE_IMAGE}-${SERVER_FLAVOUR}" \
    "$([ "${PUSH}" == "true" ] && echo "--push" || echo "--load")" \
    .
fi

if [ "$BASE_ONLY" == "false" ]; then
  docker buildx build \
    --progress=plain \
    --file "./docker/flashlight.Dockerfile" \
    --platform "$TARGET_PLATFORM" \
    --cache-from type=registry,ref="$CACHE_IMAGE" \
    --cache-to type=inline \
    --build-arg PHP_BASE_IMAGE="$PHP_BASE_IMAGE" \
    --build-arg PS_VERSION="$PS_VERSION" \
    --build-arg PHP_VERSION="$PHP_VERSION" \
    --build-arg GIT_SHA="$GIT_SHA" \
    --build-arg ZIP_SOURCE="$ZIP_SOURCE" \
    --build-arg SERVER_FLAVOUR="$SERVER_FLAVOUR" \
    --build-arg BASE_DOCKER_IMAGE="$BASE_DOCKER_IMAGE" \
    "${LABELS[@]}" \
    "${TARGET_IMAGES[@]}" \
    "$([ "${PUSH}" == "true" ] && echo "--push" || echo "--load")" \
    .
fi
