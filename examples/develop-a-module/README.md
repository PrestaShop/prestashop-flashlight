# Example: develop a module

This example demonstrates how a local module can be mounted in your PrestaShop Flashlight instance for development purposes.

## Bind a local module to your instance in your manifest

Install the module's dependencies:

```
cd ./modules/testmodule
composer install
```

Run flashlight with a RW bind mount (see ./docker-compose.yml)

```
docker compose up prestashop --force-recreate
```

And that's it: your module is available on the `prestashop` Docker container, and changes made in the local directory of the module are automatically synchronized on the `prestashop` Docker container.

## Install / test the module

You can access to PrestaShop in your browser:

- http://localhost:8000
- http://localhost:8000/admin-dev/ (back office, login/password described [here](../../README.md))

You can go to modules > install and install your module, or install it with cli:

1. obtain container name:

```sh
docker ps
```

2. execute the install module command in the container:

```sh
docker exec -ti container_name php /var/www/html/bin/console prestashop:module install testmodule
```
