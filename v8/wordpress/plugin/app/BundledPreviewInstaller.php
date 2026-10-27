<?php
namespace ExcelHerbal\ERP8;

/**
 * Installs only certified read-only Flutter web bytes from inside the V8 plugin.
 * No schema, ledger, sales, warehouse, payroll or transaction writes.
 */
final class BundledPreviewInstaller {
    public static function canInstall(): bool {
        $root = defined('EHV8_ROOT') ? EHV8_ROOT . 'bundled-web' : '';
        return $root !== '' && is_file($root . '/SHA256SUMS.txt')
            && is_file($root . '/index.html') && is_file($root . '/main.dart.js')
            && is_file($root . '/flutter_bootstrap.js') && is_file($root . '/.last_build_id');
    }

    /** @return array<string,string|null> */
    public static function install(): array {
        if (!current_user_can('manage_options')) throw new \RuntimeException('Administrator capability required.');
        $environment = \ExcelHerbal\ERP7\Administration\Environment::type();
        $host = strtolower((string)parse_url((string)home_url('/'), PHP_URL_HOST));
        $hardened = \ExcelHerbal\ERP7\Administration\Environment::hostHardeningStatus();
        if ($environment !== 'staging' || $host !== 'office.excelherbal.in' || $hardened['status'] !== 'passed') {
            throw new \RuntimeException('Bundled preview is restricted to the approved hardened Office staging host.');
        }
        if (\ehv8_legacy_core_active()) throw new \RuntimeException('Old V7 Core is still active.');
        if ((string)get_option('eh7_schema_version', '') !== \ExcelHerbal\ERP7\Database\Schema::VERSION) {
            throw new \RuntimeException('ERP schema does not match the approved existing database.');
        }
        if (!self::canInstall()) throw new \RuntimeException('Bundled preview is missing.');
        $source = rtrim(EHV8_ROOT . 'bundled-web', '/\\');
        $head = defined('EH7_SOURCE_HEAD') ? (string)EH7_SOURCE_HEAD : '';
        if (!preg_match('/^[a-f0-9]{40}$/', $head)) throw new \RuntimeException('Certified source commit marker missing.');
        if (trim((string)file_get_contents($source . '/.last_build_id')) !== $head) {
            throw new \RuntimeException('Bundled preview does not match the running V8 core Git commit.');
        }
        $files = self::certifiedFiles($source);
        $uploads = wp_upload_dir();
        if (!empty($uploads['error'])) throw new \RuntimeException((string)$uploads['error']);
        $base = rtrim((string)$uploads['basedir'], '/\\');
        $target = $base . '/eh7-flutter-web';
        $random = bin2hex(random_bytes(8));
        $stage = $base . '/eh7-flutter-web.__v8new_' . $random;
        $backup = $base . '/eh7-flutter-web.__rollback_' . gmdate('Ymd_His') . '_' . $random;
        if (!wp_mkdir_p($stage)) throw new \RuntimeException('Could not create web staging folder.');
        try {
            foreach ($files as $relative => $expected) {
                $destination = $stage . '/' . $relative;
                if (!wp_mkdir_p(dirname($destination)) || !copy($source . '/' . $relative, $destination)) {
                    throw new \RuntimeException('Unable to stage web file: ' . $relative);
                }
                if (!hash_equals($expected, strtolower((string)hash_file('sha256', $destination)))) {
                    throw new \RuntimeException('Copied web file changed: ' . $relative);
                }
            }
            if (!copy($source . '/SHA256SUMS.txt', $stage . '/SHA256SUMS.txt')) {
                throw new \RuntimeException('Could not copy preview manifest.');
            }
            if (file_put_contents($stage . '/EH7-SOURCE-HEAD.txt', $head . "\n", LOCK_EX) === false) {
                throw new \RuntimeException('Source marker write failed.');
            }
            self::writeCachePolicy($stage);
            $mainHash = strtolower((string)hash_file('sha256', $stage . '/main.dart.js'));
            $manifestHash = strtolower((string)hash_file('sha256', $stage . '/SHA256SUMS.txt'));
            $backupName = null;
            if (is_dir($target)) {
                if (!rename($target, $backup)) throw new \RuntimeException('Rollback copy of current web runtime failed.');
                $backupName = basename($backup);
            }
            if (!rename($stage, $target)) {
                if ($backupName !== null) @rename($backup, $target);
                throw new \RuntimeException('Unable to activate bundled preview; old runtime restored.');
            }
            update_option('eh7_setup_web_bundle_uploaded_at', current_time('mysql'), false);
            return [
                'source_head' => $head,
                'main_sha256' => $mainHash,
                'manifest_sha256' => $manifestHash,
                'rollback' => $backupName,
            ];
        } finally {
            if (is_dir($stage)) self::removeTree($stage);
        }
    }

    /** @return array<string,string> */
    private static function certifiedFiles(string $root): array {
        $text = file_get_contents($root . '/SHA256SUMS.txt');
        if ($text === false || trim($text) === '') throw new \RuntimeException('Bundled manifest is empty.');
        $files = [];
        foreach (preg_split('/\r?\n/', trim($text)) as $row) {
            if (!preg_match('/^([a-f0-9]{64})  (.+)$/', $row, $parts)) {
                throw new \RuntimeException('Invalid source manifest entry.');
            }
            $hash = $parts[1];
            $relative = $parts[2];
            if (!self::safePath($relative) || isset($files[$relative])) {
                throw new \RuntimeException('Unsafe or duplicate preview path.');
            }
            $path = $root . '/' . $relative;
            if (is_link($path) || !is_file($path) || !hash_equals($hash, strtolower((string)hash_file('sha256', $path)))) {
                throw new \RuntimeException('Bundled preview SHA-256 failed: ' . $relative);
            }
            $files[$relative] = $hash;
        }
        foreach (['index.html', 'main.dart.js', 'flutter_bootstrap.js', '.last_build_id'] as $required) {
            if (!isset($files[$required])) throw new \RuntimeException('Missing mandatory certified web file: ' . $required);
        }
        return $files;
    }

    public static function safePath(string $path): bool {
        if ($path === '' || str_contains($path, "\0") || str_contains($path, '\\')
            || str_starts_with($path, '/') || preg_match('/^[A-Za-z]:/', $path)) return false;
        foreach (explode('/', $path) as $part) {
            if ($part === '' || $part === '.' || $part === '..') return false;
        }
        return true;
    }

    private static function writeCachePolicy(string $root): void {
        $rules = "<IfModule mod_headers.c>\n"
            . "<FilesMatch \"^(index\\.html|flutter_bootstrap\\.js|main\\.dart\\.js|flutter_service_worker\\.js|version\\.json)$\">\n"
            . "Header set Cache-Control \"no-cache, no-store, must-revalidate, max-age=0\"\n"
            . "</FilesMatch>\n</IfModule>\n";
        if (file_put_contents($root . '/.htaccess', $rules, LOCK_EX) === false) {
            throw new \RuntimeException('Could not stage web cache policy.');
        }
    }

    private static function removeTree(string $root): void {
        $it = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($root, \FilesystemIterator::SKIP_DOTS),
            \RecursiveIteratorIterator::CHILD_FIRST
        );
        foreach ($it as $file) {
            if ($file->isDir()) @rmdir($file->getPathname());
            else @unlink($file->getPathname());
        }
        @rmdir($root);
    }
}
