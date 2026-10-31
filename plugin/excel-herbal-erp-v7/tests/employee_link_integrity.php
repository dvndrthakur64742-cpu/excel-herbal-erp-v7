<?php
// Static regression guard; database-backed integration remains required.
$src = file_get_contents(__DIR__ . '/../src/Organization/OrganizationEmployeeService.php');
foreach ([
    'LEFT JOIN {$db->users} u ON u.ID=e.wp_user_id',
    'CASE WHEN u.ID IS NULL THEN 0 ELSE 1 END AS login_enabled',
    'get_user_by(\'id\',(int)$e[\'wp_user_id\'])!==false',
] as $needle) {
    if (!str_contains($src, $needle)) {
        fwrite(STDERR, 'FAIL employee link validation guard: ' . $needle . PHP_EOL);
        exit(1);
    }
}
echo 'PASS employee login status requires existing WordPress identity (static)' . PHP_EOL;
