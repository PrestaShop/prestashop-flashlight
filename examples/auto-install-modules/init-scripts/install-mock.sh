#!/bin/sh
#
# This is an init-script for prestashop-flashlight.
#
# It will dynamically download, unzip and install a third-party module.
# Please note: storing a folder in /var/www/html/modules does not register
# the module into PrestaShop yet. This is why we call the console CLI.
#
set -eu

run_user () {
  sudo -g www-data -u www-data -- "$@"
}

ps_accounts_mock_install() {
  echo "* [ps_accounts_mock] downloading..."
  wget -q -O /tmp/ps_accounts.zip "https://github.com/PrestaShopCorp/ps_accounts_mock/releases/download/v1.0.0/ps_accounts.zip"
  echo "* [ps_accounts_mock] unziping..."
  run_user unzip -qq /tmp/ps_accounts.zip -d /var/www/html/modules
  echo "* [ps_accounts_mock] installing the module..."
  cd "$PS_FOLDER"
  run_user php -d memory_limit=-1 bin/console prestashop:module --no-interaction install "ps_accounts"
}

ps_accounts_mock_install
