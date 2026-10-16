<?php
namespace ExcelHerbal\ERP7\Administration;

use ExcelHerbal\ERP7\Database\Db;

final class StagingSafety {
    public static function status():array {
        $environment=Environment::type();
        if($environment!=='staging')return ['required'=>false,'sanitized'=>false,'environment'=>$environment];
        $db=Db::wpdb();
        $activeSessions=(int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('mobile_sessions').' WHERE revoked_at IS NULL');
        $activePush=(int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('push_devices').' WHERE active=1');
        $source=defined('EH7_SOURCE_HEAD')?(string)EH7_SOURCE_HEAD:'source-tree';
        $marker=(string)get_option('eh7_staging_sanitized_source_head','');
        $sanitizedAt=(string)get_option('eh7_staging_sanitized_at','');
        $sourceMatch=$source!==''&&$marker!==''&&hash_equals(strtolower($source),strtolower($marker));
        return [
            'required'=>true,
            'sanitized'=>$sourceMatch&&$sanitizedAt!==''&&$activeSessions===0&&$activePush===0,
            'environment'=>$environment,
            'source_head_match'=>$sourceMatch,
            'active_mobile_sessions_zero'=>$activeSessions===0,
            'active_push_devices_zero'=>$activePush===0,
            'search_indexing_disabled'=>(string)get_option('blog_public','1')==='0',
            'sanitized_at'=>$sanitizedAt?:null,
        ];
    }

    public static function sanitize():array {
        if(Environment::type()!=='staging')throw new \RuntimeException('Staging sanitizer refuses non-staging environments.');
        $host=strtolower((string)parse_url((string)home_url('/'),PHP_URL_HOST));
        Environment::assertSafeUatHost($host);
        $source=defined('EH7_SOURCE_HEAD')?(string)EH7_SOURCE_HEAD:'';
        if(!preg_match('/^[0-9a-f]{40}$/i',$source))throw new \RuntimeException('Staging sanitizer requires an exact packaged source head.');

        $db=Db::wpdb();$now=Db::now();
        $sessions=Db::mustQuery($db,'UPDATE '.Db::table('mobile_sessions')." SET revoked_at=COALESCE(revoked_at,'".$now."') WHERE revoked_at IS NULL");
        $push=Db::mustQuery($db,'UPDATE '.Db::table('push_devices')." SET active=0,updated_at='".$now."' WHERE active=1");
        update_option('blog_public',0,false);
        update_option('eh7_staging_sanitized_source_head',$source,false);
        update_option('eh7_staging_sanitized_at',$now,false);

        $status=self::status();
        if(($status['sanitized']??false)!==true)throw new \RuntimeException('Staging sanitizer verification failed.');
        return ['sessions_revoked'=>$sessions,'push_devices_deactivated'=>$push]+$status;
    }

}

