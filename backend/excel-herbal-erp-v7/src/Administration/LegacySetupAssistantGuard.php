<?php
namespace ExcelHerbal\ERP7\Administration;

/**
 * Keep the legacy Setup Assistant from competing with the current ERP workflows.
 *
 * The companion assistant remains installed for old-package safety/migration
 * purposes, but once the current backend is active its write UI must not be
 * presented as an editable administration surface.
 */
final class LegacySetupAssistantGuard{
    private const PAGE='eh7-setup-assistant';

    public static function boot():void{
        if(!is_admin()||!defined('EH7_VERSION')||version_compare((string)EH7_VERSION,'7.3.4','<'))return;
        add_action('admin_menu',[self::class,'hideLegacyMenu'],PHP_INT_MAX);
        add_action('admin_init',[self::class,'redirectLegacyPage'],1);
    }

    public static function hideLegacyMenu():void{
        remove_menu_page(self::PAGE);
        remove_submenu_page('tools.php',self::PAGE);
        remove_submenu_page('options-general.php',self::PAGE);
    }

    public static function redirectLegacyPage():void{
        if(!current_user_can('manage_options')||wp_doing_ajax())return;
        $page=isset($_GET['page'])?sanitize_key(wp_unslash((string)$_GET['page'])):'';
        if($page!==self::PAGE)return;

        wp_safe_redirect(home_url('/'),302,'Excel Herbal ERP');
        exit;
    }
}
