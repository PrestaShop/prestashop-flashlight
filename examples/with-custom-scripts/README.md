# Example: with custom scripts

This is an example of a running PrestaShop Flashlight with custom scripts.
See [./init-scripts](./init-scripts).

## Test the example

The expected output of this example is:

```
docker-compose up prestashop
[+] Building 0.0s (0/0)                                                                                                                                                                                     docker:desktop-linux
[+] Running 3/2
 ✔ Network with-custom-scripts_default         Created                              0.0s
 ✔ Container with-custom-scripts-mysql-1       Created                              0.0s
 ✔ Container with-custom-scripts-prestashop-1  Created                              0.0s
Attaching to with-custom-scripts-prestashop-1
with-custom-scripts-prestashop-1  | * Applying PS_DOMAIN (localhost:8000) to the dump...
with-custom-scripts-prestashop-1  | * Checking MySQL connectivity...
with-custom-scripts-prestashop-1  | * PHP PDO connectivity checked
with-custom-scripts-prestashop-1  | * PrestaShop MySQL client configuration set
with-custom-scripts-prestashop-1  | * Restoring MySQL dump...
with-custom-scripts-prestashop-1  | * MySQL dump restored!
with-custom-scripts-prestashop-1  | * Running init script(s)...
with-custom-scripts-prestashop-1  |   --> Running /tmp/init-scripts/01-bretzel.sh...
with-custom-scripts-prestashop-1  |   * 🥨 01 bretzel here
with-custom-scripts-prestashop-1  |   CUSTOM_FOO contains bar
with-custom-scripts-prestashop-1  |
with-custom-scripts-prestashop-1  |   --> Running /tmp/init-scripts/02-tarte-flambee.sh...
with-custom-scripts-prestashop-1  |   * 🍕 02 tarte flambée here
with-custom-scripts-prestashop-1  |   CUSTOM_MUSH contains room
with-custom-scripts-prestashop-1  |
with-custom-scripts-prestashop-1  | * Starting php-fpm...
with-custom-scripts-prestashop-1  | * Starting nginx...
```
