#!/bin/bash
set -eu

PS_FOLDER=${PS_FOLDER:?missing PS_FOLDER}
PS_VERSION=$(awk 'NR==1{print $2}' "$PS_FOLDER/VERSION")
DUMP_FILE=/dump.sql

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
  # fixing logs flooded by "mcrypt_decrypt() is deprecated"
  sed -i -e "s~'PS_CIPHER_ALGORITHM','1'~'PS_CIPHER_ALGORITHM','0'~" "$DUMP_FILE"
}

patch_1_7_6 () {
  echo "✅ Patch PrestaShop Faceted Search for version <= 1.7.6 and > 1.6"
  mkdir -p "$PS_FOLDER/var/cache/dev/sandbox"
  PS_FACETEDSEARCH_VERSION="v3.15.1"
  rm -rf "$PS_FOLDER/modules/ps_facetedsearch"
  curl -f -sL -o "/tmp/ps_facetedsearch.zip" "https://github.com/PrestaShop/ps_facetedsearch/releases/download/$PS_FACETEDSEARCH_VERSION/ps_facetedsearch.zip"
  unzip -n -q "/tmp/ps_facetedsearch.zip" -d "$PS_FOLDER/modules/ps_facetedsearch"
}

patch_other () {
  rm -f /tmp/ps-console-polyfill.php
}

if echo "$PS_VERSION" | grep "^1.6" > /dev/null; then
  patch_1_6;
elif echo "$PS_VERSION" | grep "^1.7.6" > /dev/null; then
  patch_1_7_6;
else
  patch_other;
fi