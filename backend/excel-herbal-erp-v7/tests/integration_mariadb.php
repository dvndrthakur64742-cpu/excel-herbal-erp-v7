<?php
/**
 * Disposable MariaDB integration tests for actual ERP database primitives.
 *
 * Required environment:
 * EH7_MARIADB_HOST, EH7_MARIADB_PORT, EH7_MARIADB_USER,
 * EH7_MARIADB_PASSWORD, EH7_MARIADB_DATABASE
 */
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Idempotency;

if (!defined('ARRAY_A')) define('ARRAY_A', 'ARRAY_A');
if (!function_exists('current_time')) {
    function current_time($format, $gmt = false) {
        $ts = time();
        // Isolated MariaDB UAT only: deterministic local clock, NEVER present in
        // production. The override is reset after the individual UAT case.
        $fake = $GLOBALS['eh7_uat_clock_override'] ?? null;
        if (is_string($fake) && $fake !== '') {
            $ts = strtotime(gmdate('Y-m-d', $ts).' '.$fake.' UTC');
            if ($ts === false) throw new RuntimeException('Invalid disposable UAT clock');
        }
        if ($format === 'mysql') return gmdate('Y-m-d H:i:s', $ts);
        if ($format === 'Y-m-d') return gmdate('Y-m-d', $ts);
        return gmdate($format, $ts);
    }
}
if (!function_exists('wp_json_encode')) {
    function wp_json_encode($value, $flags = 0) { return json_encode($value, $flags); }
}

final class Eh7IntegrationWpdb {
    public string $prefix = 'wp_';
    public string $last_error = '';
    public int $insert_id = 0;

    public function __construct(private mysqli $db) {}

    public function prepare(string $query, ...$args): string {
        foreach ($args as $arg) {
            $matched = false;
            $query = preg_replace_callback('/%(?:d|f|s)/', function ($m) use (&$matched, $arg) {
                if ($matched) return $m[0];
                $matched = true;
                return match ($m[0]) {
                    '%d' => (string)(int)$arg,
                    '%f' => (string)(float)$arg,
                    default => $this->quote($arg),
                };
            }, $query, 1);
        }
        return $query;
    }

    public function query(string $sql): int|false {
        $this->last_error = '';
        try {
            $result = $this->db->query($sql);
        } catch (Throwable $e) {
            $this->last_error = $e->getMessage();
            return false;
        }
        if ($result === false) {
            $this->last_error = $this->db->error;
            return false;
        }
        if ($result instanceof mysqli_result) {
            $count = $result->num_rows;
            $result->free();
            return $count;
        }
        return max(0, (int)$this->db->affected_rows);
    }

    public function get_row(string $sql, $mode = ARRAY_A): ?array {
        $result = $this->result($sql);
        if (!$result) return null;
        $row = $result->fetch_assoc() ?: null;
        $result->free();
        return $row;
    }

    public function get_var(string $sql): mixed {
        $result = $this->result($sql);
        if (!$result) return null;
        $row = $result->fetch_row();
        $result->free();
        return $row ? $row[0] : null;
    }

    public function get_col(string $sql): array {
        $result = $this->result($sql);
        if (!$result) return [];
        $values = [];
        while ($row = $result->fetch_row()) $values[] = $row[0];
        $result->free();
        return $values;
    }

    public function get_results(string $sql, $mode = ARRAY_A): array {
        $result = $this->result($sql);
        if (!$result) return [];
        $rows = [];
        while ($row = $result->fetch_assoc()) $rows[] = $row;
        $result->free();
        return $rows;
    }

    public function insert(string $table, array $data): int|false {
        $columns = array_map(fn($key) => $this->ident((string)$key), array_keys($data));
        $values = array_map(fn($value) => $this->quote($value), array_values($data));
        $sql = 'INSERT INTO '.$this->ident($table).' ('.implode(',', $columns).') VALUES ('.implode(',', $values).')';
        $result = $this->query($sql);
        if ($result === false) return false;
        $this->insert_id = (int)$this->db->insert_id;
        return 1;
    }

    public function update(string $table, array $data, array $where): int|false {
        $sets = [];
        foreach ($data as $key => $value) $sets[] = $this->ident((string)$key).'='.$this->quote($value);
        $clauses = [];
        foreach ($where as $key => $value) {
            $clauses[] = $value === null
                ? $this->ident((string)$key).' IS NULL'
                : $this->ident((string)$key).'='.$this->quote($value);
        }
        return $this->query('UPDATE '.$this->ident($table).' SET '.implode(',', $sets).' WHERE '.implode(' AND ', $clauses));
    }

    private function result(string $sql): mysqli_result|false {
        $this->last_error = '';
        try {
            $result = $this->db->query($sql);
        } catch (Throwable $e) {
            $this->last_error = $e->getMessage();
            return false;
        }
        if (!$result instanceof mysqli_result) {
            if ($result === false) $this->last_error = $this->db->error;
            return false;
        }
        return $result;
    }

