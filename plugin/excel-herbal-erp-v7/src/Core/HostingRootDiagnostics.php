<?php
namespace ExcelHerbal\ERP7\Core;

/**
 * Administrator-only, read-only diagnostic for ERP hostname root routing.
 *
 * Never prints document-root/ABSPATH paths, configuration contents, tokens,
 * file contents, or rewrite rules. Never modifies files, WordPress options,
 * cache, or hosting settings.
 */
final class HostingRootDiagnostics
{
    private const FILES = ['index.html', 'index.htm', 'index.php', '.htaccess', 'web.config'];

    public static function boot(): void
    {
        add_action('admin_menu', [self::class, 'registerMenu']);
    }

    public static function registerMenu(): void
    {
        add_management_page(
            'ERP Hosting Root Diagnostics',
            'ERP Hosting Diagnostics',
            'manage_options',
            'eh7-host-root-diagnostics',
            [self::class, 'adminPage']
        );
    }

    /**
     * Read-only, deterministic inspection callable by isolated PHP tests.
     *
     * @return array<string,mixed>
     */
    public static function inspect(string $wordpressRoot, ?string $httpDocumentRoot): array
    {
        $wpRoot = self::directory($wordpressRoot);
        $docRoot = $httpDocumentRoot !== null && trim($httpDocumentRoot) !== ''
            ? self::directory($httpDocumentRoot) : null;
        return [
            'wordpress_root_available' => $wpRoot !== null,
            'http_document_root_available' => $docRoot !== null,
            'same_directory' => $wpRoot !== null && $docRoot !== null
                ? $wpRoot === $docRoot : null,
            'wordpress_root' => self::inspectDirectory($wpRoot),
            'http_document_root' => self::inspectDirectory($docRoot),
            'content_or_configuration_modified' => false,
        ];
    }

    private static function directory(string $path): ?string
    {
        if ($path === '' || !is_dir($path)) {
            return null;
        }
        $resolved = realpath($path);
        return $resolved !== false ? rtrim($resolved, DIRECTORY_SEPARATOR) : null;
    }

    /** @return array<string,array<string,mixed>> */
    private static function inspectDirectory(?string $root): array
    {
        $items = [];
        foreach (self::FILES as $name) {
            $items[$name] = self::fileMetadata($root, $name);
        }
        return $items;
    }

    /** @return array<string,mixed> */
    private static function fileMetadata(?string $root, string $name): array
    {
        $empty = [
            'present' => false,
            'readable' => false,
            'symbolic_link' => false,
            'size_bytes' => null,
            'modified_utc' => null,
            'mentions_old_eh7_flutter_bundle' => null,
            'has_rewrite_rules' => null,
            'has_directory_index' => null,
        ];
        if ($root === null) {
            return $empty;
        }
        $candidate = $root . DIRECTORY_SEPARATOR . $name;
        if (is_link($candidate)) {
            // Do not follow symlinks out of the configured document root.
            $empty['present'] = true;
            $empty['symbolic_link'] = true;
            return $empty;
        }
        if (!is_file($candidate)) {
            return $empty;
        }
        $empty['present'] = true;
        $empty['readable'] = is_readable($candidate);
        $size = filesize($candidate);
        $mtime = filemtime($candidate);
        $empty['size_bytes'] = $size !== false ? $size : null;
        $empty['modified_utc'] = $mtime !== false ? gmdate('Y-m-d H:i:s', $mtime) : null;

        // Only inspect public-index or rewrite files. Return booleans only,
        // NEVER the content, matching line, absolute path, or a URL.
        if ($empty['readable'] && $size !== false && $size <= 65536 &&
            in_array($name, ['index.html', 'index.htm', '.htaccess', 'web.config'], true)) {
            $data = file_get_contents($candidate, false, null, 0, 65536);
            if (is_string($data)) {
                $empty['mentions_old_eh7_flutter_bundle'] =
                    preg_match('/eh7-web-[a-zA-Z0-9_-]+/', $data) === 1;
                if ($name === '.htaccess' || $name === 'web.config') {
                    $empty['has_rewrite_rules'] = preg_match(
                        '/\b(?:RewriteRule|RewriteCond|<rewrite\b|<rule\b)/i',
                        $data
                    ) === 1;
                    $empty['has_directory_index'] = preg_match(
                        '/\b(?:DirectoryIndex|defaultDocument)\b/i', $data
                    ) === 1;
                }
            }
        }
        return $empty;
    }

    /** Render no evidence without explicit WordPress administrator capability. */
    public static function adminPage(): void
    {
        if (!current_user_can('manage_options')) {
            wp_die('This diagnostic requires WordPress administrator access.');
        }
        $result = self::inspect(
            defined('ABSPATH') ? (string) ABSPATH : '',
            isset($_SERVER['DOCUMENT_ROOT']) ? (string) $_SERVER['DOCUMENT_ROOT'] : null
        );
        echo '<div class="wrap"><h1>ERP Hosting Root Diagnostics (Read-only)</h1>';
        echo '<p>Metadata only: this page does not modify files, rules, users, cache, or ERP data. '
            . 'It never displays server paths, .htaccess contents or credentials.</p>';
        echo '<p><strong>WordPress root available:</strong> '
            . ($result['wordpress_root_available'] ? 'Yes' : 'No') . '</p>';
        echo '<p><strong>HTTP document root available:</strong> '
            . ($result['http_document_root_available'] ? 'Yes' : 'No') . '</p>';
        $same = $result['same_directory'];
        echo '<p><strong>Document root matches WordPress root:</strong> '
            . ($same === null ? 'Unknown' : ($same ? 'Yes' : 'No')) . '</p>';
        foreach ([
            'wordpress_root' => 'WordPress installation root',
            'http_document_root' => 'Web server document root',
        ] as $key => $heading) {
            echo '<h2>' . esc_html($heading) . '</h2>';
            echo '<table class="widefat striped"><thead><tr><th>Filename</th>'
                . '<th>Present</th><th>Readable</th><th>Bytes</th>'
                . '<th>Modified (UTC)</th><th>Old ERP web reference?</th>'
                . '<th>Rewrite present?</th><th>DirectoryIndex present?</th></tr></thead><tbody>';
            foreach ($result[$key] as $file => $meta) {
                $flag = static function ($value): string {
                    return $value === null ? 'Not inspected' : ($value ? 'Yes' : 'No');
                };
                echo '<tr><td>' . esc_html($file) . '</td>'
                    . '<td>' . ($meta['symbolic_link'] ? 'Symlink (not followed)'
                        : ($meta['present'] ? 'Yes' : 'No')) . '</td>'
                    . '<td>' . $flag($meta['readable']) . '</td>'
                    . '<td>' . esc_html((string) ($meta['size_bytes'] ?? '—')) . '</td>'
                    . '<td>' . esc_html((string) ($meta['modified_utc'] ?? '—')) . '</td>'
                    . '<td>' . $flag($meta['mentions_old_eh7_flutter_bundle']) . '</td>'
                    . '<td>' . $flag($meta['has_rewrite_rules']) . '</td>'
                    . '<td>' . $flag($meta['has_directory_index']) . '</td></tr>';
            }
            echo '</tbody></table>';
        }
        echo '<p><strong>Next release gate:</strong> Confirm hosted backup and restore, '
            . 'identify root interception from hosting configuration, then rerun the anonymous '
            . 'source-pinned HTTP preflight and real staff-role UAT. '
            . 'A positive file flag does not prove which rewrite rule caused the issue.</p>';
        echo '</div>';
    }
}
