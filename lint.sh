#!/bin/bash
set -e
cd "$(dirname "$0")"

# Lint bash scripts
find . -type f -name '*.sh' -print0 | xargs -0 shellcheck -x;

# Lint docker files
find . -type f -name '*.Dockerfile' -print0 | xargs -0 hadolint;
