#!/bin/bash
set -eo pipefail
cd "$(dirname "$0")"

# Available variables
# -------------------
declare BASE_ONLY;             # -- only build the base image (OS_FLAVOUR) without shipping PrestaShop
declare CUSTOM_LABELS;         # -- A comma separated list of key=value pairs, for overriding official flashlight labels"
declare DRY_RUN;               # -- if used, won't really build the image. Useful to check tags compliance
declare OS_FLAVOUR;            # -- either "alpine" (default) or "debian"
declare PHP_VERSION;           # -- PHP version, defaults to recommended version for PrestaShop
declare PLATFORM;              # -- alias for $TARGET_PLATFORM
declare PS_VERSION;            # -- PrestaShop version, defaults to latest
declare PUSH;                  # -- set it to "true" if you want to push the resulting image
declare REBUILD_BASE;          # -- force the rebuild of the base image
declare SERVER_FLAVOUR;        # -- either "nginx" (default) or "apache"
declare TARGET_IMAGE;          # -- docker image name and tag, defaults to "$TARGET_IMAGE_NAME:$TARGET_IMAGE_TAG"
declare TARGET_IMAGE_NAME;     # -- docker image name, defaults to "prestashop/prestashop-flashlight"
declare TARGET_IMAGE_TAG;      # -- docker image tag, defaults to automatic tags based on the os flavour, php and prestashop versions
declare TARGET_PLATFORM;       # -- a comma separated list of target platforms, defaults to "linux/amd64"
declare ZIP_SOURCE;            # -- the zip to unpack in flashlight

error() {
  echo "$(tput bold)$(tput setaf 1)${1:-Unknown error}$(tput sgr0)"
  exit "${2:-1}"
}

help() {
  echo "$(tput bold)Usage:$(tput sgr0) $0 [options]"
  echo
  echo "$(tput bold)Options:$(tput sgr0)"
  echo "  --help               Display this help message"
  echo "  --base-only          Only build the base image (OS_FLAVOUR) without shipping PrestaShop"
  echo "  --custom-labels      A comma separated list of key=value pairs, for overriding official flashlight labels"
  echo "  --dry-run            Don't really build the image. Useful to check tags compliance"
  echo "  --os-flavour         Either 'alpine' (default) or 'debian'"
  echo "  --php-version        PHP version, defaults to recommended version for PrestaShop"
  echo "  --platform           Alias for --target-platform"
  echo "  --ps-version         PrestaShop version, defaults to latest"
  echo "  --push               Push the resulting image to the registry"
  echo "  --rebuild-base       Force the rebuild of the base image"
  echo "  --server-flavour     Either 'nginx' (default) or 'apache'"
  echo "  --target-image       Docker image name and tag, defaults to TARGET_IMAGE_NAME:TARGET_IMAGE_TAG"
  echo "  --target-image-name  Docker image name, defaults to \"prestashop/prestashop-flashlight\""
  echo "  --target-image-tag   Docker image tag, defaults to automatic tags based on the os flavour, php and prestashop versions"
  echo "  --target-platform    A comma separated list of target platforms, defaults to 'linux/amd64'"
  echo "  --zip-source         The zip containing the PrestaShop release to build a docker image upon (defaults to PrestaShop source code)"
  echo ""
  echo "$(tput bold)Environment variables:$(tput sgr0)"
  echo "  BASE_ONLY          Only build the base image (OS_FLAVOUR) without shipping PrestaShop"
  echo "  CUSTOM_LABELS      A comma separated list of key=value pairs, for overriding official flashlight labels"
  echo "  DRY_RUN            Don't really build the image. Useful to check tags compliance"
  echo "  OS_FLAVOUR         Either 'alpine' (default) or 'debian'"
  echo "  PHP_VERSION        PHP version, defaults to recommended version for PrestaShop"
  echo "  PS_VERSION         PrestaShop version, defaults to latest"
  echo "  PUSH               Set it to 'true' if you want to push the resulting image"
  echo "  REBUILD_BASE       Force the rebuild of the base image"
  echo "  SERVER_FLAVOUR     Either 'nginx' (default) or 'apache'"
  echo "  TARGET_IMAGE       Docker image name, defaults to TARGET_IMAGE_NAME:TARGET_IMAGE_TAG"
  echo "  TARGET_IMAGE_NAME  Docker image name, defaults to \"prestashop/prestashop-flashlight\""
  echo "  TARGET_IMAGE_TAG   Docker image tag, defaults to automatic tags based on the os flavour, php and prestashop versions"
  echo "  TARGET_PLATFORM    A comma separated list of target platforms, defaults to 'linux/amd64'"
  echo "  ZIP_SOURCE         The zip containing the PrestaShop release to build a docker image upon (defaults to PrestaShop source code)"
}

