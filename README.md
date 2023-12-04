![PrestaShop Flashlight logo](./assets/prestashop_flashlight_logo.png)

Spin a Prestashop testing instance in seconds!

PrestaShop Flashlight is fast: the PrestaShop installation process is tackled at build time, compiling the result to a single database dump. You will get all the content (catalog, orders...) of the usual PrestaShop development seed.

Supported architectures:

- linux/amd64 (akka `x86_64`)
- linux/arm64/v8 (akka `arm64`)

> **⚡ Disclaimer**: this tool is provided in the unique purpose of bootstraping a development or testing environment. <br>If you look for a production grade image, please refer to https://github.com/PrestaShop/docker.

# How to get PrestaShop Flashlight?

This project can [be locally built](#build) anytime, but it is easier to use our pre-built Docker image available on the [Docker Hub](https://hub.docker.com/r/prestashop/prestashop-flashlight).

You may browse a wide variety of tags, some of them being:

- `latest`
- `nightly` (coming soon)
- `1.7.8.10` if you want PrestaShop 1.7.8.10 with its recommended PHP version and tools
- `1.7.8.10-debian` same as above, but shipped with Debian Linux (_Alpine Linux_ is the default)
- `1.7.8.10-7.4` PrestaShop version 1.7.8.10 with PHP 7.4 and Alpine Linux
- `php-8.1` to get the latest PrestaShop version recommending PHP 8.1

Some tags may not be built yet, feel free to [fill an issue](./issues) to request it.

# Use

PrestaShop Flashlight can be used as a development environment, a CI/CD asset to build up a custom PrestaShop environment... Or any use case you can think of. Hence a list of useful ressources and examples to get you started:

- [Develop PrestaShop](./examples/develop-prestashop/)
- [Develop a PrestaShop Module](./examples/develop-a-module/)
- [Custom init-scripts](./examples/with-init-scripts/)
- [Custom post-scripts](./examples/with-post-scripts/)
- [Auto installation of modules](./examples/auto-install-modules/)
- Develop a PrestaShop Theme (coming soon)
- Use in a Github Action (coming soon)

PrestaShop Flashlight embeds `nginx` and `php-fpm`, however the `MySQL` server has to be provided separately. This is not a big deal if you give a close look to the _docker-compose.yml_ examples provided!

## Compatibility

PrestaShop Flashlight is based on the official compatibility charts:

- PrestaShop 1.6-1.7.x [PHP compatiblity chart](https://devdocs.prestashop-project.org/1.7/basics/installation/system-requirements/#php-compatibility-chart)
- PrestaShop 8.x [PHP compatiblity chart](https://devdocs.prestashop-project.org/8/basics/installation/system-requirements/#php-compatibility-chart)

You can check this implementation anytime in [prestashop-version.json](./prestashop-version.json).

## Environment variables

| Variable                   | Description                                                                                              | Required                                    | Default value                         |
| -------------------------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------- | ------------------------------------- |
| PS_DOMAIN                  | the public domain (and port) to reach your PrestaShop instance                                           | yes, unles using `NGROK_TUNNEL_AUTO_DETECT` | N/A (example: `localhost:8000`)       |
| NGROK_TUNNEL_AUTO_DETECT   | the ngrok agent base API url, to guess the tunnel domain of your shop                                    | yes, unless using `PS_DOMAIN`               | N/A (example `http://ngrok:4040`)     |
| SSL_REDIRECT               | if enabled and using PS_DOMAIN, PrestaShop will redirect all inbound traffic to `https://$PS_DOMAIN`     | no                                          | `false` (example: `true`)             |
| DEBUG_MODE                 | if enabled the Debug mode will be enabled on PrestaShop                                                  | no                                          | `false`                               |
| INSTALL_MODULES_DIR        | module directory containing zips to be installed with the PrestaShop CLI                                 | no                                          | empty string (example: `/ps-modules`) |
| INIT_SCRIPTS_DIR           | script directory with executable files to be run prior to PrestaShop startup                             | no                                          | `/tmp/init-scripts`                   |
| POST_SCRIPTS_DIR           | script directory with executable files to be run after the PrestaShop startup                            | no                                          | `/tmp/post-scripts`                   |
| INIT_ON_RESTART            | if enabled the PS_DOMAIN auto search and dump fix will be replayed on container restart                  | no                                          | `false`                               |
| DUMP_ON_RESTART            | if enabled the dump restoration replayed on container restart                                            | no                                          | `false`                               |
| INSTALL_MODULES_ON_RESTART | if enabled zip modules will be reinstalled on container restart                                          | no                                          | `false`                               |
| INIT_SCRIPTS_ON_RESTART    | if enabled custom init scripts will be replayed on container restart                                     | no                                          | `false`                               |
| POST_SCRIPTS_ON_RESTART    | if enabled custom post scripts will be replayed on container restart                                     | no                                          | `false`                               |
| ON_INIT_SCRIPT_FAILURE     | if set to `continue`, PrestaShop Flashlight will continue the boot process even if an init script failed | no                                          | `fail`                                |
| ON_POST_SCRIPT_FAILURE     | if set to `continue`, PrestaShop Flashlight won't exit in case of script failure                         | no                                          | `fail`                                |
| ON_INSTALL_MODULES_FAILURE | if set to `continue`, module installation failure will not block the init process                        | no                                          | `fail`                                |
| DRY_RUN                    | if enabled, the run.sh script will exit without really starting a web server                             | no                                          | `false`                               |

## Back office access information

The default url/credentials to access to PrestaShop's back office defined in `./assets/hydrate.sh` and are set to:

| Url      | {PS_DOMAIN}/admin-dev |
| -------- | --------------------- |
| Login    | admin@prestashop.com  |
| Password | prestashop            |

## Exit codes

On error, PrestaShop Flashlight can quit with these exit codes:

| Exit Code | Description                                                                      |
| --------- | -------------------------------------------------------------------------------- |
| 0         | graceful exit, probably running dry mode or after a SIGKILL                      |
| 1         | reserved for nginx                                                               |
| 2         | Missing $PS_DOMAIN or $NGROK_TUNNEL_AUTO_DETECT                                  |
| 3         | Ngrok domain cannot be guessed                                                   |
| 4         | Cannot find PrestaShop configuration file in $PS_FOLDER                          |
| 5         | SQL dump is missing                                                              |
| 6         | some module installation failed (with $ON_INSTALL_MODULES_FAILURE set to `fail`) |
| 7         | some init script failed (with $ON_INIT_SCRIPT_FAILURE set to `fail`)             |
| 8         | some post script failed (with $ON_POST_SCRIPT_FAILURE set to `fail`)             |

# Q&A

## Does Flashlight support PrestaShop 1.6?

Partially yes. As there is no console whithin the sources, the modules cannot be automatically installed right now. Feel free to contribute!

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

# Contribute

This Project is under the [MIT Licence](./LICENCE), your contribution and new use cases are very welcome.

## Build

Requirements:

- [jq](https://jqlang.github.io/jq/)

To build the latest PrestaShop version:

```sh
./build.sh
```

For a custom multi-platform build & push:

```sh
PS_VERSION=8.1.0 \
TARGETPLATFORM=linux/amd64,linux/arm64 \
PUSH=true \
TARGET_IMAGE=my-own-repo/testing:latest \
./build.sh
```

The `OS_FLAVOUR` defaults to `alpine` (see [Alpine Linux](https://www.alpinelinux.org/)) and `SERVER_FLAVOUR` to `nginx` (see [Nginx](https://www.nginx.com/)).

For more documentation about available build variables, please see [./build.sh](./build.sh).

## Lint

Requirements:

- [shellcheck](https://github.com/koalaman/shellcheck)
- [hadolint](https://github.com/hadolint/hadolint)

```sh
./lint.sh
```

# Credits

- https://github.com/PrestaShop/PrestaShop
- https://github.com/PrestaShop/performance-project
- https://github.com/jokesterfr/docker-prestashop
- https://github.com/PrestaShop/php-dev-tools
