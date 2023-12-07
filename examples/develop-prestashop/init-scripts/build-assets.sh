#!/bin/sh
set -eu

echo "* Build PrestaShop assets..."
make composer
make assets
echo "* Assets built!"
