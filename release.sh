#!/bin/sh
publish() {
  gh workflow run docker-publish.yml \
  --repo prestashop/prestashop-flashlight "$@"
}

publish --field ps_version=latest
publish --field ps_version=1.7.8.10
publish --field ps_version=1.6.1.24

publish --field os_flavour=debian --field ps_version=latest
publish --field os_flavour=debian --field ps_version=1.7.8.10
publish --field os_flavour=debian --field ps_version=1.6.1.24

# Minor versions from 1.7
publish --field ps_version=1.7.0.6
publish --field ps_version=1.7.1.2
publish --field ps_version=1.7.2.5
publish --field ps_version=1.7.3.4
publish --field ps_version=1.7.4.4
publish --field ps_version=1.7.5.2
publish --field ps_version=1.7.6.9
publish --field ps_version=1.7.7.8
publish --field ps_version=1.7.8.9
publish --field ps_version=8.0.5