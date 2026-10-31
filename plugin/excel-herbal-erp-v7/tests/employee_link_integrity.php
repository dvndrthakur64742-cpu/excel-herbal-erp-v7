<?php
// Static regressions: database-backed and browser E2E verification remain required.
$checks = [
    'employee identity status and privileged-account guard' => [
        __DIR__ . '/../src/Organization/OrganizationEmployeeService.php',
        [
            'LEFT JOIN {$db->users} u ON u.ID=e.wp_user_id',
            'CASE WHEN u.ID IS NULL THEN 0 ELSE 1 END AS login_enabled',
            'get_user_by(\'id\',(int)$e[\'wp_user_id\'])!==false',
            'user_can($linkedUser,\'manage_options\')',
            'privileged_account_password_protected',
        ],
    ],
    'WordPress admin credential save contract' => [
        __DIR__ . '/../src/Admin/Dashboard.php',
        [
            '"X-Idempotency-Key":crypto.randomUUID()',
            '"X-WP-Nonce"',
            'data.error?.message',
            'credentials:"same-origin"',
        ],
    ],
];
foreach ($checks as $label => [$path, $needles]) {
    $src = file_get_contents($path);
    if (!is_string($src)) {fwrite(STDERR, "FAIL: missing source $path\n"); exit(1);}
    foreach ($needles as $needle) {
        if (!str_contains($src, $needle)) {
            fwrite(STDERR, "FAIL $label: missing $needle\n");
            exit(1);
        }
    }
    echo "PASS $label (static)\n";
}
