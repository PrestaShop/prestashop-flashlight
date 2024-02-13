# Example: develop prestashop

Flashlight can help you bootstrap an environment to perform live development of PrestaShop itself. We hope the tool to help your contribution with a fast and flexible environment!

## Test the example

Clone PrestaShop sources:

```sh
git clone --depth 1 https://github.com/PrestaShop/PrestaShop.git
```

Get in your sources and copy this example:

```sh
cd ./PrestaShop
git clone --depth 1 https://github.com/PrestaShop/PrestaShop-Flashlight.git
mv ./PrestaShop-Flashlight/examples/develop-prestashop ./e2e-env
rm -rf ./PrestaShop-Flashlight
```

You are now ready to run PrestaShop within your Flashlight environment:

```
cd e2e-env
docker compose up prestashop --force-recreate
[+] Building 0.0s (0/0)                             docker-container:thirsty_khorana
[+] Running 3/3
 ✔ Network e2e-env_default         Created                                      0.1s
 ✔ Container e2e-env-mysql-1       Created                                      0.0s
 ✔ Container e2e-env-prestashop-1  Created                                      0.1s
Attaching to e2e-env-prestashop-1
e2e-env-prestashop-1  | * Applying PS_DOMAIN (localhost:8000) to the dump...
e2e-env-prestashop-1  | * Checking MySQL connectivity...
e2e-env-prestashop-1  | * PHP PDO connectivity checked
e2e-env-prestashop-1  | * Editing PrestaShop configuration...
```