# Parsing input arguments
# -----------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help) help; exit 0;;
    --base-only) BASE_ONLY=true; shift;;
    --custom-labels) CUSTOM_LABELS="$2"; shift; shift;;
    --dry-run) DRY_RUN=true; shift;;
    --os-flavour) OS_FLAVOUR="$2"; shift; shift;;
    --php-version) PHP_VERSION="$2"; shift; shift;;
    --platform) TARGET_PLATFORM="$2"; shift; shift;;
    --ps-version) PS_VERSION="$2"; shift; shift;;
    --push) PUSH=true; shift;;
    --rebuild-base) REBUILD_BASE=true; shift;;
    --server-flavour) SERVER_FLAVOUR="$2"; shift; shift;;
    --target-image) TARGET_IMAGE="$2"; shift; shift;;
    --target-image-name) TARGET_IMAGE_NAME="$2"; shift; shift;;
    --target-image-tag) TARGET_IMAGE_TAG="$2"; shift; shift;;
    --zip-source) ZIP_SOURCE="$2"; shift; shift;;
    *) error "Unknown option: $1" 2;;
  esac
done

# Default configuration
# ---------------------
BASE_ONLY=${BASE_ONLY:-false}
DEFAULT_OS="alpine";
DEFAULT_PLATFORM=$(docker system info --format '{{.OSType}}/{{.Architecture}}')
DEFAULT_SERVER="nginx";
DRY_RUN=${DRY_RUN:-false}
GIT_SHA=$(git rev-parse HEAD)
PUSH=${PUSH:-false}
REBUILD_BASE=${REBUILD_BASE:-$BASE_ONLY}
TARGET_PLATFORM="${TARGET_PLATFORM:-${PLATFORM:-$DEFAULT_PLATFORM}}"
LABELS=(
  "--label" "org.opencontainers.image.title=\"Prestashop Flashlight\""
  "--label" "org.opencontainers.image.description=\"PrestaShop Flashlight testing utility\""
  "--label" "org.opencontainers.image.source=\"https://github.com/PrestaShop/prestashop-flashlight\""
  "--label" "org.opencontainers.image.url=\"https://github.com/PrestaShop/prestashop-flashlight\""
  "--label" "org.opencontainers.image.licenses=\"MIT\""
  "--label" "org.opencontainers.image.created=\"$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")\""
);

TARGET_IMAGE_NAME=${TARGET_IMAGE_NAME:-prestashop/prestashop-flashlight}

# if the tag is defined there won't be auto
if [ -n "$TARGET_IMAGE_TAG" ]; then
  TARGET_IMAGE=${TARGET_IMAGE_NAME}:${TARGET_IMAGE_TAG}
fi

