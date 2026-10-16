<?php
if(!defined('WP_CLI')||!WP_CLI){if(function_exists('http_response_code'))http_response_code(403);exit;}
$result=\ExcelHerbal\ERP7\Administration\StagingSafety::sanitize();
echo wp_json_encode($result,JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES).PHP_EOL;
