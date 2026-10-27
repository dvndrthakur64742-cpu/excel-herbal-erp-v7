<?php
namespace ExcelHerbal\ERP8;

/**
 * Display the verified Flutter frontend through a small accessible root page.
 * Never route to an unverified web bundle or modify WordPress business data.
 */
final class FrontendShell {
    public static function boot(): void {
        // Legacy Setup Assistant may still be installed for rollback.
        // Only the already-verified unified V8 plugin claims the staging root.
        add_action('template_redirect',[self::class,'render'], -1000);
    }

    public static function html(string $url): string {
        $safe=htmlspecialchars($url,ENT_QUOTES|ENT_SUBSTITUTE,'UTF-8');
        return '<!doctype html><html lang="en"><head>'
            .'<meta charset="utf-8">'
            .'<meta name="viewport" content="width=device-width,initial-scale=1">'
            .'<meta name="robots" content="noindex,nofollow,noarchive">'
            .'<meta name="theme-color" content="#0B8F48">'
            .'<title>Excel Herbal ERP V8</title>'
            .'<style>html,body{margin:0;width:100%;height:100%;background:#fff}'
            .'iframe{width:100%;height:100%;border:0;display:block}</style>'
            .'</head><body><main aria-label="Excel Herbal ERP V8 workspace">'
            .'<iframe src="'.$safe.'" title="Excel Herbal ERP V8 Desktop"'
            .' loading="eager" referrerpolicy="same-origin"></iframe>'
            .'<noscript><p>JavaScript is required to open Excel Herbal ERP.</p></noscript>'
            .'</main></body></html>';
    }

    public static function render(): void {
        if (is_admin() || wp_doing_ajax() || !is_front_page()
            || (function_exists('is_feed') && is_feed())
            || (function_exists('is_preview') && is_preview())) return;
        if (!defined('EH7_SOURCE_HEAD')
            || !preg_match('/^[a-f0-9]{40}$/',(string)EH7_SOURCE_HEAD)) return;
        if (function_exists('wp_get_environment_type')
            && wp_get_environment_type()!=='staging') return;
        if (strtolower((string)parse_url((string)home_url('/'),PHP_URL_HOST))
            !=='office.excelherbal.in') return;
        if ((string)get_option('eh7_schema_version','')
            !== \ExcelHerbal\ERP7\Database\Schema::VERSION) return;
        $uploads=wp_upload_dir();
        if (!empty($uploads['error'])||empty($uploads['basedir'])
            ||empty($uploads['baseurl'])) return;
        $path=rtrim((string)$uploads['basedir'],'/\\').'/eh7-flutter-web';
        if (!is_file($path.'/index.html')||!is_file($path.'/main.dart.js')
            ||!is_file($path.'/EH7-SOURCE-HEAD.txt')) return;
        $head=trim((string)file_get_contents($path.'/EH7-SOURCE-HEAD.txt'));
        if (!hash_equals((string)EH7_SOURCE_HEAD,$head)) return;
        // WordPress-origin uploads directory only, no remote URL input.
        $url=rtrim((string)$uploads['baseurl'],'/').'/eh7-flutter-web/index.html'
            .'?eh8v='.rawurlencode($head);
        if (!headers_sent()) {
            nocache_headers();
            header('Content-Type: text/html; charset=UTF-8');
            header('X-Robots-Tag: noindex, nofollow, noarchive',true);
        }
        echo self::html($url);
        exit;
    }
}
