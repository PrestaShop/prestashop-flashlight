# Example: nightly example

This example runs the latest nightly image of PrestaShop Flashlight, which is based on the latest nightly of PrestaShop.
There might be bugs in a nightly, be cautious when using this image in your CI/CD toolchain.

## Test this example

The expected output of this example is:

```sh
docker compose up prestashop --force-recreate
[+] Running 3/2
 ✔ Network flashlight-nightly-example_default         Created              0.1s
 ✔ Container flashlight-nightly-example-mysql-1       Created              0.2s
 ✔ Container flashlight-nightly-example-prestashop-1  Created              0.0s
Attaching to prestashop-1
prestashop-1  | * Applying PS_DOMAIN (localhost:8000) to the dump...
prestashop-1  | * Checking MySQL connectivity...
prestashop-1  | * PHP PDO connectivity checked
prestashop-1  | * Editing PrestaShop configuration...
prestashop-1  | * PrestaShop MySQL configuration set
prestashop-1  | * Restoring MySQL dump...
prestashop-1  | * MySQL dump restored!
prestashop-1  | * No init-script(s) found
prestashop-1  | * Starting php-fpm...
prestashop-1  | * Starting nginx...
prestashop-1  | * Nginx started
prestashop-1  | * No post-script(s) found
```

You can access to PrestaShop in your browser:

- http://localhost:8000
- http://localhost:8000/admin-dev/ (back office, login/password described [here](../../README.md))

## Running phpMyAdmin

If you want to start a phpMyAdmin instance, it can be done easily like so:

```sh
docker compose up
# or "docker compose up prestashop php-my-admin"
```

You can now access phpMyAdmin at http://localhost:6060
