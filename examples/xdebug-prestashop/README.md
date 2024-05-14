# XDEBUG PrestaShop

You found a bug in PrestaShop? Want to track down a weird behavior? XDEBUG can help you, even within a docker environment. Here is an example to showcase the integration of this tool with PrestaShop Flashlight.

# Requirements

To enable XDEBUG capabilities within your favorite IDE, you have to mount the PrestaShop sources from your local host to the target PrestaShop Flashlight docker container.

```sh
CONTAINER_NAME=flashlight-nightly
PS_FLASHLIGHT_TAG=nightly
docker create --name "$CONTAINER_NAME" "prestashop/prestashop-flashlight:$PS_FLASHLIGHT_TAG"
docker cp "$CONTAINER_NAME:/var/www/html" ./PrestaShop
docker rm "$CONTAINER_NAME"
```

Now you will have the exact copy of the `PS_FLASHLIGHT_TAG` prestashop source code copied locally.
You are now all set to start PrestaShop Flashlight with your local source binding:

```
docker compose up prestashop
```

# Usage

@TODO: describe here some IDE configurations

# External ressources

- xdebug with VSCode: https://marketplace.visualstudio.com/items?itemName=xdebug.php-debug
- xdebug with PHPStorm: https://www.jetbrains.com/help/phpstorm/configuring-xdebug.html

# Note
When both enabled, xdebug and blackfire can cause php-fpm to log a "Connection reset by peer" error that ends up in displaying a 502 bad gateway message.
To be able to use xdebug, one temporary solution can be to disable blackfire with BLACKFIRE_ENABLED=false