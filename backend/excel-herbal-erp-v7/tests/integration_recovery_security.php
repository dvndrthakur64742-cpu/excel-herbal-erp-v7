<?php
define('EH7_INTEGRATION_LIBRARY_ONLY', true);
require __DIR__.'/integration_mariadb.php';

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Schema;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Organization\DocumentVault;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\MobileAuth;

const EH7_RS_PLAINTEXT = "Excel Herbal ERP disposable recovery fixture v1\n";

$GLOBALS['eh7_rs_transients'] = [];

if (!function_exists('get_option')) {
    function get_option($name, $default = false) {
        global $wpdb;
        if (!isset($wpdb)) return $default;
        $value = $wpdb->get_var($wpdb->prepare(
            'SELECT option_value FROM '.$wpdb->prefix.'options WHERE option_name=%s LIMIT 1',
            (string)$name
        ));
        return $value === null ? $default : $value;
    }
}
if (!function_exists('get_transient')) {
    function get_transient($key) { return $GLOBALS['eh7_rs_transients'][(string)$key] ?? false; }
}
if (!function_exists('set_transient')) {
    function set_transient($key, $value, $expiration = 0) {
        $GLOBALS['eh7_rs_transients'][(string)$key] = $value;
        return true;
    }
}
if (!function_exists('delete_transient')) {
    function delete_transient($key) {
        unset($GLOBALS['eh7_rs_transients'][(string)$key]);
        return true;
    }
}
if (!function_exists('get_user_by')) {
    function get_user_by($field, $value) {
        if ((string)$field !== 'id' || (int)$value !== 501) return false;
        return (object)['ID' => 501, 'user_pass' => 'fixture-hash'];
    }
}
if (!function_exists('wp_check_password')) {
    function wp_check_password($password, $hash, $user_id = '') {
        return (string)$password === 'FixturePass!2026'
            && (string)$hash === 'fixture-hash'
            && (int)$user_id === 501;
    }
}

function rs_rebuild(Eh7IntegrationWpdb $db, array $names): void {
    $defs = Schema::definitions();
    $db->query('SET FOREIGN_KEY_CHECKS=0');
    foreach ($names as $name) {
        if (!isset($defs[$name])) throw new RuntimeException('Missing schema definition '.$name);
        if ($db->query('DROP TABLE IF EXISTS '.Db::table($name)) === false) {
            throw new RuntimeException($db->last_error);
        }
    }
    foreach ($names as $name) {
        $sql = 'CREATE TABLE '.Db::table($name).' ('.$defs[$name].') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4';
        if ($db->query($sql) === false) throw new RuntimeException('Create '.$name.' failed: '.$db->last_error);
    }
    $db->query('SET FOREIGN_KEY_CHECKS=1');
}

function rs_insert(Eh7IntegrationWpdb $db, string $table, array $row): void {
    if ($db->insert(Db::table($table), $row) === false) {
        throw new RuntimeException('Insert '.$table.' failed: '.$db->last_error);
    }
}

function rs_case(string $name, callable $fn): void {
    try {
        $fn();
        echo "PASS {$name}\n";
    } catch (Throwable $e) {
        echo "FAIL {$name}: {$e->getMessage()}\n";
        exit(1);
    }
}

