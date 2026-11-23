<?php
/** Isolated admin-only, no-production-write root diagnostics acceptance test. */
require_once __DIR__ . '/../src/Core/HostingRootDiagnostics.php';
use ExcelHerbal\ERP7\Core\HostingRootDiagnostics as D;

function eh7_host_check(bool $ok, string $message): void
{
    if (!$ok) {
        fwrite(STDERR, "FAIL $message\n");
        exit(1);
    }
    echo "PASS $message\n";
}

$dir = sys_get_temp_dir() . DIRECTORY_SEPARATOR . 'eh7-host-fixture-' .
    bin2hex(random_bytes(6));
$wp = $dir . DIRECTORY_SEPARATOR . 'wp';
$web = $dir . DIRECTORY_SEPARATOR . 'web';
mkdir($wp, 0700, true);
mkdir($web, 0700, true);
$index = '<html><base href="/wp-content/uploads/eh7-web-e7ede3d/"></html>';
$rewrite = "# controlled synthetic fixture\n" .
    "DirectoryIndex index.php\n" .
    "RewriteEngine On\n" .
    "RewriteRule ^$ /wp-content/uploads/eh7-web-e7ede3d/index.html [L]\n" .
    "# secret_never_disclose=synthetic-password-do-not-copy\n";
file_put_contents($web . DIRECTORY_SEPARATOR . 'index.html', $index);
file_put_contents($web . DIRECTORY_SEPARATOR . '.htaccess', $rewrite);
file_put_contents($wp . DIRECTORY_SEPARATOR . 'index.php', '<?php // WP synthetic');
$before = hash_file('sha256', $web . DIRECTORY_SEPARATOR . '.htaccess');
$record = D::inspect($wp, $web);
eh7_host_check($record['wordpress_root_available'] === true,
    'WP install root is discoverable');
eh7_host_check($record['http_document_root_available'] === true &&
    $record['same_directory'] === false,
    'Separate actual server document root is detected');
eh7_host_check($record['wordpress_root']['index.php']['present'] === true,
    'WP PHP entrypoint metadata available');
eh7_host_check($record['http_document_root']['index.html']['present'] === true &&
    $record['http_document_root']['index.html']['mentions_old_eh7_flutter_bundle'] === true,
    'Old Flutter static entry flagged by harmless boolean');
eh7_host_check($record['http_document_root']['.htaccess']['has_rewrite_rules'] === true &&
    $record['http_document_root']['.htaccess']['has_directory_index'] === true &&
    $record['http_document_root']['.htaccess']['mentions_old_eh7_flutter_bundle'] === true,
    'Rewrite and DirectoryIndex flags detected without contents');
$serialized = json_encode($record, JSON_THROW_ON_ERROR);
eh7_host_check(!str_contains($serialized, $dir) &&
    !str_contains($serialized, 'secret_never_disclose') &&
    !str_contains($serialized, '[L]') &&
    !str_contains($serialized, $rewrite),
    'No server paths, .htaccess lines or secrets exposed by inspector');
eh7_host_check(hash_file('sha256', $web . DIRECTORY_SEPARATOR . '.htaccess') === $before &&
    $record['content_or_configuration_modified'] === false,
    'Read-only inspection does not modify host files');
$missing = D::inspect($wp, null);
eh7_host_check($missing['http_document_root_available'] === false &&
    $missing['same_directory'] === null,
    'Missing HTTP document root remains unknown, never guessed');

class WP_Error
{
    public function __construct(
        public string $code,
        public string $message,
        public array $data
    ) {}
}
function register_rest_route(string $namespace, string $route, array $args): void
{
    $GLOBALS['eh7_diagnostic_route'] = compact('namespace', 'route', 'args');
}
$GLOBALS['eh7_can_manage'] = false;
function current_user_can(string $cap): bool
{
    return $cap === 'manage_options' && $GLOBALS['eh7_can_manage'] === true;
}
function wp_die(string $message): void
{
    throw new RuntimeException($message);
}
function esc_html(string $raw): string
{
    return htmlspecialchars($raw, ENT_QUOTES, 'UTF-8');
}
define('ABSPATH', $wp . DIRECTORY_SEPARATOR);
$_SERVER['DOCUMENT_ROOT'] = $web;
try {
    ob_start();
    D::adminPage();
    ob_end_clean();
    eh7_host_check(false, 'Non-admin user must not access diagnostic');
} catch (RuntimeException $e) {
    ob_end_clean();
    eh7_host_check(str_contains($e->getMessage(), 'administrator'),
        'Non-admin user denied before metadata output');
}
// Verify the WP REST route uses WordPress administrator capability, not
// the ordinary ERP employee bearer or an anonymous public callback.
D::registerRestRoute();
$route = $GLOBALS['eh7_diagnostic_route'];
eh7_host_check($route['namespace'] === 'eh7-host-diagnostics/v1' &&
    $route['route'] === '/root' &&
    $route['args']['methods'] === 'GET',
    'Separate read-only root REST route registered');
$permission = $route['args']['permission_callback'];
eh7_host_check($permission() === false,
    'Anonymous/ordinary staff cannot call root inspector via REST');
$denied = D::restReport();
eh7_host_check($denied instanceof WP_Error &&
    $denied->code === 'eh7_host_diagnostics_forbidden' &&
    $denied->data['status'] === 403,
    'Direct unauthorized REST callback also denies with 403');
$GLOBALS['eh7_can_manage'] = true;
eh7_host_check($permission() === true,
    'WordPress administrator may inspect the safe REST metadata');
$api = D::restReport();
eh7_host_check($api['ok'] === true &&
    $api['data']['same_directory'] === false &&
    !str_contains(json_encode($api, JSON_THROW_ON_ERROR), $dir),
    'Authorized REST response contains metadata but never the root path');
ob_start();
D::adminPage();
$html = ob_get_clean();
eh7_host_check(str_contains($html, 'Document root matches WordPress root') &&
    str_contains($html, 'Read-only'),
    'Administrator-only safe output produced');
eh7_host_check(!str_contains($html, $dir) &&
    !str_contains($html, 'secret_never_disclose') &&
    !str_contains($html, 'RewriteRule ^$'),
    'Admin HTML never prints absolute paths or rewrite configuration');

foreach ([
    $web . DIRECTORY_SEPARATOR . 'index.html',
    $web . DIRECTORY_SEPARATOR . '.htaccess',
    $wp . DIRECTORY_SEPARATOR . 'index.php',
] as $file) {
    unlink($file);
}
rmdir($web);
rmdir($wp);
rmdir($dir);
echo "PASSED root diagnostics metadata/read-only/admin isolation contracts\n";
