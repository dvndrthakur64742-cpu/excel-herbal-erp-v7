<?php
namespace ExcelHerbal\ERP7\Core;
final class Autoloader {
    public static function register(string $src): void {
        spl_autoload_register(static function (string $class) use ($src): void {
            $prefix = 'ExcelHerbal\\ERP7\\';
            if (!str_starts_with($class, $prefix)) return;
            $file = rtrim($src, '/\\') . '/' . str_replace('\\', '/', substr($class, strlen($prefix))) . '.php';
            if (is_file($file)) require_once $file;
        });
    }
}
