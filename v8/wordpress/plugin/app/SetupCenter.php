<?php
namespace ExcelHerbal\ERP8;

final class SetupCenter {
    public static function boot(): void {
        add_action('admin_menu', [self::class, 'menu']);
        add_action('admin_post_ehv8_install_preview', [self::class, 'installPreview']);
    }

    public static function menu(): void {
        add_menu_page(
            'Excel Herbal ERP V8 — Setup & Health',
            'Excel Herbal ERP V8',
            'manage_options',
            'excel-herbal-erp-v8',
            [self::class, 'render'],
            'dashicons-chart-area',
            3
        );
    }

    public static function legacySetupPresent(): bool {
        foreach ((array) get_option('active_plugins', []) as $entry) {
            if (str_ends_with((string) $entry, 'excel-herbal-erp-v7-setup-assistant/excel-herbal-erp-v7-setup-assistant.php')) {
                return true;
            }
        }
        return false;
    }

    public static function render(): void {
        if (!current_user_can('manage_options')) wp_die('Administrator access required.');
        $schemaInstalled = (string) get_option('eh7_schema_version', '');
        $schemaExpected = \ExcelHerbal\ERP7\Database\Schema::VERSION;
        $uploads = wp_upload_dir();
        $root = empty($uploads['error']) ? rtrim((string)$uploads['basedir'], '/\\') . '/eh7-flutter-web' : '';
        $webPresent = $root !== '' && is_file($root . '/main.dart.js');
        $webHead = $root !== '' && is_file($root . '/EH7-SOURCE-HEAD.txt')
            ? trim((string)file_get_contents($root . '/EH7-SOURCE-HEAD.txt')) : 'unavailable';
        $bundled = BundledPreviewInstaller::canInstall();
        $hardening = \ExcelHerbal\ERP7\Administration\Environment::hostHardeningStatus();
        $safe = $schemaExpected === $schemaInstalled && $hardening['status'] === 'passed';
        echo '<div class="wrap"><h1>Excel Herbal ERP V8 — Unified Setup</h1>';
        echo '<p>One WordPress plugin for the existing ERP business database and its read-only V8 web preview. Existing employee, stock, sales, accounting, and attendance records remain in place.</p>';
        if (isset($_GET['ehv8_result'])) {
            $value = sanitize_key((string) wp_unslash($_GET['ehv8_result']));
            echo '<div class="notice ' . ($value === 'success' ? 'notice-success' : 'notice-error') . '"><p>';
            echo $value === 'success' ? 'Certified read-only V8 web preview installed and backed up.' : 'Preview deployment was blocked. Review the diagnostic below.';
            echo '</p></div>';
        }
        $rows = [
            'Staging environment' => \ExcelHerbal\ERP7\Administration\Environment::type(),
            'Main plugin version' => EHV8_VERSION,
            'Certified build commit' => defined('EH7_SOURCE_HEAD') ? (string)EH7_SOURCE_HEAD : 'unknown',
            'Existing database schema' => $schemaInstalled,
            'Required core schema' => $schemaExpected,
            'WordPress staging hardening' => (string)$hardening['status'],
            'Web runtime present' => $webPresent ? 'Yes' : 'No',
            'Live web source' => $webHead,
            'Bundled preview' => $bundled ? 'Ready for staged installation' : 'Not included',
            'Old Setup Assistant' => self::legacySetupPresent() ? 'Installed and active — remove only after V8 is verified' : 'Not active',
        ];
        echo '<table class="widefat striped" style="max-width:880px"><tbody>';
        foreach ($rows as $key => $value) {
            echo '<tr><th scope="row" style="width:300px">' . esc_html($key) . '</th><td>' . esc_html((string)$value) . '</td></tr>';
        }
        echo '</tbody></table>';
        $diag = (array)get_option('ehv8_last_preview_deploy', []);
        if (!empty($diag['message'])) {
            echo '<p><strong>Last preview operation:</strong> ' . esc_html((string)$diag['message']) . '</p>';
        }
        echo '<h2>V8 Read-Only Desktop Preview</h2>';
        echo '<p>Installs only the separately certified bundled Flutter files, preserving the existing web runtime in a rollback directory. It does not post transactions or change finance tables.</p>';
        if ($safe && $bundled) {
            echo '<form method="post" action="' . esc_url(admin_url('admin-post.php')) . '">';
            echo '<input type="hidden" name="action" value="ehv8_install_preview">';
            wp_nonce_field('ehv8_install_preview');
            submit_button('Install Bundled V8 Read-Only Web Preview', 'primary', 'submit', false);
            echo '</form>';
        } else {
            echo '<p><strong>Blocked:</strong> database schema, WordPress staging hardening, or certified bundled web files are not ready.</p>';
        }
        echo '<p><a href="' . esc_url(home_url('/')) . '" target="_blank" rel="noopener noreferrer">Open ERP Desktop</a>';
        echo ' · <a href="' . esc_url(admin_url('tools.php?page=eh7-uat-web-deploy')) . '">Advanced Certified Web Deployment</a></p>';
        echo '<p><strong>Migration order:</strong> install V8 ZIP without activating; deactivate old V7 Core; activate V8; verify all menus and REST; install bundled preview; only then delete old plugins after backup validation.</p>';
        echo '</div>';
    }

    public static function installPreview(): void {
        if (!current_user_can('manage_options')) wp_die('Administrator access required.');
        check_admin_referer('ehv8_install_preview');
        try {
            $result = BundledPreviewInstaller::install();
            update_option('ehv8_last_preview_deploy', [
                'ok' => true,
                'source_head' => $result['source_head'],
                'main_sha256' => $result['main_sha256'],
                'rollback' => $result['rollback'],
                'message' => 'Verified staging preview installed',
                'installed_at' => gmdate('c'),
                'actor_wp_user_id' => get_current_user_id(),
            ], false);
            wp_safe_redirect(admin_url('admin.php?page=excel-herbal-erp-v8&ehv8_result=success'));
        } catch (\Throwable $e) {
            update_option('ehv8_last_preview_deploy', [
                'ok' => false,
                'message' => substr($e->getMessage(), 0, 350),
                'installed_at' => gmdate('c'),
                'actor_wp_user_id' => get_current_user_id(),
            ], false);
            wp_safe_redirect(admin_url('admin.php?page=excel-herbal-erp-v8&ehv8_result=failed'));
        }
        exit;
    }
}
