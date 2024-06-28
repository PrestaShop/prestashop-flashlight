#!/bin/bash
set -eu

PS_FOLDER=${PS_FOLDER:?missing PS_FOLDER}
PS_VERSION=$(awk 'NR==1{print $2}' "$PS_FOLDER/VERSION")

add_console () {
  mkdir -p "$PS_FOLDER/bin"
  touch "$PS_FOLDER/bin/console"
cat <<EOF > "$PS_FOLDER/bin/console"
<?php
if (!defined('_PS_ADMIN_DIR_')) { define('_PS_ADMIN_DIR_', '/admin-dev'); }
if (!defined('_PS_MODE_DEV_')) { define('_PS_MODE_DEV_', true); }
\$rootDirectory = getenv('_PS_ROOT_DIR_') ?: '/var/www/html';
require_once \$rootDirectory . '/config/config.inc.php';
function getModuleName(\$args) {
  for (\$i = 0; \$i < count(\$args); \$i++) {
    if (\$args[\$i] === 'install') {
      if (isset(\$args[\$i + 1])) {
        return \$args[\$i + 1];
      }
    }
  }
  throw new Exception('Module name not found');
}
\$moduleName = getModuleName(\$argv);
if (version_compare(_PS_VERSION_, '1.7', '>=')) {
  global \$kernel;
  if(!\$kernel){
    require_once _PS_ROOT_DIR_.'/app/AppKernel.php';
    \$kernel = new \AppKernel('dev', true);
    \$kernel->boot();
  }
}
\$module = Module::getInstanceByName(\$moduleName);
\$module->install();
EOF
  chmod +x "$PS_FOLDER/bin/console"
}

patch_1_6 () {
  echo "✅ Add a robots file for PrestaShop 1.6"
  echo "User-agent: *" > "$PS_FOLDER/admin/robots.txt"
  echo "Disallow: /" >> "$PS_FOLDER/admin/robots.txt"
  add_console
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
  cat /dev/null # Nothing to do
}

if echo "$PS_VERSION" | grep "^1.6" > /dev/null; then
  patch_1_6;
elif echo "$PS_VERSION" | grep "^1.7.6" > /dev/null; then
  patch_1_7_6;
else
  patch_other;
fi