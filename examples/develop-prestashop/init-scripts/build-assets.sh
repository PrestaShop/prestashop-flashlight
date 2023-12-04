#!/bin/sh
set -eu

echo "* Build PrestaShop assets..."
make assets
echo "* Assets built!"
