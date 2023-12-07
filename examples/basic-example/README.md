# Example: basic example

This example runs the latest PrestaShop Flashlight available image, which is based on the latest upstream release of PrestaShop.

## Test the example

The expected output of this example is:

```sh
docker compose up prestashop
[+] Building 0.0s (0/0)                                                                docker-container:thirsty_khorana
[+] Running 3/3
 ✔ Network basic-example_default         Created            0.0s
 ✔ Container basic-example-mysql-1       Created            0.1s
 ✔ Container basic-example-prestashop-1  Created            0.1s
Attaching to basic-example-prestashop-1
basic-example-prestashop-1  | * Applying PS_DOMAIN (localhost:8000) to the dump...
basic-example-prestashop-1  | * Checking MySQL connectivity...
basic-example-prestashop-1  | * PHP PDO connectivity checked
basic-example-prestashop-1  | * PrestaShop MySQL client configuration set
basic-example-prestashop-1  | * Restoring MySQL dump...
basic-example-prestashop-1  | * MySQL dump restored!
basic-example-prestashop-1  | * No init script(s) found
basic-example-prestashop-1  | * Starting php-fpm...
basic-example-prestashop-1  | * Starting nginx...
basic-example-prestashop-1  | * Nginx started
basic-example-prestashop-1  | * No post script(s) found
```

You can access to PrestaShop in your browser:

- http://localhost:8000
- http://localhost:8000/admin-dev/ (back office, login/password described [here](../../README.md))

## Same with phpMyAdmin

If you want to start a phpMyAdmin tool, this can be done easily like so:

```sh
docker compose up # or "docker compose up prestashop php-my-admin"
```

Now you can access to phpMyAdmin here: http://localhost:6060
