<?php

if (!defined('_PS_VERSION_')) {
    exit;
}

class Testmodule extends Module
{
    /**
     * @var string
     */
    const VERSION = '1.0.0';

    public function __construct()
    {
        $this->name = 'testmodule';
        $this->author = 'PrestaShop';
        $this->version = '1.0.0';
        $this->ps_versions_compliancy = [
            'min' => '1.7.0',
            'max' => '99.99.99',
        ];
        $this->bootstrap = false;

        parent::__construct();
        $this->displayName = $this->l('Test Module', [], 'Modules.Mymodule.Admin');
        $this->description = $this->l('Test Module', [], 'Modules.Mymodule.Admin');
        $this->confirmUninstall = $this->l('Are you sure you want to quit ModuleA?', [], 'Modules.Mymodule.Admin');

        require_once __DIR__ . '/vendor/autoload.php';
    }

    public function install()
    {
        return true;
    }

    public function uninstall()
    {
        return true;
    }

    public function getFilePath()
    {
        return __FILE__;
    }        
}
