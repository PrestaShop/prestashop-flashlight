![PrestaShop Flashlight logo](./assets/prestashop_flashlight_logo.png)

Spin a Prestashop testing instance in seconds!

> **⚠️ Disclaimer**: the following tool is provided in the solely purpose of bootstraping a PrestaShop testing environment. <br>If you look for a production grade image, please refer to https://github.com/PrestaShop/docker.

> **Note**: no MySQL server is shipped in the resulting image, you have to provide your own instance for the backup to be dumped during the first connection.

Compatible with these architecture:

- linux/amd64 (akka `x86_64`)
- linux/arm64/v8 (akka `arm64`)

The resulting image is based on this tech stack:

- An [Alpine](https://alpine-linux.org) linux image
- An [Nginx](https://nginx.com) server

## How fast is it?

On a Mac M1 computer:
xxxx
xxx
xxx

VS the official image with AUTO_INSTALL=1:

On a Mac M1 computer:
xxxx
xxx
xxx

## Where do I find pre-built images?

Here: https://hub.docker.com/r/prestashop/flashlight

## Build

```sh
PS_VERSION=8.0.1 ./build.sh
```

## Use

Start the environment

```sh
cp .env.dist .env
edit .env
docker compose up
```

Run your tests

```sh
cd ./test-examples
pnpm i
pnpm test
```

## Credits

- https://github.com/PrestaShop/PrestaShop
- https://github.com/PrestaShop/performance-project
- https://github.com/jokesterfr/docker-prestashop
