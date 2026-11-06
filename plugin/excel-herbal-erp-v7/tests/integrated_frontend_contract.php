<?php
/** Pure source/route gate for the unified review-only Flutter frontend. */
require_once __DIR__ . '/../src/Core/IntegratedFrontend.php';
use ExcelHerbal\ERP7\Core\IntegratedFrontend as UI;
if (!function_exists('esc_url')) {
    function esc_url($url) { return htmlspecialchars((string)$url, ENT_QUOTES, 'UTF-8'); }
}
function ensure($pass, $message): void {
    if (!$pass) { fwrite(STDERR, "FAIL $message\n"); exit(1); }
    echo "PASS $message\n";
}
ensure(UI::isPreviewRequest('/erp/', 'https://office.excelherbal.in/'),
    'exact /erp/ preview route');
ensure(UI::isSiteRootRequest('/', 'https://office.excelherbal.in/'),
    'exact Office homepage is eligible only after administrator opt-in');
ensure(!UI::isSiteRootRequest('/erp/', 'https://office.excelherbal.in/'),
    'preview is not mistaken for homepage');
ensure(!UI::isSiteRootRequest('/wp-json/excel-herbal-erp/v7/health',
    'https://office.excelherbal.in/'),
    'WP REST routes cannot be mistaken for homepage');
ensure(!UI::isSiteRootRequest('/wp-admin/',
    'https://office.excelherbal.in/'),
    'WordPress administration cannot be mistaken for homepage');
ensure(UI::isSiteRootRequest('/company/', 'https://uat.invalid/company/'),
    'subdirectory site root is matched exactly');
ensure(!UI::isSiteRootRequest('/', 'https://uat.invalid/company/'),
    'subdirectory site does not hijack host root');

ensure(UI::isPreviewRequest('/erp?review=1', 'https://office.excelherbal.in/'),
    'preview query parameters do not break routing');
ensure(!UI::isPreviewRequest('/erp-danger', 'https://office.excelherbal.in/'),
    'unrelated WordPress page untouched');
ensure(UI::isPreviewRequest('/company/erp/', 'https://test.invalid/company/'),
    'subdirectory installation routing');
ensure(!UI::isPreviewRequest('/erp/', 'https://test.invalid/company/'),
    'subdirectory scope cannot escape');
ensure(UI::isOfficeHost('https://office.excelherbal.in/', 'office.excelherbal.in'),
    'production URL and HTTP host agree');
ensure(!UI::isOfficeHost('https://office.excelherbal.in/', 'uat.invalid'),
    'staging request cannot fetch production-compiled Flutter');
ensure(!UI::isOfficeHost('https://uat.invalid/', 'office.excelherbal.in'),
    'cloned UAT URL cannot impersonate Office');
ensure(!UI::isOfficeHost('https://office.excelherbal.in/', 'office.excelherbal.in.other.test'),
    'Office host suffix spoof fails closed');
$html = '<html><head><base href="__EH7_PLUGIN_ASSET_BASE__"></head></html>';
$actual = UI::renderShell($html,
    'https://office.excelherbal.in/wp-content/plugins/excel-herbal-erp-v7/web/');
ensure(str_contains($actual, '/excel-herbal-erp-v7/web/'),
    'asset base is served by same WordPress plugin');
ensure(!str_contains($actual, '__EH7_PLUGIN_ASSET_BASE__'),
    'asset placeholder removed');
try {
    UI::renderShell($actual, 'https://bad.invalid/');
    ensure(false, 'missing placeholder must fail');
} catch (RuntimeException $e) {
    ensure(true, 'missing placeholder fails closed');
}
echo "PASSED single plugin frontend route contracts (no WordPress writes)\n";
