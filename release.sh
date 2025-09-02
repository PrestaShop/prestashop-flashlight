#!/bin/bash
set -eu
EXCLUDED_TAGS='\/1.5|\/1.6.0|alpha|beta|rc|RC|\^'
PRESTASHOP_TAGS=$(git ls-remote --tags git@github.com:PrestaShop/PrestaShop.git | cut -f2 | grep -Ev $EXCLUDED_TAGS | cut -d '/' -f3 | sort -r -V)
PRESTASHOP_TAGS_DEBIAN=$(echo "$PRESTASHOP_TAGS" | grep -Ev '^1.7|1.6')
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

get_compatible_php_version() {
  REGEXP_LIST=$(< prestashop-versions.json jq -r 'keys_unsorted | .[]')
  while IFS= read -r regExp; do
    # shellcheck disable=SC3010
    if [[ $1 =~ $regExp ]]; then
      < prestashop-versions.json jq -r '."'"${regExp}"'".php.compatible[]'
      break;
    fi
  done <<EOF
$REGEXP_LIST
EOF
}

REPO="prestashop/prestashop-flashlight"
WORKFLOW="docker-publish.yml"
RUNNER="self-hosted"
TARGET_PLATFORMS="linux/amd64,linux/arm64"
RUN_IDS=""
publish() {
  echo "Publishing" "$@"
  gh workflow run "$WORKFLOW" \
    --repo "$REPO" \
    --field target_platforms="$TARGET_PLATFORMS" "$@" \
    --field runner="$RUNNER"
  
  sleep 10 # give GitHub some time to register the run

  RUN_ID=$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --json databaseId,headBranch -q '.[0].databaseId')
  RUN_IDS="$RUN_IDS $RUN_ID"
}

# Latest
publish --field ps_version=latest --field os_flavour=alpine
publish --field ps_version=latest --field os_flavour=debian

# Build & publish every prestashop version with recommended PHP version
for PS_VERSION in $PRESTASHOP_TAGS; do
  publish --field ps_version="$PS_VERSION" --field os_flavour=alpine
done

for PS_VERSION in $PRESTASHOP_TAGS_DEBIAN; do
  publish --field ps_version="$PS_VERSION" --field os_flavour=debian
done

# Build & publish every prestashop minor version with all compatible PHP versions (alpine only)
for PS_VERSION in $PRESTASHOP_MINOR_TAGS; do
  while IFS= read -r PHP_VERSION; do
    publish --field ps_version="$PS_VERSION" --field php_version="$PHP_VERSION"
  done <<EOF
$(get_compatible_php_version "$PS_VERSION")
EOF
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