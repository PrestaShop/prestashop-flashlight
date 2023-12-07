#!/bin/bash
set -eu

PS_FOLDER=${PS_FOLDER:?missing PS_FOLDER}
PS_VERSION=$(awk 'NR==1{print $2}' "$PS_FOLDER/VERSION")
PS_OPT_DIR=/var/opt/prestashop

patch_1_6 () {
  # Add robots file
  echo "User-agent: *" > "$PS_FOLDER/admin-dev/robots.txt"
  echo "Disallow: /" >> "$PS_FOLDER/admin-dev/robots.txt"

  # Protect our settings against a volume mount on $PS_FOLDER
  mkdir -p "$PS_OPT_DIR"
  cp "$PS_FOLDER/config/settings.inc.php" "$PS_OPT_DIR/settings.inc.php"
}

patch_other () {
  # Protect our settings against a volume mount on $PS_FOLDER
  mkdir -p "$PS_OPT_DIR"
  cp "$PS_FOLDER/app/config/parameters.php" "$PS_OPT_DIR/parameters.php"
}

if echo "$PS_VERSION" | grep "^1.6" > /dev/null; then
  patch_1_6;
else
  patch_other;
fi