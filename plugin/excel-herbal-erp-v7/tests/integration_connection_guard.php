<?php
declare(strict_types=1);

// No database connection or WordPress data is required for this guard test.
define('EH7_INTEGRATION_LIBRARY_ONLY', true);
require __DIR__.'/integration_mariadb.php';

$names = [
    'EH7_INTEGRATION_MODE',
    'EH7_MARIADB_DATABASE',
    'EH7_MARIADB_HOST',
    'EH7_MARIADB_PORT',
];
$original = [];
foreach ($names as $name) $original[$name] = getenv($name);

function guardCase(
    string $name,
    ?string $mode,
    ?string $database,
    ?string $host,
    ?string $port,
    bool $allowed
): void {
    foreach ([
        'EH7_INTEGRATION_MODE' => $mode,
        'EH7_MARIADB_DATABASE' => $database,
        'EH7_MARIADB_HOST' => $host,
        'EH7_MARIADB_PORT' => $port,
    ] as $key => $value) {
        putenv($value === null ? $key : $key.'='.$value);
    }
    try {
        eh7_assert_synthetic_connection();
        if (!$allowed) throw new LogicException('Unsafe database config was allowed: '.$name);
    } catch (RuntimeException $e) {
        if ($allowed || !str_starts_with($e->getMessage(), 'REFUSED:')) {
            throw new LogicException('Wrong guard response for '.$name, 0, $e);
        }
    }
    echo 'PASS '.$name."\n";
}

try {
    guardCase('reject unset mode and database', null, null, null, null, false);
    guardCase('reject production mode', 'production', 'eh7_test_prepaid', '127.0.0.1', '3306', false);
    guardCase('reject regular WordPress database', 'synthetic', 'wordpress', '127.0.0.1', '3306', false);
    guardCase('reject database prefix without suffix', 'synthetic', 'eh7_test_', '127.0.0.1', '3306', false);
    guardCase('reject SQL-ish database name', 'synthetic', 'eh7_test_a;DROP', '127.0.0.1', '3306', false);
    guardCase('reject production domain', 'synthetic', 'eh7_test_prepaid', 'office.excelherbal.in', '3306', false);
    guardCase('reject remote IP', 'synthetic', 'eh7_test_prepaid', '10.0.0.4', '3306', false);
    guardCase('reject invalid port', 'synthetic', 'eh7_test_prepaid', 'localhost', '65536', false);
    guardCase('permit CI localhost test database', 'synthetic', 'eh7_test_prepaid', '127.0.0.1', '3306', true);
    guardCase('permit isolated MariaDB Docker service', 'synthetic', 'eh7_test_prepaid', 'mariadb', '3306', true);
    echo "PASSED connection safety before any database access\n";
} finally {
    foreach ($original as $name => $value) {
        putenv($value === false ? $name : $name.'='.$value);
    }
}
