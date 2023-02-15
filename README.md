![PrestaShop Flashlight logo](./assets/prestashop_flashlight_logo.png)

Spin a Prestashop testing instance in seconds!

> **⚠️ Disclaimer**: the following tool is provided in the solely purpose of bootstraping a PrestaShop test environment. <br>If you look for a production grade image, please refer to https://github.com/PrestaShop/docker.

> **Note**: no MySQL server is shipped in the resulting image, you will need to provide your own. The docker-bolt-testing image will restore its internal MySQL dump to this server once firstly connected.

## How to build

```sh
PS_VERSION=8.0.1 ./build.sh
```

## Credits

- https://github.com/PrestaShop/PrestaShop
- https://github.com/PrestaShop/performance-project
- https://github.com/jokesterfr/docker-prestashop
