![PrestaShop Flashlight logo](./assets/prestashop_flashlight_logo.png)

Spin up a PrestaShop testing instance in seconds!

PrestaShop Flashlight is fast: the PrestaShop installation wizard is run at build time, compiling the result to a single database dump. You will get all the content (catalog, orders...) of the usual PrestaShop development seed.

Supported architectures:

- linux/amd64 (aka `x86_64`)
- linux/arm64/v8 (aka `arm64`)

> **⚡ Disclaimer**: this tool is provided with the sole purpose of bootstrapping a **development or testing environment** and is **unsuitable for production**.  
> If you're looking for a production grade image, please refer to https://github.com/PrestaShop/docker.

# How to get PrestaShop Flashlight?

This project can [be built locally](#build) anytime, but it's easier to use our pre-built Docker image available on the [Docker Hub](https://hub.docker.com/r/prestashop/prestashop-flashlight).

You may browse a wide variety of tags, including:

- `latest`
- `nightly`
- `1.7.8.11` if you want PrestaShop 1.7.8.11 with its recommended PHP version and tools
- `1.7.8.11-debian` same as above, but shipped with Debian Linux (_Alpine Linux_ is the default)
- `1.7.8.11-7.4` PrestaShop version 1.7.8.11 with PHP 7.4 and Alpine Linux
- `php-8.1` to get the latest PrestaShop version recommending PHP 8.1

Some tags may not be built yet, feel free to [fill an issue](./issues) to request it.

# Use

PrestaShop Flashlight can be used as a **development environment**, a **CI/CD asset** to build up a custom PrestaShop environment, or any use case you can think of. Following is a list of resources and examples to get you started:

- [Auto installation of modules](./examples/auto-install-modules/)
- [Basic example](./examples/basic-example/)
- [Custom init-scripts](./examples/with-init-scripts/)
- [Custom post-scripts](./examples/with-post-scripts/)
- [Develop a PrestaShop module](./examples/develop-a-module/)
- [Develop PrestaShop](./examples/develop-prestashop/)
- [Ngrok tunneling](./examples/ngrok-tunnel)
- [Nightly example](./examples/nightly-example/)
- [Probe PrestaShop with Blackfire](./examples/blackfire-example/)
- [Validate a module with the PrestaShop coding standard](./examples/module-coding-standard/)
- [Xdebug a store](./examples/xdebug-prestashop/)
- Develop a PrestaShop Theme (coming soon)
- Use in GitHub Action (coming soon)

PrestaShop Flashlight embeds `nginx` and `php-fpm`, however the `MySQL` server has to be provided separately. This can easily be achieved using docker compose: _docker-compose.yml_ files are provided in [examples](./examples).

## Compatibility

PrestaShop Flashlight is based on the official compatibility charts:

- PrestaShop 1.6-1.7.x [PHP compatibility chart](https://devdocs.prestashop-project.org/1.7/basics/installation/system-requirements/#php-compatibility-chart)
- PrestaShop 8.x [PHP compatibility chart](https://devdocs.prestashop-project.org/8/basics/installation/system-requirements/#php-compatibility-chart)

You can check this implementation anytime in [prestashop-version.json](./prestashop-version.json).

| Supported PrestaShop versions | Supported PHP versions |
| ----------------------------- | ---------------------- |
| 1.6.1.11-1.6.1.24             | PHP 5.6 - 7.1          |
| 1.7.0 ~ 1.7.4                 | PHP 5.6 - 7.1          |
| 1.7.5 ~ 1.7.6                 | PHP 5.6 - 7.2          |
| 1.7.7                         | PHP 7.1 - 7.3          |
| 1.7.8                         | PHP 7.1 - 7.4          |
| 8.0~8.1                       | PHP 7.2 - 8.1          |
| nightly                       | PHP 8.1 - 8.3          |

PrestaShop Flashlight **does not support** PHP versions prior to PHP 5.6 with Alpine Linux, 8.0 with Debian, here is why:

- Official PHP docker images are very old for PHP 5.2, 5.3, 5.4... til the point docker images do not comply with current docker engines.
- Old debian / alpine OS releases do not support arm64 builds and packages
- Rebuilding legacy PHP environments compatible with moddern docker images is costly, with a low value for Flashlight
- Migrating from PHP 5.2 to 5.6 might not be a hard task for an agency/merchant.
- Sury repositories dropped support for Debian Jessie, Stretch & Buster

## Environment variables

| Variable                   | Description                                                                                                  | Default value                          |
| -------------------------- | ------------------------------------------------------------------------------------------------------------ | -------------------------------------- |
| PS_DOMAIN¹                 | the public domain (and port) to reach your PrestaShop instance                                               | N/A (example: `localhost:8000`)        |
| NGROK_TUNNEL_AUTO_DETECT²  | the ngrok agent base API url, to guess the tunnel domain of your shop                                        | N/A (example `http://ngrok:4040`)      |
| DEBUG_MODE                 | if enabled the Debug mode will be enabled on PrestaShop                                                      | `false`                                |
| DRY_RUN                    | if enabled, the run.sh script will exit without really starting a web server                                 | `false`                                |
| DUMP_ON_RESTART            | if enabled the dump restoration replayed on container restart                                                | `false`                                |
| INIT_ON_RESTART            | if enabled the PS_DOMAIN auto search and dump fix will be replayed on container restart                      | `false`                                |
| INIT_SCRIPTS_DIR           | script directory with executable files to be run prior to PrestaShop startup                                 | `/tmp/init-scripts`                    |
| INIT_SCRIPTS_ON_RESTART    | if enabled custom init scripts will be replayed on container restart                                         | `false`                                |
| INSTALL_MODULES_DIR        | module directory containing zips to be installed with the PrestaShop CLI                                     | empty string (example: `/ps-modules`)  |
| INSTALL_MODULES_ON_RESTART | if enabled zip modules will be reinstalled on container restart                                              | `false`                                |
| MYSQL_DATABASE             | MySQL database name                                                                                          | `prestashop`                           |
| MYSQL_EXTRA_DUMP           | extra SQL dump to be restored in PrestaShop                                                                  | empty string (example: `/tmp/foo.sql`) |
| MYSQL_HOST                 | MySQL host                                                                                                   | `mysql`                                |
| MYSQL_PASSWORD             | MySQL password                                                                                               | `prestashop`                           |
| MYSQL_PORT                 | MySQL server port                                                                                            | `3306`                                 |
| MYSQL_USER                 | MySQL user                                                                                                   | `prestashop`                           |
| ON_INIT_SCRIPT_FAILURE     | if set to `continue`, PrestaShop Flashlight will continue the boot process even if an init script failed     | `fail`                                 |
| ON_INSTALL_MODULES_FAILURE | if set to `continue`, module installation failure will not block the init process                            | `fail`                                 |
| ON_POST_SCRIPT_FAILURE     | if set to `continue`, PrestaShop Flashlight won't exit in case of script failure                             | `fail`                                 |
| POST_SCRIPTS_DIR           | script directory with executable files to be run after the PrestaShop startup                                | `/tmp/post-scripts`                    |
| POST_SCRIPTS_ON_RESTART    | if enabled custom post scripts will be replayed on container restart                                         | `false`                                |
| PS_FOLDER                  | prestashop sources directory                                                                                 | `/var/www/html`                        |
| PS_PROTOCOL                | if PS_PROTOCOL equals `https` the public URL will be `https://$PS_DOMAIN`                                    | `http` (example: `https`)              |
| SSL_REDIRECT               | if enabled the public URL will be `https://$PS_DOMAIN` (if not using `PS_PROTOCOL`)                          | `false` (example: `true`)              |
| XDEBUG_ENABLED             | if enabled Xdebug will be enabled in PHP. See settings here: `$PHP_INI_DIR/conf.d/docker-php-ext-xdebug.ini` | `false` (example: `true`)              |
| BLACKFIRE_ENABLED          | if enabled Blackfire will be enabled in PHP.                                                                 | `false` (example: `true`)              |

> Note:
>
> - ¹required (mutually exclusive with `NGROK_TUNNEL_AUTO_DETECT`)
> - ²required (mutually exclusive with `PS_DOMAIN`)

## User

PrestaShop Flashlight user is `www-data`, in order to set an example, by applying good security practices.
However you can anytime run a container with docker, using `--user root` or in your docker-compose file, with `user: root`.

See:

- https://docs.docker.com/reference/cli/docker/container/run/#options
- https://docs.docker.com/compose/compose-file/05-services/#user

## Back office access information

The default url/credentials to access to PrestaShop's back office defined in [`./assets/hydrate.sh`](./assets/hydrate.sh) and are set to:

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

Yes. A polyfill is provided for the PrestaShop console, officially introduced in 1.7.

## Developing a module with RW (known Linux issue)

The [develop-a-module](https://github.com/PrestaShop/prestashop-flashlight/tree/main/examples/develop-a-module) example is provided as a local environment for a developer. At PrestaShop, we could successfully use it with Mac OSx and Windows, but due to the nature of the Docker implementation on Linux (no virtualization), we could not yet allow the module to write content from PrestaShop to the host. Will keep you posted here, feel free to suggest your ideas in this project issues.

## Api calls within a docker network

**Disclaimer**: PrestaShop is sensitive to the `Host` header of your client, and can behave surprisingly. In fact, since the Multi-shop feature is available, you cannot just call any front controller from any endpoint unless you set the `Host` or the `id_shop` you are targeting.

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

Indeed, this **WON'T WORK**, the container port is 80, only the host knows about 8000 in our use case. Let's talk about it:

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

Dependencies:

- [jq](https://jqlang.github.io/jq/)
- [Docker buildx](https://github.com/docker/buildx)

To build Flashlight for the latest PrestaShop version available:

```sh
./build.sh
```

Same but for a predefined PHP and PrestaShop version:

```sh
PS_VERSION=8.1.0 \
PHP_VERSION=8.1 \
TARGET_IMAGE=my-own-repo/testing:latest \
./build.sh
```

To get more documentation on the available build options, please consider reading the [build.sh](./build.sh) top file `Available variables` section.

### Cross compiling for another architecture

Init buildx:

```sh
docker buildx create --name mybuilder --use --platform linux/amd64,linux/arm64
```

Then:

```sh
TARGET_PLATFORM=linux/amd64,linux/arm64 \
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
