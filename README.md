![PrestaShop Flashlight logo](./assets/prestashop_flashlight_logo.png)

Spin a Prestashop testing instance in seconds!

PrestaShop FlashLight is fast: the installation process with default content for a PrestaShop is tackled at build time, compiling the result to a single database dump.

Supported architectures:

- linux/amd64 (akka `x86_64`)
- linux/arm64/v8 (akka `arm64`)

At runtime the dump is tweaked and consumed, providing a fast instance bootstrap.

> **⚠️ Disclaimer**: the following tool is provided in the sole purpose of bootstraping a PrestaShop testing environment. <br>If you look for a production grade image, please refer to https://github.com/PrestaShop/docker.

> **Note**: no MySQL server is shipped in the resulting image, you have to provide your own instance for the backup to be dumped during the first connection.

## Where do I find pre-built images?

Here: https://hub.docker.com/r/prestashop/prestashop-flashlight

## Use

Start the environment

```sh
cp .env.dist .env
edit .env
docker compose up
```

Add init scripts

```yaml
services:
  prestashop:
    image: prestashop/prestashop-flashlight:8.1.0-8.1
    volumes:
      - ./init-scripts:/tmp/init-scripts:ro
```

## Build

Requirements:

- [jq](https://jqlang.github.io/jq/)

To build the latest PrestaShop version, simply:

```sh
./build.sh
```

For a custom multiplatform build & push:

```sh
PS_VERSION=8.1.0 \
PLATFORM=linux/amd64,linux/arm64 \
PUSH=true \
TARGET_IMAGE=my-own-repo/testing:latest \
./build.sh
```

The `OS_FLAVOUR` defaults to `alpine` (see [Alpine Linux](https://www.alpinelinux.org/)) and `SERVER_FLAVOUR` to `nginx` (see [Nginx](https://www.nginx.com/)).

For more documentation about available build variables, please see [./build.sh](./build.sh).

## Container environment variables

- **`PS_DOMAIN`**
  - Description: the public domain (and port) to reach your PrestaShop instance
  - Mandatory if you do not use `NGROK_TUNNEL_AUTO_DETECT`
  - Example: `localhost:8000`
- **`NGROK_TUNNEL_AUTO_DETECT`**
  - Description: the ngrok agent base API url, to guess the tunnel domain of your shop
  - Mandatory if you do not use `PS_DOMAIN`
  - Example: `http://ngrok:4040`
- **`SSL_REDIRECT`**
  - If set to `true` PrestaShop will be told to redirect all inbound traffic to https://$PS_DOMAIN
  - Default to `false` (or automatically guessed if using NGROK_TUNNEL_AUTO_DETECT)
- **`DEBUG_MODE`**
  - If set to `true` the Debug mode will be enabled on PrestaShop
  - Default to `false`
- **`INSTALL_MODULES_DIR`**
  - A module directory containing zips to be installed with the PrestaShop CLI
  - Example: `/ps-modules`
- **`INIT_ON_RESTART`**
  - If set to `true` the PS_DOMAIN auto search and dump fix will be replayed on container restart
  - Default to `false`
- **`DUMP_ON_RESTART`**
  - If set to `true` the dump restoration replayed on container restart
  - Default to `false`
- **`INSTALL_MODULES_ON_RESTART`**
  - If set to `true` zip modules will be reinstalled on container restart
  - Default to `false`
- **`INIT_SCRIPTS_ON_RESTART`**
  - If set to `true` custom init scripts will be replayed on container restart
  - Default to `false`
- **`ON_INIT_SCRIPT_FAILURE`**
  - If set to `continue`, PrestaShop Flashlight will continue the boot process even if an init script failed
  - Default to `fail`

## Maintaining

Requirements:

- [shellcheck](https://github.com/koalaman/shellcheck)
- [hadolint](https://github.com/hadolint/hadolint)

```sh
# Lint bash scripts
find . -type f \( -name '*.sh' \) | xargs shellcheck -x -s bash;

# Lint docker files
HADOLINT_IGNORE=DL3006,DL3018 find . -type f \( -name '*.Dockerfile' \) | xargs hadolint;
```

## Api calls within a docker network

**Disclaimer**: PrestaShop is sensitive to the `Host` header of your client, and can behave surprisingly. In fact, since the Multi-shop feature is available, you cannot just call any front controller from any endpoint, unless... You set the ` Host` or the `id_shop` you are targeting.

Let's explain this subtle - rather mandatory - knowledge:

Assume you have a module installed and working properly, and your PS_DOMAIN configured on `http://localhost:8000`

```sh
> docker compose up -d
> curl -i 'http://localhost:8000/index.php?fc=module&module=mymodule&controller=myctrl'
HTTP/1.1 200 OK
some happy content here ...
```

Is working as expected. But what about the same request performed within the docker container?

```sh
> docker exec -t prestashop curl -i 'http://localhost:8000/index.php?fc=module&module=mymodule&controller=myctrl'
curl: (7) Failed to connect to localhost port 32000 after 5 ms: Couldn't connect to server
```

Indeed, this **WON'T WORK**, the container port is 80, only the host know about 8000 in our use case. Let's talk to it:

```sh
> docker exec -t prestashop curl -i 'http://localhost/index.php?fc=module&module=mymodule&controller=myctrl'
HTTP/1.1 302 Found
Server: nginx/1.24.0
Date: Tue, 22 Aug 2023 08:53:22 GMT
Content-Type: text/html; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
X-Powered-By: PHP/8.1.22
Location: http://localhost:8000/
```

Damn! Do you know what's happening? PrestaShop cannot know which shop of its multi-shop configuration you are trying to talk to. Event with one shop, this won't be selected by default and fail with a redirect which cannot be resolved within our network configuration.

If you definitely know the Shop ID you are targeting, you can do this with success:

```sh
curl -i -H  'http://localhost:80/index.php?id_shop=1&fc=module&module=mymodule&controller=myctrl'
HTTP/1.1 200 OK
some happy content here ...
```

but the best way to perform this is to set the target `Host` in a header field:

```sh
curl -i -H 'Host: localhost:8000' 'http://localhost:80/index.php?fc=module&module=mymodule&controller=myctrl'
HTTP/1.1 302 Found
Server: nginx/1.24.0
Date: Tue, 22 Aug 2023 08:53:22 GMT
Content-Type: text/html; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
X-Powered-By: PHP/8.1.22
Location: http://localhost:8000/
```

or even better if you use a Nginx reverse-proxy to forward requests to prestashop within the internal docker network:

```nginx
# so you can call "http://localhost:3000/prestashop/index.php" to reach your PrestaShop id_shop 1 with success
server {
  location /prestashop {
      resolver 127.0.0.11 ipv6=off valid=10s;
      resolver_timeout 10s;
      proxy_set_header Host "localhost:8000";
      rewrite /prestashop/?(.*) /$1 break;
      set $frontend "http://prestashop:80";
      proxy_pass $frontend;
  }
}
```

## Credits

- https://github.com/PrestaShop/PrestaShop
- https://github.com/PrestaShop/performance-project
- https://github.com/jokesterfr/docker-prestashop
