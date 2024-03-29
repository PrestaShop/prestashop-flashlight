# Example: auto installing modules

This is an example of auto-installing modules at _PrestaShop Flashlight_ startup.
It will statically install all modules provided in the `./module` directory,
and install one module dynamically (see `./init-scripts`).

## Test the example

```sh
docker-compose up prestashop
```

The expected output of this example is:

```sh
docker-compose up prestashop
[+] Building 0.0s (0/0)
[+] Running 3/2
 ✔ Network auto-install-modules_default         Created                                                                                                                                                                                                        0.0s
 ✔ Container auto-install-modules-mysql-1       Created                                                                                                                                                                                                        0.1s
 ✔ Container auto-install-modules-prestashop-1  Created                                                                                                                                                                                                        0.1s
Attaching to auto-install-modules-prestashop-1
auto-install-modules-prestashop-1  | * Applying PS_DOMAIN (localhost:8000) to the dump...
auto-install-modules-prestashop-1  | * Checking MySQL connectivity...
auto-install-modules-prestashop-1  | * PHP PDO connectivity checked
auto-install-modules-prestashop-1  | * PrestaShop MySQL client configuration set
auto-install-modules-prestashop-1  | * Restoring MySQL dump...
auto-install-modules-prestashop-1  | * MySQL dump restored!
auto-install-modules-prestashop-1  | --> Unzipping and installing psxmarketingwithgoogle from /ps-modules/psxmarketingwithgoogle-v1.61.1.zip...
auto-install-modules-prestashop-1  |
auto-install-modules-prestashop-1  |   Install action on module psxmarketingwithgoogle succeeded.
auto-install-modules-prestashop-1  |
auto-install-modules-prestashop-1  | * No init script(s) found
auto-install-modules-prestashop-1  | * Starting php-fpm...
auto-install-modules-prestashop-1  | * Starting nginx...
auto-install-modules-prestashop-1  | * Nginx started
auto-install-modules-prestashop-1  | * No post script(s) found
```

If you try to install an invalid module, you will get an `exit 6` error like so:

```sh
auto-install-modules-prestashop-1  | --> Unzipping and installing ps_accounts.zip from /ps-modules/ps_accounts.zip...
auto-install-modules-prestashop-1  | 17:18:12 ERROR     [console] Error thrown while running command "prestashop:module --no-interaction install 'ps_accounts.zip'". Message: "The module ps_accounts.zip could not be found on Addons." ["exception" => PrestaShop\PrestaShop\Core\Domain\Theme\Exception\FailedToEnableThemeModuleException { …},"command" => "prestashop:module --no-interaction install 'ps_accounts.zip'","message" => "The module ps_accounts.zip could not be found on Addons."]
auto-install-modules-prestashop-1  |
auto-install-modules-prestashop-1  | In ModuleManager.php line 299:
auto-install-modules-prestashop-1  |
auto-install-modules-prestashop-1  |   The module ps_accounts.zip could not be found on Addons.
auto-install-modules-prestashop-1  |
auto-install-modules-prestashop-1  |
auto-install-modules-prestashop-1  | prestashop:module [-h|--help] [-q|--quiet] [-v|vv|vvv|--verbose] [-V|--version] [--ansi] [--no-ansi] [-n|--no-interaction] [-e|--env ENV] [--no-debug] [--id_shop [ID_SHOP]] [--id_shop_group [ID_SHOP_GROUP]] [--] <command> <action> <module name> [<file path>]
auto-install-modules-prestashop-1  |
auto-install-modules-prestashop-1  | x module installation failed. Sleep and exit.
auto-install-modules-prestashop-1 exited with code 6
```

Unless you decide to skip this behavior with `ON_INSTALL_MODULES_FAILURE=continue`
