#!/bin/sh
set -eu

RUN_IDS=""
REPO="prestashop/prestashop-flashlight"
WORKFLOW="docker-base-publish.yml"
RUNNER="self-hosted"
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


# Monitoring loop
# Can be a workaround for dockerhub's pull rate limit
# Will rerun failed jobs every 30 minutes, until they succeed
echo "Monitoring workflow runs..."
while :; do
  ALL_DONE=true
  for RUN_ID in $RUN_IDS; do
    STATUS=$(gh run view "$RUN_ID" --repo prestashop/prestashop-flashlight --json status,conclusion -q '.status')
    CONCLUSION=$(gh run view "$RUN_ID" --repo prestashop/prestashop-flashlight --json status,conclusion -q '.conclusion')

    if [ "$STATUS" != "completed" ]; then
      echo "Run $RUN_ID still in progress..."
      ALL_DONE=false
    elif [ "$CONCLUSION" = "failure" ]; then
      echo "Run $RUN_ID failed, restarting..."
      gh run rerun "$RUN_ID" --repo prestashop/prestashop-flashlight
      ALL_DONE=false
    fi
  done

  if [ "$ALL_DONE" = true ]; then
    echo "All workflow runs completed successfully!"
    break
  fi

  echo "Waiting 30 minutes before next check..."
  sleep 1800
done
