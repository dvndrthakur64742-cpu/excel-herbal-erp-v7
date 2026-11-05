<?php
// Startup API contract: static guard until authenticated UAT HTTP checks run.
// The Flutter app fails closed if any of these four fields is absent.
$source = file_get_contents(__DIR__ . '/../src/Http/ApiDispatch.php');
if (!is_string($source)) {
    fwrite(STDERR, "FAIL bootstrap source unavailable\n");
    exit(1);
}
$start = strpos($source, 'private static function bootstrap(Actor $a):array');
$end = strpos($source, 'private static function companyProfile(', $start ?: 0);
if ($start === false || $end === false || $end <= $start) {
    fwrite(STDERR, "FAIL bootstrap handler missing\n");
    exit(1);
}
$bootstrap = substr($source, $start, $end - $start);
$required = [
    "'business_date'=>Db::today()",
    "'business_timezone'=>wp_timezone_string()",
    "'server_timestamp'=>gmdate('c')",
    "'api_contract'=>ApiContract::VERSION",
    "'features'=>",
];
foreach ($required as $field) {
    if (!str_contains($bootstrap, $field)) {
        fwrite(STDERR, "FAIL missing bootstrap metadata: $field\n");
        exit(1);
    }
}
echo "PASS Flutter-compatible bootstrap metadata (static)\n";
