# Example: nightly example

This example runs the latest nightly image of PrestaShop Flashlight, which is based on the latest nightly of PrestaShop. There might be bugs in a nightly, be cautious when using this image in your CI/CD toolchain.

## Test this example

The expected output of this example is:

```sh
docker compose up prestashop --force-recreate
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
