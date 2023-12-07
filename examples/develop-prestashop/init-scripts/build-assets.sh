#!/bin/sh
set -eu

echo "* Download composer dependencies..."
make composer

echo "* Build PrestaShop assets..."
# Disclaimer: it seems that the PrestaShop front-end assets currently require
#   to install Node.js dependencies globally. This is a bad pattern, which would
#   require this script to be run as root.
#
# As an alternative, we propose this NPM_PREFIX_DIR hack suggestion, which could
# eventually help to avoid running init-scripts as root in the future
#
NPM_PREFIX_DIR=/tmp/npm
mkdir -p $NPM_PREFIX_DIR
npm prefix -g $NPM_PREFIX_DIR
export PATH="$PATH:$NPM_PREFIX_DIR/bin"
make assets

echo "✅ Assets built!"