    private function quote(mixed $value): string {
        if ($value === null) return 'NULL';
        if (is_bool($value)) return $value ? '1' : '0';
        if (is_int($value)) return (string)$value;
        if (is_float($value)) return rtrim(rtrim(sprintf('%.10F', $value), '0'), '.');
        return "'".$this->db->real_escape_string((string)$value)."'";
    }

    private function ident(string $value): string {
        if (!preg_match('/^[A-Za-z0-9_]+$/', $value)) throw new RuntimeException('Unsafe SQL identifier.');
        return '`'.$value.'`';
    }
}

function eh7_connect(): mysqli {
    mysqli_report(MYSQLI_REPORT_OFF);
    $host = getenv('EH7_MARIADB_HOST') ?: '127.0.0.1';
    $port = (int)(getenv('EH7_MARIADB_PORT') ?: 3306);
    $user = getenv('EH7_MARIADB_USER') ?: 'root';
    $password = getenv('EH7_MARIADB_PASSWORD') ?: '';
    $database = getenv('EH7_MARIADB_DATABASE') ?: '';
    $db = @new mysqli($host, $user, $password, $database, $port);
    if ($db->connect_errno) throw new RuntimeException('MariaDB connection failed: '.$db->connect_error);
    $db->set_charset('utf8mb4');
    return $db;
}

function eh7_setup_global_db(): Eh7IntegrationWpdb {
    global $wpdb;
    $wpdb = new Eh7IntegrationWpdb(eh7_connect());
    return $wpdb;
}

function eh7_schema(Eh7IntegrationWpdb $db): void {
    foreach (['wp_eh7_integration_probe', 'wp_eh7_idempotency_keys'] as $table) {
        if ($db->query('DROP TABLE IF EXISTS `'.$table.'`') === false) throw new RuntimeException($db->last_error);
    }
    $sql = [
        "CREATE TABLE wp_eh7_idempotency_keys (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            request_hash CHAR(64) NOT NULL,
            company_id BIGINT UNSIGNED NOT NULL,
            employee_id BIGINT UNSIGNED NOT NULL,
            operation VARCHAR(190) NOT NULL,
            payload_hash CHAR(64) NULL,
            status VARCHAR(20) NOT NULL,
            response_json LONGTEXT NULL,
            created_at DATETIME NOT NULL,
            completed_at DATETIME NULL,
            PRIMARY KEY (id),
            UNIQUE KEY request_hash (request_hash)
        ) ENGINE=InnoDB",
        "CREATE TABLE wp_eh7_integration_probe (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            token VARCHAR(100) NOT NULL,
            value_int INT NOT NULL,
            created_at DATETIME NOT NULL,
            PRIMARY KEY (id),
            KEY token_idx (token)
        ) ENGINE=InnoDB",
    ];
    foreach ($sql as $statement) if ($db->query($statement) === false) throw new RuntimeException($db->last_error);
}

function eh7_count(Eh7IntegrationWpdb $db, string $token): int {
    return (int)$db->get_var($db->prepare('SELECT COUNT(*) FROM wp_eh7_integration_probe WHERE token=%s', $token));
}

function eh7_worker(): never {
    $wpdb = eh7_setup_global_db();
    $actor = new Actor(10, 10, 1, 1, [1], [], 'BM');
    try {
        $out = Idempotency::run(
            $actor,
            'concurrent-shared-key',
            'integration.concurrent',
            function () use ($wpdb) {
                if ($wpdb->insert('wp_eh7_integration_probe', [
                    'token' => 'concurrent',
                    'value_int' => 1,
                    'created_at' => Db::now(),
                ]) === false) throw new RuntimeException($wpdb->last_error);
                usleep(700000);
                return ['result' => 'single-execution'];
            },
            ['branch_id' => 1, 'amount' => 100]
        );
        echo json_encode(['ok' => true, 'out' => $out], JSON_THROW_ON_ERROR);
        exit(0);
    } catch (Throwable $e) {
        fwrite(STDERR, get_class($e).': '.$e->getMessage());
        exit(2);
    }
}

if (($argv[1] ?? '') === 'worker') eh7_worker();

if (defined('EH7_INTEGRATION_LIBRARY_ONLY') && EH7_INTEGRATION_LIBRARY_ONLY) return;

$failed = 0;
function pass_case(string $name): void { echo "PASS {$name}\n"; }
function fail_case(string $name, Throwable|string $error): void {
    global $failed;
    $failed++;
    $message = $error instanceof Throwable ? $error->getMessage() : $error;
    echo "FAIL {$name}: {$message}\n";
}
function run_case(string $name, callable $fn): void {
    try { $fn(); pass_case($name); } catch (Throwable $e) { fail_case($name, $e); }
}

$wpdb = eh7_setup_global_db();
eh7_schema($wpdb);
$version = (string)$wpdb->get_var('SELECT VERSION()');
echo "INFO mariadb_version={$version}\n";

