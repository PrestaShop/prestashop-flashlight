#!/bin/bash
set -eu

usage() {
  cat <<EOF
Usage: $0 [--dry-run] [--ps-version <version>] [--php-version <version>] [--os-flavour <alpine|debian>] [--server <nginx|apache>]
       [--runner <self-hosted|ubuntu-latest>]

Dispatch the docker-publish workflow for PrestaShop Flashlight images.

Options:
  --dry-run                  Only print the gh commands, do not dispatch nor monitor anything
  --ps-version <version>     Only release this PrestaShop version (e.g. 8.0.0), for every
                             OS flavour, every compatible PHP version, nginx and apache.
                             Wildcards release every matching stable tag (e.g. '8.*', '8.1.*');
                             quote them so the shell does not expand them
  --php-version <version>    Only release images built with this PHP version (e.g. 8.1)
  --os-flavour <flavour>     Only release images for this OS flavour (alpine or debian)
  --server <flavour>         Only release images for this server flavour (nginx or apache)
  --runner <runner>          Runner executing the workflow (self-hosted or ubuntu-latest, default: self-hosted)
  -h, --help                 Show this help

Filters can be combined, each one narrows the set of released images.
Without --ps-version, the full release is built with nginx, or with the --server flavour if given.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

DRY_RUN=false
TARGET_PS_VERSION=""
PHP_FILTER=""
OS_FILTER=""
SERVER_FILTER=""
RUNNER="self-hosted"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --ps-version|--php-version|--os-flavour|--server|--runner)
      [ $# -ge 2 ] || { usage >&2; die "$1 requires a value"; }
      case "$1" in
        --ps-version) TARGET_PS_VERSION="$2" ;;
        --php-version) PHP_FILTER="$2" ;;
        --os-flavour) OS_FILTER="$2" ;;
        --server) SERVER_FILTER="$2" ;;
        --runner) RUNNER="$2" ;;
      esac
      shift 2 ;;
    --ps-version=*) TARGET_PS_VERSION="${1#*=}"; shift ;;
    --php-version=*) PHP_FILTER="${1#*=}"; shift ;;
    --os-flavour=*) OS_FILTER="${1#*=}"; shift ;;
    --server=*) SERVER_FILTER="${1#*=}"; shift ;;
    --runner=*) RUNNER="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option $1" ;;
  esac
done

case "$OS_FILTER" in
  ""|alpine|debian) ;;
  *) die "invalid OS flavour '$OS_FILTER' (expected alpine or debian)" ;;
esac
case "$SERVER_FILTER" in
  ""|nginx|apache) ;;
  *) die "invalid server flavour '$SERVER_FILTER' (expected nginx or apache)" ;;
esac
case "$RUNNER" in
  self-hosted|ubuntu-latest) ;;
  *) die "invalid runner '$RUNNER' (expected self-hosted or ubuntu-latest)" ;;
esac
if [ -n "$PHP_FILTER" ] && ! jq -e --arg v "$PHP_FILTER" 'has($v)' php-flavours.json > /dev/null; then
  die "unknown PHP version '$PHP_FILTER' (see php-flavours.json)"
fi

# get_php_versions <ps_version> <compatible|recommended>
get_php_versions() {
  REGEXP_LIST=$(< prestashop-versions.json jq -r 'keys_unsorted | .[]')
  while IFS= read -r regExp; do
    # shellcheck disable=SC3010
    if [[ $1 =~ $regExp ]]; then
      < prestashop-versions.json jq -r '."'"${regExp}"'".php.'"$2"' | if type == "array" then .[] else . end'
      break;
    fi
  done <<EOF
$REGEXP_LIST
EOF
}

REPO="prestashop/prestashop-flashlight"
WORKFLOW="docker-publish.yml"
TARGET_PLATFORMS="linux/amd64,linux/arm64"
RUN_IDS=""
PUBLISHED=0
LATEST_PS_VERSION=""

