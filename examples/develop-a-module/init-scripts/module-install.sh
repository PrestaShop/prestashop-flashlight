#!/bin/sh
#
# This is an init-script for prestashop-flashlight.
#
# Storing a folder in /var/www/html/modules is not enough to register the module
# into PrestaShop, hence why we have to call the console install CLI.
#
set -eu

cd "$PS_FOLDER"
echo "* [testmodule] installing the module..."
php -d memory_limit=-1 bin/console prestashop:module --no-interaction install "testmodule"
