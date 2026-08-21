#!/usr/bin/env bash
# Prune registry cache: delete blobs older than 30 days, then garbage-collect.
set -euo pipefail

REGISTRY_DATA=/var/lib/docker-registry-mirror

echo "[$(date -Iseconds)] Starting cache prune (blobs older than 30 days)..."

# Delete repository manifest revision files older than 30 days.
# This marks images as unreferenced so GC can remove their blobs.
find "$REGISTRY_DATA/docker/registry/v2/repositories" \
  -name "*.json" -mtime +30 -delete 2>/dev/null || true

find "$REGISTRY_DATA/docker/registry/v2/repositories" \
  -name "link" -mtime +30 -delete 2>/dev/null || true

# Run registry garbage collect inside the container
docker exec docker-registry-mirror \
  /bin/registry garbage-collect \
  --delete-untagged \
  /etc/docker/registry/config.yml

echo "[$(date -Iseconds)] Cache prune complete."