# publish <ps_version> <os_flavour> [php_version] [server]
# An empty php_version or server lets the workflow apply its default (recommended PHP, nginx)
publish() {
  local PS="$1" OS="$2" PHP="${3:-}" SERVER="${4:-}"

  # Apply filters against the effective values of the build
  if [ -n "$OS_FILTER" ] && [ "$OS" != "$OS_FILTER" ]; then return; fi
  if [ -n "$SERVER_FILTER" ] && [ "${SERVER:-nginx}" != "$SERVER_FILTER" ]; then return; fi
  if [ -n "$PHP_FILTER" ]; then
    local EFFECTIVE_PHP="$PHP"
    if [ -z "$EFFECTIVE_PHP" ]; then
      local PS_REF="$PS"
      [ "$PS_REF" != latest ] || PS_REF="$LATEST_PS_VERSION"
      EFFECTIVE_PHP=$(get_php_versions "$PS_REF" recommended)
    fi
    if [ "$EFFECTIVE_PHP" != "$PHP_FILTER" ]; then return; fi
  fi

  local FIELDS=(--field ps_version="$PS" --field os_flavour="$OS")
  [ -z "$PHP" ] || FIELDS+=(--field php_version="$PHP")
  [ -z "$SERVER" ] || FIELDS+=(--field server="$SERVER")

  local CMD=(gh workflow run "$WORKFLOW" \
    --repo "$REPO" \
    --field target_platforms="$TARGET_PLATFORMS" "${FIELDS[@]}" \
    --field runner="$RUNNER")
  PUBLISHED=$((PUBLISHED + 1))

  if [ "$DRY_RUN" = true ]; then
    echo "[dry-run] ${CMD[*]}"
    return
  fi

  echo "Publishing" "${FIELDS[@]}"
  "${CMD[@]}"

  sleep 10 # give GitHub some time to register the run

  RUN_ID=$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --json databaseId,headBranch -q '.[0].databaseId')
  RUN_IDS="$RUN_IDS $RUN_ID"
}

monitor() {
  if [ "$PUBLISHED" -eq 0 ]; then
    die "no image matches the given filters"
  fi
  if [ "$DRY_RUN" = true ]; then
    echo "[dry-run] $PUBLISHED workflow run(s) would be dispatched"
    return
  fi
  ./monitor-workflow-runs.sh --run-ids "$RUN_IDS" --workflow "$WORKFLOW" --revive-expired
}

EXCLUDED_TAGS='\/1.5|\/1.6.0|\/1.6.1.0|\/1.6.1.1|\/1.6.1.2|show|alpha|beta|rc|RC|\^|refs\/tags\/.*\/'

# Stable PrestaShop release tags, newest first
get_prestashop_tags() {
  git ls-remote --tags git@github.com:PrestaShop/PrestaShop.git | cut -f2 | grep -Ev "$EXCLUDED_TAGS" | cut -d '/' -f3 | sort -r -V
}

# publish_ps_version <ps_version>
# Build & publish a single prestashop version: every OS flavour, compatible PHP version and server flavour
# Returns 1 when no compatible PHP version is known for this version
publish_ps_version() {
  local PS_VERSION="$1" COMPATIBLE_PHP_VERSIONS OS_FLAVOUR PHP_VERSION SERVER
  COMPATIBLE_PHP_VERSIONS=$(get_php_versions "$PS_VERSION" 'compatible[]')
  [ -n "$COMPATIBLE_PHP_VERSIONS" ] || return 1

  for OS_FLAVOUR in alpine debian; do
    while IFS= read -r PHP_VERSION; do
      # Debian builds are only available for PHP 8.0+
      if [ "$OS_FLAVOUR" = debian ] && [ "${PHP_VERSION%%.*}" -lt 8 ]; then
        continue
      fi
      for SERVER in nginx apache; do
        publish "$PS_VERSION" "$OS_FLAVOUR" "$PHP_VERSION" "$SERVER"
      done
    done <<EOF
$COMPATIBLE_PHP_VERSIONS
EOF
  done
}

