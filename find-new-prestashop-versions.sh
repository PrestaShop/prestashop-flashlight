#!/bin/bash
#
# Detects newly published PrestaShop versions and updates prestashop-versions.json.
#
# PrestaShop 9.x is not published on GitHub releases: its zip lives on
# assets.prestashop3.com in a "<version>-<build>" directory, where <build> is a
# distribution build number that does not appear in the git tag. Versions are
# therefore discovered from the git tags, and the build number is resolved by
# probing the asset URLs.
#
# Versions below 9.0 need no update: their keys are version ranges and their zip
# comes from GitHub releases.
#
# Usage:
#   ./find-new-prestashop-versions.sh [--dry-run]
#
# Outputs (when running in GitHub Actions):
#   changed=true|false    whether prestashop-versions.json was modified
#   body_file=<path>      pull request body describing the changes
set -eu

cd "$(dirname "$0")"

PS_GIT_REPO=${PS_GIT_REPO:-https://github.com/PrestaShop/PrestaShop.git}
PS_RAW_BASE=${PS_RAW_BASE:-https://raw.githubusercontent.com/PrestaShop/PrestaShop}
ASSETS_BASE=${ASSETS_BASE:-https://assets.prestashop3.com/dst/edition/corporate}
VERSIONS_FILE=${VERSIONS_FILE:-prestashop-versions.json}
FLAVOURS_FILE=${FLAVOURS_FILE:-php-flavours.json}
BODY_FILE=${BODY_FILE:-${RUNNER_TEMP:-/tmp}/prestashop-versions-pr-body.md}
# How many build numbers above the highest known one to probe, and how many
# "-B.M" minor build numbers to try for each of them.
BUILD_LOOKAHEAD=${BUILD_LOOKAHEAD:-3}
BUILD_MINOR_LOOKAHEAD=${BUILD_MINOR_LOOKAHEAD:-2}
DRY_RUN=false

if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true;
fi

log() { echo "$@" >&2; }
die() { log "error: $*"; exit 1; }

# ---------------------------------------------------------------------------
# prestashop-versions.json readers
# ---------------------------------------------------------------------------

escape_dots() {
  printf '%s' "$1" | sed 's/\./\\./g';
}

zip_url() {
  echo "${ASSETS_BASE}/$1/prestashop_edition_basic_version_$1.zip";
}

# Every key of every zip_sources map, e.g. "9.1.4-5.0", "9.2.0-6.0-beta.1".
all_zip_keys() {
  jq -r '[.[] | (.zip_sources // {}) | keys[]] | .[]' <"$VERSIONS_FILE";
}

# Highest build number known, all version branches taken together.
global_max_build() {
  local max;
  max=$(all_zip_keys | sed -nE 's/^[0-9]+\.[0-9]+\.[0-9]+-([0-9]+)\.[0-9]+.*$/\1/p' | sort -n | tail -1);
  echo "${max:-1}";
}

# Highest build number known for a single version branch, e.g. "9.1".
branch_max_build() {
  local branch=$1;
  all_zip_keys \
    | grep -E "^$(escape_dots "$branch")\." \
    | sed -nE 's/^[0-9]+\.[0-9]+\.[0-9]+-([0-9]+)\.[0-9]+.*$/\1/p' \
    | sort -n | tail -1;
}

# Is this version already recorded? zip_sources keys carry the build number the
# git tag does not have, so "9.1.4" has to be matched against "9.1.4-5.0".
is_known_version() {
  local core=$1 pre=$2;
  all_zip_keys | grep -qE "^$(escape_dots "$core")-[0-9]+\.[0-9]+$(escape_dots "$pre")$";
}

# The prestashop-versions.json key matching a version, using the same regexp
# matching as build.sh. Empty when the version has no key yet.
matching_key() {
  local version=$1 key;
  while IFS= read -r key; do
    # shellcheck disable=SC3010
    if [[ $version =~ $key ]]; then
      echo "$key";
      return 0;
    fi
  done <<<"$(jq -r 'keys_unsorted | .[]' <"$VERSIONS_FILE")"
}

# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

# All 9.0+ tags, stable and pre-release. Alphas are skipped: they are never
# published as a distribution zip.
list_upstream_versions() {
  git ls-remote --tags --refs "$PS_GIT_REPO" \
    | cut -f2 | sed 's#refs/tags/##' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+(-(beta|rc)\.[0-9]+)?$' \
    | awk -F. '$1 >= 9' \
    | sort -V;
}

url_exists() {
  curl --silent --fail --head --location --max-time 20 --output /dev/null "$1";
}

# Resolves the distribution build number of a version by probing the asset URLs.
# Echoes "<zip_sources key> <url>" on success.
probe_zip_source() {
  local core=$1 pre=$2 lo hi build minor key url;
  lo=$(branch_max_build "$(echo "$core" | cut -d. -f1-2)");
  if [ -z "$lo" ]; then
    lo=$(global_max_build);
  fi
  hi=$(( $(global_max_build) + BUILD_LOOKAHEAD ));
  if [ "$hi" -lt "$(( lo + BUILD_LOOKAHEAD ))" ]; then
    hi=$(( lo + BUILD_LOOKAHEAD ));
  fi
  for (( build = lo; build <= hi; build++ )); do
    for (( minor = 0; minor <= BUILD_MINOR_LOOKAHEAD; minor++ )); do
      key="${core}-${build}.${minor}${pre}";
      url=$(zip_url "$key");
      if url_exists "$url"; then
        echo "$key $url";
        return 0;
      fi
    done
  done
  return 1;
}

# The PHP versions a PrestaShop version is tested against, read from its own CI
# matrix. Not available on branches older than 9.1.
fetch_upstream_php_versions() {
  local version=$1;
  curl --silent --fail --location --max-time 20 \
    "${PS_RAW_BASE}/${version}/.github/workflows/workflow-matrix/complete-php-versions.json" \
    | jq -r '.[]' | sort -V;
}

# ---------------------------------------------------------------------------
# prestashop-versions.json writers
#
# The file is edited as text rather than through jq: jq would reformat every
# single-line "compatible" array and bury the actual change in a huge diff.
# ---------------------------------------------------------------------------

# Appends an entry to the zip_sources map of an existing key.
insert_zip_source() {
  local key=$1 entry_key=$2 entry_url=$3 tmp;
  tmp=$(mktemp);
  if ! awk -v key="$key" -v ek="$entry_key" -v eu="$entry_url" '
    BEGIN { state = 0; prev = "" }
    state == 0 && $0 == "  \"" key "\": {" { state = 1; print; next }
    state == 1 && $0 ~ /^  \},?$/ { exit 1 }
    state == 1 && $0 == "    \"zip_sources\": {" { state = 2; print; next }
    state == 2 {
      if ($0 ~ /^    \},?$/) {
        if (prev != "") { sub(/,?$/, ",", prev); print prev }
        printf "      \"%s\": \"%s\"\n", ek, eu;
        print;
        state = 3;
        next;
      }
      if (prev != "") { print prev }
      prev = $0;
      next;
    }
    { print }
    END { if (state != 3) { exit 1 } }
  ' "$VERSIONS_FILE" >"$tmp"; then
    rm -f "$tmp";
    die "could not insert \"$entry_key\" into the zip_sources of \"$key\"";
  fi
  mv "$tmp" "$VERSIONS_FILE";
}

# Inserts a whole new version branch, right before the "nightly" key.
insert_version_branch() {
  local block=$1 tmp;
  tmp=$(mktemp);
  if ! awk -v block="$block" '
    $0 == "  \"nightly\": {" && !inserted { printf "%s", block; inserted = 1 }
    { print }
    END { if (!inserted) { exit 1 } }
  ' "$VERSIONS_FILE" >"$tmp"; then
    rm -f "$tmp";
    die "could not find the \"nightly\" key to insert the new version branch before";
  fi
  mv "$tmp" "$VERSIONS_FILE";
}

version_branch_block() {
  local key=$1 php_recommended=$2 php_compatible=$3 nodejs=$4 entry_key=$5 entry_url=$6;
  cat <<EOF
  "$key": {
    "php": {
      "recommended": "$php_recommended",
      "compatible": [$php_compatible]
    },
    "nodejs": {
      "recommended": "$nodejs"
    },
    "zip_sources": {
      "$entry_key": "$entry_url"
    }
  },
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

ADDED_VERSIONS=()
NEW_BRANCHES=()
MISSING_FLAVOURS=()

handle_new_version() {
  local version=$1;
  local core pre found key url branch_key;
  local php_list php_compatible php_display php_recommended php_source nodejs block php_version;

  core=${version%%-*};
  pre=${version#"$core"};

  log "-- $version: looking for a distribution zip";
  found=$(probe_zip_source "$core" "$pre") || found="";
  if [ -z "$found" ]; then
    log "   none published yet, skipping";
    return 0;
  fi
  read -r key url <<<"$found";
  log "   found $key";

  branch_key=$(matching_key "$version");
  if [ -n "$branch_key" ]; then
    insert_zip_source "$branch_key" "$key" "$url";
    ADDED_VERSIONS+=("$version|$key|$url|$branch_key");
    return 0;
  fi

  # New version branch: read the PHP versions from the upstream CI matrix, fall
  # back to the most recent known branch when that file does not exist yet.
  branch_key="^$(echo "$core" | cut -d. -f1-2)";
  php_list=$(fetch_upstream_php_versions "$version") || php_list="";
  if [ -n "$php_list" ]; then
    php_source="the upstream CI matrix of \`$version\`";
  else
    log "   no upstream PHP matrix, copying the previous version branch";
    php_source="the previous version branch (fallback)";
    php_list=$(jq -r '[to_entries[] | select(.key != "nightly") | .value.php.compatible] | last | .[]' <"$VERSIONS_FILE");
  fi
  php_recommended=$(echo "$php_list" | sort -V | tail -1);
  php_compatible=$(echo "$php_list" | sed 's/.*/"&"/' | paste -sd, - | sed 's/,/, /g');
  php_display=$(echo "$php_list" | paste -sd, - | sed 's/,/, /g');
  nodejs=$(jq -r '[to_entries[] | select(.key != "nightly") | select(.value.nodejs != null) | .value.nodejs.recommended] | last' <"$VERSIONS_FILE");

  log "   new version branch $branch_key (PHP $php_recommended, from $php_source)";
  block=$(version_branch_block "$branch_key" "$php_recommended" "$php_compatible" "$nodejs" "$key" "$url");
  insert_version_branch "$block
";
  ADDED_VERSIONS+=("$version|$key|$url|$branch_key");
  NEW_BRANCHES+=("$branch_key|$php_recommended|$php_display|$nodejs|$php_source");

  # A new branch may need a PHP version the image factory cannot build yet.
  while IFS= read -r php_version; do
    if ! jq -e --arg v "$php_version" 'has($v)' <"$FLAVOURS_FILE" >/dev/null; then
      MISSING_FLAVOURS+=("$php_version|$branch_key");
    fi
  done <<<"$php_list"
}

write_body() {
  local entry version key url branch_key php_recommended php_display nodejs php_source php_version;
  {
    echo "Automated update of \`$VERSIONS_FILE\`, every zip URL below returned a 200.";
    echo;
    echo "## New PrestaShop versions";
    echo;
    for entry in "${ADDED_VERSIONS[@]}"; do
      IFS='|' read -r version key url branch_key <<<"$entry";
      echo "- \`$version\` → \`$key\` under \`$branch_key\` ([zip]($url))";
    done
    if [ ${#NEW_BRANCHES[@]} -gt 0 ]; then
      echo;
      echo "## New version branches";
      echo;
      for entry in "${NEW_BRANCHES[@]}"; do
        IFS='|' read -r branch_key php_recommended php_display nodejs php_source <<<"$entry";
        echo "- \`$branch_key\`: recommended PHP \`$php_recommended\`, compatible \`$php_display\`, taken from $php_source.";
        echo "  NodeJS \`$nodejs\` was copied from the previous branch: **please check it manually**.";
      done
    fi
    if [ ${#MISSING_FLAVOURS[@]} -gt 0 ]; then
      echo;
      echo "## :warning: Missing PHP flavours";
      echo;
      for entry in "${MISSING_FLAVOURS[@]}"; do
        IFS='|' read -r php_version branch_key <<<"$entry";
        echo "- PHP \`$php_version\` is compatible with \`$branch_key\` but has no entry in \`$FLAVOURS_FILE\`. Builds using it will fail until one is added.";
      done
    fi
    echo;
    echo "Generated by \`find-new-prestashop-versions.sh\`.";
  } >"$BODY_FILE"
}

main() {
  local version core pre backup;

  [ -r "$VERSIONS_FILE" ] || die "$VERSIONS_FILE not found";
  [ -r "$FLAVOURS_FILE" ] || die "$FLAVOURS_FILE not found";

  backup=$(mktemp);
  cp "$VERSIONS_FILE" "$backup";

  log "Listing upstream PrestaShop versions...";
  while IFS= read -r version; do
    core=${version%%-*};
    pre=${version#"$core"};
    if is_known_version "$core" "$pre"; then
      continue;
    fi
    handle_new_version "$version";
  done <<<"$(list_upstream_versions)"

  if [ ${#ADDED_VERSIONS[@]} -eq 0 ]; then
    rm -f "$backup";
    log "No new PrestaShop version found.";
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
      echo "changed=false" >>"$GITHUB_OUTPUT";
    fi
    return 0;
  fi

  if ! jq empty <"$VERSIONS_FILE"; then
    mv "$backup" "$VERSIONS_FILE";
    die "the update produced an invalid $VERSIONS_FILE, changes reverted";
  fi

  write_body;
  log "";
  cat "$BODY_FILE" >&2;
  log "";

  if [ "$DRY_RUN" = "true" ]; then
    log "--dry-run: reverting $VERSIONS_FILE";
    mv "$backup" "$VERSIONS_FILE";
    return 0;
  fi

  rm -f "$backup";
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "changed=true" >>"$GITHUB_OUTPUT";
    echo "body_file=$BODY_FILE" >>"$GITHUB_OUTPUT";
  fi
}

main "$@"
