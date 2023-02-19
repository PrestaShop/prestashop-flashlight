#!/bin/sh
set -e -o pipefail
cd $(dirname "$0")

# Configuration
PS_VERSION="${PS_VERSION:-8.0.1}"
PHP_VERSION="${PHP_VERSION:-8.2.2}"
PS_FOLDER="/var/www/html"
BUILDER_IMAGE="prestashop/flashlight-builder:latest"
BUILDER_CONTAINER="flashlight-builder"
FLASHLIGHT_IMAGE="prestashop/flashlight:${PS_VERSION}-${PHP_VERSION}"
DUMP_FILE="dump-${PS_VERSION}-${PHP_VERSION}.sql"
DUMP_PATH="/var/backup/${DUMP_FILE}"

# Build builder common docker image
docker build \
  -f ./Dockerfile \
  --target base-prestashop \
  --build-arg PS_VERSION=${PS_VERSION} \
  --build-arg PHP_VERSION=${PHP_VERSION} \
  --build-arg PS_FOLDER=${PS_FOLDER} \
  -t ${BUILDER_IMAGE} \
  .

# Run the auto-install
docker rm --force ${BUILDER_CONTAINER} 2> /dev/null
docker run \
  --name ${BUILDER_CONTAINER} \
  --volume $(pwd)/tools/auto-install-and-dump.sh:/run.sh:ro \
  --entrypoint /run.sh \
  --env DUMP_PATH=${DUMP_PATH} \
  --env PS_FOLDER=${PS_FOLDER} \
  ${BUILDER_IMAGE}

# Extract the dump
DEST_FILE="./${DUMP_FILE}";
docker cp ${BUILDER_CONTAINER}:${DUMP_PATH} ${DEST_FILE}
docker rm --force ${BUILDER_CONTAINER}

# Build PrestaShop Flashlight image
docker build \
  -f ./Dockerfile \
  --build-arg PS_VERSION=${PS_VERSION} \
  --build-arg PHP_VERSION=${PHP_VERSION} \
  --build-arg PS_FOLDER=${PS_FOLDER} \
  -t ${FLASHLIGHT_IMAGE} \
  .
