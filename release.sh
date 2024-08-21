#!/bin/sh
set -eu
EXCLUDED_TAGS='\/1.5|\/1.6.0|alpha|beta|rc|RC|\^'
PRESTASHOP_TAGS=$(git ls-remote --tags git@github.com:PrestaShop/PrestaShop.git | cut -f2 | grep -Ev $EXCLUDED_TAGS | cut -d '/' -f3 | sort -r -V)
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
  MINOR_TAGS=""
  for VERSION in $PRESTASHOP_TAGS; do
    CRITERIA=$(echo "$VERSION" | cut -d. -f1-2)
    # shellcheck disable=SC3010
    if [[ "$CRITERIA" == 1* ]]; then
      CRITERIA=$(echo "$VERSION" | cut -d. -f1-3)
    fi
    if ! echo "$MINOR_TAGS" | grep -q "^$CRITERIA"; then
      MINOR_TAGS="$MINOR_TAGS\n$VERSION";
    fi
  done
  echo "$MINOR_TAGS"
)

get_compatible_php_version() {
  REGEXP_LIST=$(echo "$PRESTASHOP_TAGS" | jq -r 'keys_unsorted | .[]')
  while IFS= read -r regExp; do
    # shellcheck disable=SC3010
    if [[ $1 =~ $regExp ]]; then
      echo "$PRESTASHOP_TAGS" | jq -r '."'"${regExp}"'".php.compatible[]'
      break;
    fi
  done <<EOF
$REGEXP_LIST
EOF
}

publish() {
  gh workflow run docker-publish.yml \
    --repo prestashop/prestashop-flashlight \
    --field target_platforms=linux/amd64,linux/arm64 "$@"
}

# Latest
publish --field ps_version=latest
publish --field ps_version=latest --field os_flavour=debian

# Build & publish every prestashop version with recommended PHP version
for PS_VERSION in $PRESTASHOP_TAGS; do
  publish --field ps_version="$PS_VERSION"
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
