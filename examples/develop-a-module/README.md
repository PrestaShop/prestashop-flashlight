# Example: develop a module

This example demonstrates how a local module can be mounted in your PrestaShop Flashlight instance for development purposes.

## Bind a local module to your instance in your manifest

Let's consider we have a `testmodule` PrestaShop Module. 

Create a `modules/` directory, and drop in your `testmodule` directory.

Create a bind mount in your docker-compose.yml:

```yaml
...
  prestashop:
    container_name: prestashop
    ...
    volumes:
      - type: bind
        source: ./modules/testmodule # local path to the module
        target: /var/www/html/modules/testmodule # path to be mounted in the container
...
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