run_case('mariadb_transaction_commit', function () use ($wpdb) {
    Transaction::run(function () use ($wpdb) {
        if ($wpdb->insert('wp_eh7_integration_probe', [
            'token' => 'commit',
            'value_int' => 1,
            'created_at' => Db::now(),
        ]) === false) throw new RuntimeException($wpdb->last_error);
    });
    if (eh7_count($wpdb, 'commit') !== 1) throw new RuntimeException('committed row missing');
});

run_case('mariadb_transaction_rollback', function () use ($wpdb) {
    try {
        Transaction::run(function () use ($wpdb) {
            if ($wpdb->insert('wp_eh7_integration_probe', [
                'token' => 'rollback',
                'value_int' => 1,
                'created_at' => Db::now(),
            ]) === false) throw new RuntimeException($wpdb->last_error);
            throw new RuntimeException('rollback-probe');
        });
    } catch (RuntimeException $e) {
        if ($e->getMessage() !== 'rollback-probe') throw $e;
    }
    if (eh7_count($wpdb, 'rollback') !== 0) throw new RuntimeException('rolled-back row persisted');
});

run_case('mariadb_savepoint_rollback', function () use ($wpdb) {
    Transaction::run(function () use ($wpdb) {
        $wpdb->insert('wp_eh7_integration_probe', ['token' => 'outer-a', 'value_int' => 1, 'created_at' => Db::now()]);
        try {
            Transaction::run(function () use ($wpdb) {
                $wpdb->insert('wp_eh7_integration_probe', ['token' => 'inner-b', 'value_int' => 1, 'created_at' => Db::now()]);
                throw new RuntimeException('savepoint-probe');
            });
        } catch (RuntimeException $e) {
            if ($e->getMessage() !== 'savepoint-probe') throw $e;
        }
        $wpdb->insert('wp_eh7_integration_probe', ['token' => 'outer-c', 'value_int' => 1, 'created_at' => Db::now()]);
    });
    if (eh7_count($wpdb, 'outer-a') !== 1 || eh7_count($wpdb, 'outer-c') !== 1 || eh7_count($wpdb, 'inner-b') !== 0) {
        throw new RuntimeException('savepoint isolation mismatch');
    }
});

$actor = new Actor(10, 10, 1, 1, [1], [], 'BM');
run_case('mariadb_idempotency_replay', function () use ($wpdb, $actor) {
    $calls = 0;
    $fn = function () use ($wpdb, &$calls) {
        $calls++;
        $wpdb->insert('wp_eh7_integration_probe', ['token' => 'idem-replay', 'value_int' => 1, 'created_at' => Db::now()]);
        return ['saved' => 1];
    };
    $first = Idempotency::run($actor, 'replay-key', 'integration.replay', $fn, ['a' => 1, 'b' => 2]);
    $second = Idempotency::run($actor, 'replay-key', 'integration.replay', $fn, ['b' => 2, 'a' => 1]);
    if ($first !== ['saved' => 1] || $second !== ['saved' => 1] || $calls !== 1 || eh7_count($wpdb, 'idem-replay') !== 1) {
        throw new RuntimeException('idempotent replay executed business callback more than once');
    }
});

run_case('mariadb_idempotency_payload_mismatch', function () use ($actor) {
    try {
        Idempotency::run($actor, 'replay-key', 'integration.replay', fn() => ['unexpected' => true], ['a' => 999]);
    } catch (DomainException $e) {
        if ($e->codeKey === 'idempotency_payload_mismatch' && $e->httpStatus === 409) return;
        throw $e;
    }
    throw new RuntimeException('payload mismatch was accepted');
});

run_case('mariadb_concurrent_idempotency_single_execution', function () use ($wpdb) {
    if (!function_exists('proc_open')) throw new RuntimeException('proc_open unavailable');
    $cmd = [PHP_BINARY, __FILE__, 'worker'];
    $spec = [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']];
    $workers = [];
    for ($i = 0; $i < 2; $i++) {
        $pipes = [];
        $process = proc_open($cmd, $spec, $pipes);
        if (!is_resource($process)) throw new RuntimeException('worker process failed to start');
        fclose($pipes[0]);
        $workers[] = [$process, $pipes];
    }
    $outputs = [];
    foreach ($workers as [$process, $pipes]) {
        $stdout = stream_get_contents($pipes[1]); fclose($pipes[1]);
        $stderr = stream_get_contents($pipes[2]); fclose($pipes[2]);
        $exit = proc_close($process);
        if ($exit !== 0) throw new RuntimeException('worker failed: '.$stderr);
        $outputs[] = json_decode($stdout, true, 512, JSON_THROW_ON_ERROR);
    }
    if (eh7_count($wpdb, 'concurrent') !== 1) throw new RuntimeException('business callback executed more than once');
    if (count(array_filter($outputs, fn($row) => ($row['out']['result'] ?? '') === 'single-execution')) !== 2) {
        throw new RuntimeException('concurrent callers did not receive stable response');
    }
});

echo ($failed ? 'FAILED' : 'PASSED')." MariaDB integration suite\n";
exit($failed ? 1 : 0);