get_latest_prestashop_version() {
  curl --silent --show-error --fail --location --request GET \
    'https://api.github.com/repos/prestashop/prestashop/releases' |
      jq -r '
      [.[] 
        | select(.tag_name | test("^\\d+\\.\\d+\\.\\d+(\\.\\d+)?$")) 
        | {
            tag: .tag_name,
            major: (.tag_name | capture("(?<n>\\d+)") | .n | tonumber),
            minor: (.tag_name | capture("^\\d+\\.(?<n>\\d+)") | .n | tonumber),
            patch: (.tag_name | capture("^\\d+\\.\\d+\\.(?<n>\\d+)") | .n | tonumber),
            build: (
              if (.tag_name | test("^\\d+\\.\\d+\\.\\d+\\.\\d+$")) 
              then (.tag_name | capture("^\\d+\\.\\d+\\.\\d+\\.(?<n>\\d+)$") | .n | tonumber)
              else 0
              end
            )
          }
      ] 
      | sort_by(.major, .minor, .patch, .build) 
      | reverse 
      | .[0].tag'
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

get_recommended_zip_source_if_any() {
  local PS_VERSION=$1;
  local RECOMMENDED_ZIP_SOURCE=;
  REGEXP_LIST=$(jq -r 'keys_unsorted | .[]' <prestashop-versions.json)
  while IFS= read -r regExp; do
    if [[ $PS_VERSION =~ $regExp ]]; then
      RECOMMENDED_ZIP_SOURCE=$(jq -r '."'"${regExp}"'".zip_source' <prestashop-versions.json)
      break;
    fi
  done <<<"$REGEXP_LIST"
  echo "$RECOMMENDED_ZIP_SOURCE";
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
      RES="-t ${TARGET_IMAGE_NAME}:nightly-${SERVER_FLAVOUR}";
    else 
      RES="-t ${TARGET_IMAGE_NAME}:nightly-${OS_FLAVOUR}-${SERVER_FLAVOUR}";
    fi
  else
    if [ "$PS_VERSION" = "$(get_latest_prestashop_version)" ] \
      && [ "$OS_FLAVOUR" = "$DEFAULT_OS" ] \
      && [ "$PHP_VERSION" = "$(get_recommended_php_version "$PS_VERSION")" ] \
      && [ "$SERVER_FLAVOUR" = "$DEFAULT_SERVER" ]; then
      RES="-t ${TARGET_IMAGE_NAME}:latest";
    fi
    if [ "$OS_FLAVOUR" = "$DEFAULT_OS" ]; then
      RES="${RES} -t ${TARGET_IMAGE_NAME}:${PS_VERSION}-${PHP_VERSION}-${SERVER_FLAVOUR}";
      if [ "$PHP_VERSION" = "$(get_recommended_php_version "$PS_VERSION")" ]; then
        RES="${RES} -t ${TARGET_IMAGE_NAME}:${PS_VERSION}-${SERVER_FLAVOUR}";
        RES="${RES} -t ${TARGET_IMAGE_NAME}:php-${PHP_VERSION}-${SERVER_FLAVOUR}";
      fi
    fi
    RES="${RES} -t ${TARGET_IMAGE_NAME}:${PS_VERSION}-${PHP_BASE_IMAGE}-${SERVER_FLAVOUR}";
    RES="${RES} -t ${TARGET_IMAGE_NAME}:${PS_VERSION}-${OS_FLAVOUR}-${SERVER_FLAVOUR}";
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
BASE_DOCKER_IMAGE="$TARGET_IMAGE_NAME:base-${PHP_BASE_IMAGE}-${SERVER_FLAVOUR}"

# If ZIP_SOURCE is not defined, set it based on PS_VERSION
if [ -z "$ZIP_SOURCE" ]; then
  if [ "$PS_VERSION" == "nightly" ]; then
    ZIP_SOURCE="https://storage.googleapis.com/prestashop-core-nightly/nightly.zip"
  else
    RECOMMENDED_ZIP_SOURCE=$(get_recommended_zip_source_if_any "$PS_VERSION")
    if [ "$RECOMMENDED_ZIP_SOURCE" != "" ] && [ "$RECOMMENDED_ZIP_SOURCE" != "null" ]; then
      ZIP_SOURCE="$RECOMMENDED_ZIP_SOURCE"
    else
      ZIP_SOURCE="https://github.com/PrestaShop/PrestaShop/releases/download/${PS_VERSION}/prestashop_${PS_VERSION}.zip"
    fi
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
if [ "$DRY_RUN" == "true" ]; then
  docker() {
    echo docker "$@"
  }
fi

# acts as a cache if available
docker pull "$BASE_DOCKER_IMAGE" 2> /dev/null || REBUILD_BASE='true';

if [ "$REBUILD_BASE" == "true" ]; then
  echo "building base for $PHP_BASE_IMAGE $SERVER_FLAVOUR ($TARGET_PLATFORM) named $BASE_DOCKER_IMAGE"
  docker buildx build \
    --progress=plain \
    --file "./docker/$OS_FLAVOUR-base.Dockerfile" \
    --platform "$TARGET_PLATFORM" \
    --cache-from type=registry,ref="$BASE_DOCKER_IMAGE" \
    --cache-to type=inline \
    --build-arg PHP_BASE_IMAGE="$PHP_BASE_IMAGE" \
    --build-arg PHP_VERSION="$PHP_VERSION" \
    --build-arg NODE_VERSION="$NODE_VERSION" \
    --build-arg GIT_SHA="$GIT_SHA" \
    --build-arg SERVER_FLAVOUR="$SERVER_FLAVOUR" \
    "${LABELS[@]}" \
    -t "$BASE_DOCKER_IMAGE" \
    "$([ "${PUSH}" == "true" ] && echo "--push" || echo "--load")" \
    .
fi

if [ "$BASE_ONLY" == "false" ]; then
  echo "building final based on $BASE_DOCKER_IMAGE named ${TARGET_IMAGES[*]}"
  docker buildx build \
    --progress=plain \
    --file "./docker/flashlight.Dockerfile" \
    --platform "$TARGET_PLATFORM" \
    --cache-from type=registry,ref="$BASE_DOCKER_IMAGE" \
    --cache-to type=inline \
    --build-arg BASE_DOCKER_IMAGE="$BASE_DOCKER_IMAGE" \
    --build-arg PHP_BASE_IMAGE="$PHP_BASE_IMAGE" \
    --build-arg PS_VERSION="$PS_VERSION" \
    --build-arg PHP_VERSION="$PHP_VERSION" \
    --build-arg GIT_SHA="$GIT_SHA" \
    --build-arg ZIP_SOURCE="$ZIP_SOURCE" \
    --build-arg SERVER_FLAVOUR="$SERVER_FLAVOUR" \
    --build-arg TARGET_IMAGE_NAME="$TARGET_IMAGE_NAME" \
    "${LABELS[@]}" \
    "${TARGET_IMAGES[@]}" \
    "$([ "${PUSH}" == "true" ] && echo "--push" || echo "--load")" \
    .
fi
