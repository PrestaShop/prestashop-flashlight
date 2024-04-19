# Module coding standard

As a module developer, you might want to run PHPStan linting with a given PrestaShop version for your module.
This is now made easier thanks to PrestaShop flashlight:

```
❯ docker run -it --rm \
  --entrypoint /usr/bin/phpstan \
  --volume ./testmodule:/var/www/html/modules/testmodule:ro \
  prestashop/prestashop-flashlight:latest \
  --memory-limit=-1 --configuration=/var/www/html/modules/testmodule/phpstan.neon
Detected PS version 8.1.5
 1/1 [▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓] 100%

 ------ ----------------------------------------------------------------
  Line   testmodule.php
 ------ ----------------------------------------------------------------
  33     Method Testmodule::install() has no return type specified.
  43     Method Testmodule::getFilePath() has no return type specified.
 ------ ----------------------------------------------------------------

 [ERROR] Found 2 errors
```
