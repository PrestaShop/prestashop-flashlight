#!/usr/local/bin/php -d memory_limit=-1
<?php
if (!defined('_PS_ADMIN_DIR_')) { define('_PS_ADMIN_DIR_', '/admin-dev'); }
if (!defined('_PS_MODE_DEV_')) { define('_PS_MODE_DEV_', true); }
$rootDirectory = getenv('_PS_ROOT_DIR_') ?: '/var/www/html';
require_once $rootDirectory . '/config/config.inc.php';

function getModuleName($args) {
  for ($i = 0; $i < count($args); $i++) {
    if ($args[$i] === 'install') {
      if (isset($args[$i + 1])) {
        return $args[$i + 1];
      }
    } 
  }
  throw new Exception('Module name not found');
}

function installModule($args) {
  $moduleName = getModuleName($args);
  if (version_compare(_PS_VERSION_, '1.7', '>=')) {
    global $kernel;
    if(!$kernel){
      require_once _PS_ROOT_DIR_.'/app/AppKernel.php';
      $kernel = new \AppKernel('dev', true);
      $kernel->boot();
    }
  }
  $module = Module::getInstanceByName($moduleName);
  $module->install();
}

function clearCache() {
  $cacheDirs = [
    _PS_CACHEFS_DIRECTORY_ . '/smarty/compile',
    _PS_CACHEFS_DIRECTORY_ . '/smarty/cache',
    _PS_IMG_DIR_ . '/tmp',
  ];
  foreach ($cacheDirs as $dir) {
    $files = glob($dir . '/*');
    foreach ($files as $file) {
      if (is_file($file)) {
        unlink($file);
      }
    }
  }
}

switch ($argv[1]) {
  case 'prestashop:module':
    installModule($argv);
    break;
  case 'cache:clear':
    clearCache();
    break;
  default:
    throw new Exception('This command is not supported by prestashop-flashlight\'s polyfill');
}

