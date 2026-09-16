<?php
/**
 * Plugin Name: Excel Herbal ERP 7 Clean Core
 * Version: 7.3.5-rc1
 * Requires PHP: 8.1
 */
if(!defined('ABSPATH'))exit;define('EH7_VERSION','7.3.5-rc1');define('EH7_DIR',plugin_dir_path(__FILE__));require_once EH7_DIR.'src/Core/Autoloader.php';\ExcelHerbal\ERP7\Core\Autoloader::register(EH7_DIR.'src');register_activation_hook(__FILE__,[\ExcelHerbal\ERP7\Core\Plugin::class,'activate']);add_action('plugins_loaded',[\ExcelHerbal\ERP7\Core\Plugin::class,'boot']);
