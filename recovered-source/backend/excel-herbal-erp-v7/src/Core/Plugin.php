<?php
namespace ExcelHerbal\ERP7\Core;use ExcelHerbal\ERP7\Database\Schema;use ExcelHerbal\ERP7\Http\Api;use ExcelHerbal\ERP7\Security\MobileAuth;
final class Plugin{public static function activate():void{Schema::install();}public static function boot():void{MobileAuth::boot();add_action('rest_api_init',[Api::class,'register']);}}