if [ -n "$TARGET_PS_VERSION" ]; then
  case "$TARGET_PS_VERSION" in
    *[*?]*)
      # Wildcard: release every matching stable tag (e.g. 8.* or 8.1.*)
      MATCHING_TAGS=""
      for TAG in $(get_prestashop_tags); do
        # shellcheck disable=SC2053
        if [[ $TAG == $TARGET_PS_VERSION ]]; then
          MATCHING_TAGS="$MATCHING_TAGS $TAG"
        fi
      done
      [ -n "$MATCHING_TAGS" ] || die "no PrestaShop tag matches '$TARGET_PS_VERSION'"
      echo "PrestaShop versions matching '$TARGET_PS_VERSION':$MATCHING_TAGS"
      for TAG in $MATCHING_TAGS; do
        publish_ps_version "$TAG" || echo "Warning: no compatible PHP version found for PrestaShop $TAG in prestashop-versions.json, skipping" >&2
      done
      ;;
    *)
      publish_ps_version "$TARGET_PS_VERSION" || die "no compatible PHP version found for PrestaShop $TARGET_PS_VERSION in prestashop-versions.json"
      ;;
  esac

  monitor
  exit 0
fi

PRESTASHOP_TAGS=$(get_prestashop_tags)
PRESTASHOP_TAGS_DEBIAN=$(echo "$PRESTASHOP_TAGS" | grep -Ev '^1.7|1.6')
LATEST_PS_VERSION=$(echo "$PRESTASHOP_TAGS" | head -n 1)
# PRESTASHOP_MAJOR_TAGS=$(
#   MAJOR_TAGS=""
#   for VERSION in $PRESTASHOP_TAGS; do
#     CRITERIA=$(echo "$VERSION" | cut -d. -f1)
#     # shellcheck disable=SC3010
#     if [[ "$CRITERIA" == 1* ]]; then
#       CRITERIA=$(echo "$VERSION" | cut -d. -f1-2)
#     fi
#     if ! echo "$MAJOR_TAGS" | grep -q "^$CRITERIA"; then
#       MAJOR_TAGS="$MAJOR_TAGS\n$VERSION";
#     fi
#   done
#   echo "$MAJOR_TAGS"
# )
PRESTASHOP_MINOR_TAGS=$(
  MINOR_TAGS=$()
  for VERSION in $PRESTASHOP_TAGS; do
    CRITERIA=$(echo "$VERSION" | cut -d. -f1-2)
    # shellcheck disable=SC3010
    if [[ "$CRITERIA" == 1* ]]; then
      CRITERIA=$(echo "$VERSION" | cut -d. -f1-3)
    fi
    if ! echo "$MINOR_TAGS" | grep -q "^$CRITERIA"; then
      MINOR_TAGS+=("$VERSION");
    fi
  done
  echo "${MINOR_TAGS[@]}"
)

# The full release targets a single server flavour (the workflow defaults to nginx)
FULL_SERVER="$SERVER_FILTER"

# Latest
publish latest alpine "" "$FULL_SERVER"
publish latest debian "" "$FULL_SERVER"

# Build & publish every prestashop version with recommended PHP version
for PS_VERSION in $PRESTASHOP_TAGS; do
  publish "$PS_VERSION" alpine "" "$FULL_SERVER"
done

for PS_VERSION in $PRESTASHOP_TAGS_DEBIAN; do
  publish "$PS_VERSION" debian "" "$FULL_SERVER"
done

# Build & publish every prestashop minor version with all compatible PHP versions (alpine only)
for PS_VERSION in $PRESTASHOP_MINOR_TAGS; do
  while IFS= read -r PHP_VERSION; do
    publish "$PS_VERSION" alpine "$PHP_VERSION" "$FULL_SERVER"
  done <<EOF
$(get_php_versions "$PS_VERSION" 'compatible[]')
EOF
done

monitor
