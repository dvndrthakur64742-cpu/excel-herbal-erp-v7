<?php
declare(strict_types=1);
/**
 * PHP built-in server router for a real WordPress core installation.
 * No WordPress/auth mocks. Maps pretty /wp-json/... URLs to WordPress'
 * query-based REST routing, avoiding .htaccess on the loopback test server.
 */
$root=getenv('B2B_REAL_WP_ROOT')?:'';
if(!is_string($root)||$root===''||!is_file($root.'/wp-load.php'))
    {http_response_code(500);exit('No disposable WordPress install');}
$path=(string)(parse_url($_SERVER['REQUEST_URI']??'/',PHP_URL_PATH)??'/');
if($path==='/wp-json'||str_starts_with($path,'/wp-json/')){
    $_GET['rest_route']=substr($path,strlen('/wp-json'));
    require $root.'/index.php';
    return true;
}
$file=realpath($root.$path);
$prefix=rtrim(realpath($root)?:'',DIRECTORY_SEPARATOR).DIRECTORY_SEPARATOR;
if($file!==false&&str_starts_with($file,$prefix)&&is_file($file))
    return false;
require $root.'/index.php';
return true;
