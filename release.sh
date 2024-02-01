#!/bin/sh
set -eu
PRESTASHOP_TAGS=.prestashop-tags
PRESTASHOP_MINOR_TAGS=.prestashop-minor-tags

get_prestashop_tags() {
  git ls-remote --tags git@github.com:PrestaShop/PrestaShop.git \
  | cut -f2 \
  | grep -Ev '\/1.5|\/1.6.0|beta|rc|RC|\^' \
  | cut -d '/' -f3 \
  | sort -r -V > "$PRESTASHOP_TAGS"
}

get_prestashop_minor_tags() {
  printf "" > "$PRESTASHOP_MINOR_TAGS"
  while IFS= read -r version; do
    major_minor=$(echo "$version" | cut -d. -f1-2)
    major_minor_patch=$(echo "$version" | cut -d. -f1-3)
    criteria=$major_minor
    # shellcheck disable=SC3010
    [[ "$major_minor" == 1* ]] && criteria=$major_minor_patch
    if ! grep -q "^$criteria" "$PRESTASHOP_MINOR_TAGS"; then
      echo "$version" >> "$PRESTASHOP_MINOR_TAGS"
    fi
  done < "$PRESTASHOP_TAGS"
}

get_compatible_php_version() {
  local PS_VERSION=$1;
  REGEXP_LIST=$(jq -r 'keys_unsorted | .[]' <prestashop-versions.json)
  while IFS= read -r regExp; do
    if [[ $PS_VERSION =~ $regExp ]]; then
      jq -r '."'"${regExp}"'".php.compatible[]' <prestashop-versions.json
      break;
    fi
  done <<<"$REGEXP_LIST"
}

publish() {
  gh workflow run docker-publish.yml \
  --repo prestashop/prestashop-flashlight \
  --field target_platforms=linux/amd64,linux/arm64 "$@"
}

get_prestashop_tags
get_prestashop_minor_tags

# Latest
publish --field ps_version=latest
publish --field ps_version=latest --field os_flavour=debian

# Recommended PHP for every minor tag
while IFS= read -r PS_VERSION; do
  publish --field ps_version="$PS_VERSION"
  publish --field ps_version="$PS_VERSION" --field os_flavour=debian
done < "$PRESTASHOP_MINOR_TAGS"

# Compatible PHP for every minor tag (alpine only)
while IFS= read -r PS_VERSION; do
  echo "$PS_VERSION:"
  while IFS= read -r PHP_VERSION; do
    echo "--> $PHP_VERSION"
    publish --field ps_version="$PS_VERSION" --filed php_version="$PHP_VERSION"
  done <<<"$(get_compatible_php_version "$PS_VERSION")"
done < "$PRESTASHOP_MINOR_TAGS"