function rs_auth_suite(): never {
    $db = eh7_setup_global_db();
    rs_rebuild($db, ['employees', 'mobile_sessions']);
    rs_insert($db, 'employees', [
        'id' => 10,
        'company_id' => 1,
        'employee_code' => 'SEC10',
        'wp_user_id' => 501,
        'designation_code' => 'BM',
        'assigned_branch_id' => 1,
        'full_name' => 'Disposable Security Fixture',
        'mobile' => '9876543210',
        'monthly_salary' => 1000,
        'joining_date' => '2026-01-01',
        'status' => 'active',
        'created_at' => '2026-01-01 00:00:00',
    ]);

    $serverBackup = $_SERVER;
    try {
        $tokens = null;
        rs_case('mobile_auth_login', function () use (&$tokens) {
            $tokens = MobileAuth::login('98765 43210', 'FixturePass!2026', 'CI recovery fixture', 'ci-device-1');
            if (strlen((string)($tokens['access_token'] ?? '')) !== 64) throw new RuntimeException('access token length mismatch');
            if (strlen((string)($tokens['refresh_token'] ?? '')) !== 96) throw new RuntimeException('refresh token length mismatch');
        });

        rs_case('mobile_auth_redirect_authorization', function () use (&$tokens) {
            unset($_SERVER['HTTP_AUTHORIZATION'], $_SERVER['Authorization']);
            $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] = 'Bearer '.$tokens['access_token'];
            if (MobileAuth::user(0) !== 501) throw new RuntimeException('redirect Authorization header did not resolve session');
        });

        $rotated = null;
        rs_case('mobile_auth_refresh_rotation', function () use (&$tokens, &$rotated) {
            $rotated = MobileAuth::refresh($tokens['refresh_token'], 'CI recovery fixture', 'ci-device-1');
            if (($rotated['access_token'] ?? '') === $tokens['access_token']) throw new RuntimeException('access token was not rotated');
            if (($rotated['refresh_token'] ?? '') === $tokens['refresh_token']) throw new RuntimeException('refresh token was not rotated');
        });

        rs_case('mobile_auth_old_access_revoked', function () use (&$tokens) {
            unset($_SERVER['REDIRECT_HTTP_AUTHORIZATION'], $_SERVER['Authorization']);
            $_SERVER['HTTP_AUTHORIZATION'] = 'Bearer '.$tokens['access_token'];
            if (MobileAuth::user(0) !== 0) throw new RuntimeException('old access token remained valid after refresh rotation');
        });

        rs_case('mobile_auth_direct_authorization', function () use (&$rotated) {
            unset($_SERVER['HTTP_AUTHORIZATION'], $_SERVER['REDIRECT_HTTP_AUTHORIZATION']);
            $_SERVER['Authorization'] = 'Bearer '.$rotated['access_token'];
            if (MobileAuth::user(0) !== 501) throw new RuntimeException('direct Authorization header did not resolve rotated session');
        });

        rs_case('mobile_auth_logout_revocation', function () use (&$rotated) {
            unset($_SERVER['HTTP_AUTHORIZATION'], $_SERVER['REDIRECT_HTTP_AUTHORIZATION']);
            $_SERVER['Authorization'] = 'Bearer '.$rotated['access_token'];
            $out = MobileAuth::logout();
            if (($out['logged_out'] ?? false) !== true) throw new RuntimeException('logout response mismatch');
            if (MobileAuth::user(0) !== 0) throw new RuntimeException('logged-out access token remained valid');
        });
    } finally {
        $_SERVER = $serverBackup;
    }

    echo "PASSED recovery security auth suite\n";
    exit(0);
}

function rs_create_options(Eh7IntegrationWpdb $db): void {
    if ($db->query('DROP TABLE IF EXISTS '.$db->prefix.'options') === false) throw new RuntimeException($db->last_error);
    $sql = 'CREATE TABLE '.$db->prefix.'options ('.
        'option_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,'.
        'option_name VARCHAR(191) NOT NULL,'.
        'option_value LONGTEXT NOT NULL,'.
        'autoload VARCHAR(20) NOT NULL DEFAULT \'no\','.
        'PRIMARY KEY(option_id),UNIQUE KEY option_name(option_name)'.
        ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4';
    if ($db->query($sql) === false) throw new RuntimeException($db->last_error);
}

