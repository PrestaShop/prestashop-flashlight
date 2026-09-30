#!/bin/sh
set -eu

usage() {
  cat <<EOF
Usage: $0 [--runner <self-hosted|ubuntu-latest>]

Dispatch the docker-base-publish workflow for every PHP version (Alpine and Debian).

Options:
  --runner <runner>    Runner executing the workflow (self-hosted or ubuntu-latest, default: self-hosted)
  -h, --help           Show this help
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

RUNNER="self-hosted"
while [ $# -gt 0 ]; do
  case "$1" in
    --runner)
      [ $# -ge 2 ] || { usage >&2; die "$1 requires a value"; }
      RUNNER="$2"
      shift 2 ;;
    --runner=*) RUNNER="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option $1" ;;
  esac
done

case "$RUNNER" in
  self-hosted|ubuntu-latest) ;;
  *) die "invalid runner '$RUNNER' (expected self-hosted or ubuntu-latest)" ;;
esac

RUN_IDS=""
REPO="prestashop/prestashop-flashlight"
WORKFLOW="docker-base-publish.yml"
TARGET_PLATFORMS="linux/amd64,linux/arm64"

# Launch Alpine builds
PHP_VERSIONS="$(jq -r 'keys | join(" ")' ./php-flavours.json)"
for PHP_VERSION in $PHP_VERSIONS; do
  echo "Publishing Alpine Base for $PHP_VERSION"
  gh workflow run "$WORKFLOW" \
    --repo "$REPO" \
    --field target_platforms="$TARGET_PLATFORMS" \
    --field os_flavour="alpine" \
    --field php_version="$PHP_VERSION" \
    --field runner="$RUNNER"

  sleep 10 # give GitHub some time to register the run

  RUN_ID=$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --json databaseId,headBranch -q '.[0].databaseId')
  RUN_IDS="$RUN_IDS $RUN_ID"
done

# Launch Debian builds
PHP_DEBIAN_VERSIONS="8.0 8.1 8.2 8.3"
for PHP_VERSION in $PHP_DEBIAN_VERSIONS; do
  echo "Publishing Debian Base for $PHP_VERSION"
  gh workflow run "$WORKFLOW" \
    --repo "$REPO" \
    --field target_platforms="$TARGET_PLATFORMS" \
    --field os_flavour="debian" \
    --field php_version="$PHP_VERSION" \
    --field runner="$RUNNER"

  sleep 10 # give GitHub some time to register the run

  RUN_ID=$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --json databaseId,headBranch -q '.[0].databaseId')
  RUN_IDS="$RUN_IDS $RUN_ID"
done

./monitor-workflow-runs.sh --run-ids "$RUN_IDS" --workflow "$WORKFLOW" --revive-expired
