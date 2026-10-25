#!/bin/bash
set -eu

PS_FOLDER=${PS_FOLDER:?missing PS_FOLDER}
PS_VERSION=${1:?missing PS_VERSION}

add_polyfill_console () {
  mkdir -p "$PS_FOLDER/bin"
  touch "$PS_FOLDER/bin/console"
  mv /tmp/ps-console-polyfill.php "$PS_FOLDER/bin/console"
  chmod +x "$PS_FOLDER/bin/console"
}

patch_1_6 () {
  echo "✅ Add a robots file for PrestaShop 1.6"
  echo "User-agent: *" > "$PS_FOLDER/admin/robots.txt"
  echo "Disallow: /" >> "$PS_FOLDER/admin/robots.txt"
  add_polyfill_console
}

patch_1_7_6 () {
  echo "✅ Patch PrestaShop Faceted Search for version <= 1.7.6 and > 1.6"
  mkdir -p "$PS_FOLDER/var/cache/dev/sandbox"
  PS_FACETEDSEARCH_VERSION="v3.15.1"
  rm -rf "$PS_FOLDER/modules/ps_facetedsearch"
  curl -f -sL -o "/tmp/ps_facetedsearch.zip" "https://github.com/PrestaShop/ps_facetedsearch/releases/download/$PS_FACETEDSEARCH_VERSION/ps_facetedsearch.zip"
  # the archive holds the ps_facetedsearch/ folder itself
  unzip -n -q "/tmp/ps_facetedsearch.zip" -d "$PS_FOLDER/modules"
}

patch_other () {
  rm -f /tmp/ps-console-polyfill.php
}

# PrestaShop <= 1.7.6 downloads language flags from prestashop.com, which no longer answers.
# In dev mode (enabled by hydrate.sh) the download timeout aborts the installer:
# read the flag bundled in the installer instead (falls back to the "none" flag when missing)
patch_language_flag () {
  LANGUAGE_CLASS="$PS_FOLDER/classes/Language.php"
  if grep -q "prestashop.com/download/lang_packs/flags/jpeg/" "$LANGUAGE_CLASS"; then
    echo "✅ Read language flags from the installer instead of prestashop.com"
    sed -i -E "s#'http://www\.prestashop\.com/download/lang_packs/flags/jpeg/' *\. *\\\$iso_code *\. *'\.jpg'#_PS_ROOT_DIR_ . '/install/langs/' . \$iso_code . '/flag.jpg'#" "$LANGUAGE_CLASS"
    if grep -q "prestashop.com/download/lang_packs/flags/jpeg/" "$LANGUAGE_CLASS"; then
      echo "❌ Could not patch the language flag download in $LANGUAGE_CLASS" >&2
      exit 1
    fi
  fi
}

patch_language_flag

if echo "$PS_VERSION" | grep "^1.6" > /dev/null; then
  patch_1_6;
elif echo "$PS_VERSION" | grep "^1.7.6" > /dev/null; then
  patch_1_7_6;
else
  patch_other;
fi