function rs_seed_document_recovery(): never {
    if (!function_exists('openssl_encrypt') || !function_exists('openssl_decrypt')) {
        fwrite(STDERR, "OpenSSL is unavailable\n");
        exit(1);
    }

    $db = eh7_setup_global_db();
    rs_rebuild($db, ['private_documents', 'hr_candidates', 'hr_candidate_documents']);
    rs_create_options($db);

    $key = random_bytes(32);
    if ($db->insert($db->prefix.'options', [
        'option_name' => 'eh7_document_key',
        'option_value' => base64_encode($key),
        'autoload' => 'no',
    ]) === false) throw new RuntimeException('Option seed failed: '.$db->last_error);

    $iv = random_bytes(12);
    $tag = '';
    $cipher = openssl_encrypt(EH7_RS_PLAINTEXT, 'aes-256-gcm', $key, OPENSSL_RAW_DATA, $iv, $tag, 'eh7-document-v1');
    if ($cipher === false) throw new RuntimeException('Fixture encryption failed');

    rs_insert($db, 'private_documents', [
        'id' => 77,
        'filename' => 'recovery-fixture.pdf',
        'mime_type' => 'application/pdf',
        'payload' => base64_encode($cipher),
        'iv' => base64_encode($iv),
        'tag' => base64_encode($tag),
        'sha256' => hash('sha256', EH7_RS_PLAINTEXT),
        'created_at' => '2026-09-18 00:00:00',
    ]);
    rs_insert($db, 'hr_candidates', [
        'id' => 44,
        'company_id' => 1,
        'candidate_code' => 'RECOVERY-44',
        'branch_id' => 1,
        'full_name' => 'Disposable Recovery Fixture',
        'proposed_designation_code' => 'BM',
        'offered_monthly_salary' => 1000,
        'status' => 'registered',
        'created_by' => 10,
        'created_at' => '2026-09-18 00:00:00',
    ]);
    rs_insert($db, 'hr_candidate_documents', [
        'id' => 55,
        'company_id' => 1,
        'candidate_id' => 44,
        'attachment_id' => 0,
        'private_file_id' => 77,
        'document_type' => 'ci_recovery_fixture',
        'title' => 'Disposable recovery fixture',
        'status' => 'active',
        'uploaded_by' => 10,
        'created_at' => '2026-09-18 00:00:00',
    ]);

    $actor = new Actor(501, 10, 1, 1, [1], [Capabilities::HR_VIEW, Capabilities::HR_DOCUMENT_DOWNLOAD], 'SYSADMIN');
    rs_case('document_recovery_seed_readable', function () use ($actor) {
        $out = DocumentVault::download($actor, 'candidate', 44, 55);
        if (($out['bytes'] ?? '') !== EH7_RS_PLAINTEXT) throw new RuntimeException('seed document plaintext mismatch');
    });

    echo "PASSED document recovery seed suite\n";
    exit(0);
}

function rs_verify_document_recovery(): never {
    $db = eh7_setup_global_db();
    $actor = new Actor(501, 10, 1, 1, [1], [Capabilities::HR_VIEW, Capabilities::HR_DOCUMENT_DOWNLOAD], 'SYSADMIN');

    rs_case('document_restore_matching_key', function () use ($actor) {
        $out = DocumentVault::download($actor, 'candidate', 44, 55);
        if (($out['bytes'] ?? '') !== EH7_RS_PLAINTEXT) throw new RuntimeException('restored plaintext mismatch');
        if (($out['filename'] ?? '') !== 'recovery-fixture.pdf') throw new RuntimeException('restored filename mismatch');
    });

    rs_case('document_restore_wrong_key_rejected', function () use ($db, $actor) {
        $original = (string)get_option('eh7_document_key', '');
        if ($original === '') throw new RuntimeException('restored document key missing');
        $db->update($db->prefix.'options', ['option_value' => base64_encode(random_bytes(32))], ['option_name' => 'eh7_document_key']);
        try {
            DocumentVault::download($actor, 'candidate', 44, 55);
        } catch (DomainException $e) {
            if ($e->codeKey === 'document_integrity_failed') {
                $db->update($db->prefix.'options', ['option_value' => $original], ['option_name' => 'eh7_document_key']);
                return;
            }
            $db->update($db->prefix.'options', ['option_value' => $original], ['option_name' => 'eh7_document_key']);
            throw $e;
        }
        $db->update($db->prefix.'options', ['option_value' => $original], ['option_name' => 'eh7_document_key']);
        throw new RuntimeException('wrong key unexpectedly decrypted document');
    });

    rs_case('document_inactive_rejected', function () use ($db, $actor) {
        $db->update(Db::table('hr_candidate_documents'), ['status' => 'inactive'], ['id' => 55]);
        try {
            DocumentVault::download($actor, 'candidate', 44, 55);
        } catch (DomainException $e) {
            $db->update(Db::table('hr_candidate_documents'), ['status' => 'active'], ['id' => 55]);
            if ($e->codeKey === 'document_not_found') return;
            throw $e;
        }
        $db->update(Db::table('hr_candidate_documents'), ['status' => 'active'], ['id' => 55]);
        throw new RuntimeException('inactive document remained downloadable');
    });

    echo "PASSED document recovery restore suite\n";
    exit(0);
}

$mode = (string)($argv[1] ?? '');
match ($mode) {
    'auth' => rs_auth_suite(),
    'seed-document-recovery' => rs_seed_document_recovery(),
    'verify-document-recovery' => rs_verify_document_recovery(),
    default => throw new RuntimeException('Usage: integration_recovery_security.php auth|seed-document-recovery|verify-document-recovery'),
};
