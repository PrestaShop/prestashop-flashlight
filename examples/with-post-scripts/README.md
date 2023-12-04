# Example: with post scripts

This is an example of a running PrestaShop Flashlight with custom post scripts.
See [./post-scripts](./post-scripts).

**⚠️ Note:** your post-scripts **MUST** be executable, and have a [shebang](<https://en.wikipedia.org/wiki/Shebang_(Unix)>) to be run by flashlight at startup. Otherwise they would be ignored.

## Test the example

The expected output of this example is:

```sh
docker compose up prestashop
[+] Building 0.0s (0/0)
[+] Running 2/2
 ✔ Container with-post-scripts-mysql-1       Running                                                                                                                                                                                                           0.0s
 ✔ Container with-post-scripts-prestashop-1  Recreated                                                                                                                                                                                                         0.7s
Attaching to with-post-scripts-prestashop-1
with-post-scripts-prestashop-1  | * Applying PS_DOMAIN (localhost:8000) to the dump...
with-post-scripts-prestashop-1  | * Checking MySQL connectivity...
with-post-scripts-prestashop-1  | * PHP PDO connectivity checked
with-post-scripts-prestashop-1  | * PrestaShop MySQL client configuration set
with-post-scripts-prestashop-1  | * Restoring MySQL dump...
with-post-scripts-prestashop-1  | * MySQL dump restored!
with-post-scripts-prestashop-1  | * No init script(s) found
with-post-scripts-prestashop-1  | * Starting php-fpm...
with-post-scripts-prestashop-1  | * Starting nginx...
with-post-scripts-prestashop-1  | * Nginx started
with-post-scripts-prestashop-1  | * Running post script(s)...
with-post-scripts-prestashop-1  |   --> Running /tmp/post-scripts/01-test.sh...
with-post-scripts-prestashop-1  |   * 01-test here
with-post-scripts-prestashop-1  |   Writing CUSTOM_GALETTE to /tmp/check-me
with-post-scripts-prestashop-1  |
with-post-scripts-prestashop-1  |   --> Running /tmp/post-scripts/02-test-seq.sh...
with-post-scripts-prestashop-1  |   * 02-test-seq here
with-post-scripts-prestashop-1  |   sequential script test succeeded
with-post-scripts-prestashop-1  |
with-post-scripts-prestashop-1  |   --> Running /tmp/post-scripts/03-mysql-test.sh...
with-post-scripts-prestashop-1  |   * 03-mysql-test here
with-post-scripts-prestashop-1  |   All checks passed!
with-post-scripts-prestashop-1  |
```
