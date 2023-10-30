#!/bin/bash
set -eu

PS_FOLDER=${PS_FOLDER:?missing PS_FOLDER}
PS_VERSION=$(awk 'NR==1{print $2}' "${PS_FOLDER}/VERSION")

patch_1_6 () {
  # Add robots file
  echo "User-agent: *" > "${PS_FOLDER}/robots.txt"
  echo "Disallow: /" >> "${PS_FOLDER}/robots.txt"
}

if echo "$PS_VERSION" | grep "^1.6" > /dev/null; then
  patch_1_6;
fi