<?php
namespace ExcelHerbal\ERP7\Core;

/**
 * Review-only unified plugin frontend. Keeps the existing homepage and older
 * frontend installer untouched until a separately approved migration.
 *
 * The bundled Dart application is deliberately compiled for the Office API.
 * Fail closed on other hosts rather than sending UAT login details to Office.
 */
final class IntegratedFrontend
{
    public const PREVIEW_PATH = '/erp/';
    private const OFFICE_HOST = 'office.excelherbal.in';
    private const SHELL_FILE = 'web/eh7-app-shell.txt';

    public static function boot(): void
    {
        add_action('template_redirect', [self::class, 'maybeServe'], 0);
        add_action('admin_menu', [self::class, 'adminMenu']);
    }

    public static function previewUrl(): string
    {
        return home_url(self::PREVIEW_PATH);
    }

    public static function isPreviewRequest(string $requestUri, string $homeUrl): bool
    {
        $requested = parse_url($requestUri, PHP_URL_PATH);
        $preview = parse_url(rtrim($homeUrl, '/') . self::PREVIEW_PATH, PHP_URL_PATH);
        if (!is_string($requested) || !is_string($preview)) {
            return false;
        }
        return rtrim($requested, '/') === rtrim($preview, '/');
    }

    public static function isOfficeHost(string $homeUrl, string $hostHeader): bool
    {
        $homeHost = strtolower((string) parse_url($homeUrl, PHP_URL_HOST));
        $requestHost = strtolower((string) parse_url('https://' . $hostHeader, PHP_URL_HOST));
        return $homeHost === self::OFFICE_HOST && $requestHost === self::OFFICE_HOST;
    }

    public static function renderShell(string $html, string $assetBaseUrl): string
    {
        // This substitution affects only the built HTML asset base; it does
        // not patch Dart, change API host policy or grant any permissions.
        $placeholder = '__EH7_PLUGIN_ASSET_BASE__';
        if (substr_count($html, $placeholder) !== 1) {
            throw new \RuntimeException('ERP Web shell asset-base marker is missing or repeated.');
        }
        return str_replace($placeholder, esc_url($assetBaseUrl), $html);
    }

    public static function maybeServe(): void
    {
        if ((function_exists('is_admin') && is_admin()) ||
            (function_exists('wp_doing_ajax') && wp_doing_ajax())) {
            return;
        }
        $requestUri = (string) ($_SERVER['REQUEST_URI'] ?? '');
        $homeUrl = home_url('/');
        if (!self::isPreviewRequest($requestUri, $homeUrl)) {
            return;
        }

        $method = strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? 'GET'));
        if ($method !== 'GET' && $method !== 'HEAD') {
            status_header(405);
            header('Allow: GET, HEAD');
            header('Content-Type: text/plain; charset=utf-8');
            if ($method !== 'HEAD') {
                echo 'The ERP preview supports GET requests only.';
            }
            exit;
        }
        $hostHeader = (string) ($_SERVER['HTTP_HOST'] ?? '');
        if (!self::isOfficeHost($homeUrl, $hostHeader)) {
            status_header(503);
            nocache_headers();
            header('Content-Type: text/plain; charset=utf-8');
            if ($method !== 'HEAD') {
                echo 'This reviewed Flutter build targets the Office ERP API only. '
                    . 'Use a separately compiled, source-pinned UAT frontend for test hosts.';
            }
            exit;
        }

        $path = EH7_DIR . self::SHELL_FILE;
        if (!is_file($path) || !is_readable($path)) {
            status_header(503);
            nocache_headers();
            header('Content-Type: text/plain; charset=utf-8');
            if ($method !== 'HEAD') {
                echo 'The ERP frontend assets are missing. Contact the ERP administrator.';
            }
            exit;
        }
        try {
            $html = file_get_contents($path);
            if ($html === false) {
                throw new \RuntimeException('Cannot read ERP frontend HTML.');
            }
            $html = self::renderShell(
                $html,
                plugins_url('web/', EH7_DIR . 'excel-herbal-erp-v7.php')
            );
        } catch (\Throwable $error) {
            status_header(503);
            nocache_headers();
            header('Content-Type: text/plain; charset=utf-8');
            if ($method !== 'HEAD') {
                echo 'The ERP frontend could not load. Contact the ERP administrator.';
            }
            exit;
        }
        status_header(200);
        nocache_headers();
        header('X-Content-Type-Options: nosniff');
        header('X-Robots-Tag: noindex, nofollow, noarchive');
        header('Content-Type: text/html; charset=utf-8');
        if ($method !== 'HEAD') {
            echo $html;
        }
        exit;
    }

    public static function adminMenu(): void
    {
        add_management_page(
            'Excel Herbal ERP Web Preview',
            'ERP Web Preview',
            'manage_options',
            'eh7-erp-web-preview',
            [self::class, 'adminPage']
        );
    }

    public static function adminPage(): void
    {
        if (!current_user_can('manage_options')) {
            wp_die('This page requires administrator access.');
        }
        $url = self::previewUrl();
        echo '<div class="wrap"><h1>Excel Herbal ERP — Integrated Web Preview</h1>';
        echo '<p>The reviewed Flutter interface and PHP backend are bundled in one plugin. '
            . 'The existing homepage and older UI installer remain unchanged.</p>';
        echo '<p><a class="button button-primary" target="_blank" rel="noopener noreferrer" href="'
            . esc_url($url) . '">Open ERP Preview</a></p>';
        echo '<p><strong>Release status:</strong> QA REVIEW ONLY. '
            . 'Do not switch the homepage or disable a frontend installer until '
            . 'source-pinned role testing, hosted backup/restore and rollback are complete.</p>';
        echo '</div>';
    }
}
