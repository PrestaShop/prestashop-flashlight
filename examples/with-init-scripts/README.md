# Example: with init scripts

This is an example of a running PrestaShop Flashlight with custom init scripts.
See [./init-scripts](./init-scripts).

**⚠️ Note:** your init-scripts **MUST** be executable, and have a [shebang](<https://en.wikipedia.org/wiki/Shebang_(Unix)>) to be run by flashlight at startup. Otherwise, they would be ignored.

## Test the example

The expected output of this example is:

```sh
docker compose up prestashop --force-recreate
[+] Building 0.0s (0/0)
[+] Running 3/2
 ✔ Network with-init-scripts_default         Created                                                                                                                                                                                                           0.0s
 ✔ Container with-init-scripts-mysql-1       Created                                                                                                                                                                                                           0.0s
 ✔ Container with-init-scripts-prestashop-1  Created                                                                                                                                                                                                           0.1s
Attaching to with-init-scripts-prestashop-1
with-init-scripts-prestashop-1  | * Applying PS_DOMAIN (localhost:8000) to the dump...
with-init-scripts-prestashop-1  | * Checking MySQL connectivity...
with-init-scripts-prestashop-1  | * PHP PDO connectivity checked
with-init-scripts-prestashop-1  | * PrestaShop MySQL client configuration set
with-init-scripts-prestashop-1  | * Restoring MySQL dump...
with-init-scripts-prestashop-1  | * MySQL dump restored!
with-init-scripts-prestashop-1  | * Running init script(s)...
with-init-scripts-prestashop-1  |   --> Running /tmp/init-scripts/01-bretzel.sh...
with-init-scripts-prestashop-1  |   * 🥨 01 bretzel here
with-init-scripts-prestashop-1  |   CUSTOM_FOO contains bar
with-init-scripts-prestashop-1  |
with-init-scripts-prestashop-1  |   --> Running /tmp/init-scripts/02-tarte-flambee.sh...
with-init-scripts-prestashop-1  |   * 🍕 02 tarte flambée here
with-init-scripts-prestashop-1  |   CUSTOM_MUSH contains room
with-init-scripts-prestashop-1  |
with-init-scripts-prestashop-1  | * Starting php-fpm...
with-init-scripts-prestashop-1  | * Starting nginx...
with-init-scripts-prestashop-1  | * Nginx started
with-init-scripts-prestashop-1  | * No post script(s) found
```
