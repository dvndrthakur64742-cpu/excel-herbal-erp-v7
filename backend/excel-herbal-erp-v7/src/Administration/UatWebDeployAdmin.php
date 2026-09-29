<?php
namespace ExcelHerbal\ERP7\Administration;

use ExcelHerbal\ERP7\Security\ActorResolver;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;

final class UatWebDeployAdmin{
    private const PAGE='eh7-uat-web-deploy';
    private const ACTION='eh7_uat_web_deploy';
    private const MAX_BYTES=52428800;

    public static function boot():void{
        add_action('admin_menu',[self::class,'menu']);
        add_action('admin_post_'.self::ACTION,[self::class,'handle']);
    }

    public static function menu():void{
        add_management_page('EH7 UAT Web Deploy','EH7 UAT Web Deploy','manage_options',self::PAGE,[self::class,'render']);
    }

    public static function render():void{
        if(!current_user_can('manage_options'))wp_die('Administrator access required.');
        $result=get_transient(self::resultKey());
        if($result!==false)delete_transient(self::resultKey());
        echo '<div class="wrap"><h1>EH7 UAT Web Deploy</h1>';
        echo '<p>Controlled web-runtime deployment for the office BUILD/UAT environment. The bundle is verified by SHA-256 manifest and the current runtime is retained as a rollback copy.</p>';
        if(is_array($result)){
            echo '<div class="notice '.(!empty($result['ok'])?'notice-success':'notice-error').'"><p>'.esc_html((string)($result['message']??'Deployment result unavailable.')).'</p></div>';
        }
        try{
            $actor=self::deploymentActor();
            $uploads=wp_upload_dir();
            $target=rtrim((string)$uploads['basedir'],'/\\').'/eh7-flutter-web';
            if($actor){
                echo '<p><strong>ERP actor:</strong> '.esc_html((string)$actor->designationCode).' · Employee #'.esc_html((string)$actor->employeeId).'</p>';
            }else{
                echo '<p><strong>UAT deployment authority:</strong> WordPress administrator · controlled BUILD/UAT fallback</p>';
            }
            echo '<p><strong>Current runtime:</strong> '.esc_html(is_file($target.'/main.dart.js')?'present':'missing').'</p>';
            echo '<form method="post" enctype="multipart/form-data" action="'.esc_url(admin_url('admin-post.php')).'">';
            wp_nonce_field(self::ACTION);
            echo '<input type="hidden" name="action" value="'.esc_attr(self::ACTION).'">';
            echo '<p><label for="eh7_web_bundle"><strong>Certified Flutter Web ZIP</strong></label><br><input id="eh7_web_bundle" name="web_bundle" type="file" accept=".zip,application/zip" required></p>';
            echo '<p><label for="eh7_source_head"><strong>Certified source head</strong></label><br><input id="eh7_source_head" name="source_head" class="regular-text code" pattern="[0-9a-f]{40}" maxlength="40" required></p>';
            echo '<p><label for="eh7_reason"><strong>Audit reason</strong></label><br><input id="eh7_reason" name="reason" class="regular-text" value="Deploy certified UAT web runtime" required minlength="10"></p>';
            echo '<p><label for="eh7_confirm"><input id="eh7_confirm" type="checkbox" name="confirm" value="1" required> I confirm this certified BUILD/UAT web deployment.</label></p>';
            submit_button('Deploy Certified Web Bundle','primary','submit',false,['id'=>'eh7_submit']);
            echo '</form>';
        }catch(\Throwable $e){
            echo '<div class="notice notice-error"><p>'.esc_html($e->getMessage()).'</p></div>';
        }
        echo '</div>';
    }

    public static function handle():void{
        if(!current_user_can('manage_options'))wp_die('Administrator access required.');
        check_admin_referer(self::ACTION);
        $reason=sanitize_text_field((string)($_POST['reason']??''));
        $sourceHead=strtolower(trim((string)($_POST['source_head']??'')));
        try{
            if(empty($_POST['confirm']))throw new \RuntimeException('Explicit deployment confirmation is required.');
            if(strlen($reason)<10)throw new \RuntimeException('A deployment audit reason is required.');
            if(!preg_match('/^[0-9a-f]{40}$/',$sourceHead))throw new \RuntimeException('Certified source head is invalid.');
            $actor=self::deploymentActor();
            $result=self::deploy($_FILES['web_bundle']??[],$sourceHead);
            $auditContext=[
                'source_head'=>$sourceHead,
                'main_sha256'=>$result['main_sha256'],
                'manifest_sha256'=>$result['manifest_sha256'],
                'rollback'=>$result['rollback'],
                'reason'=>$reason,
            ];
            if($actor){
                Audit::add($actor,'administration.uat_web_deploy','web_runtime',$sourceHead,$auditContext);
            }else{
                update_option('eh7_uat_web_deploy_last_wp_admin_audit',[
                    'wp_user_id'=>get_current_user_id(),
                    'source_head'=>$sourceHead,
                    'main_sha256'=>$result['main_sha256'],
                    'manifest_sha256'=>$result['manifest_sha256'],
                    'rollback'=>$result['rollback'],
                    'reason'=>$reason,
                    'created_at'=>gmdate('c'),
                ],false);
            }
            set_transient(self::resultKey(),['ok'=>true,'message'=>'Certified UAT web bundle deployed. Source '.$sourceHead.' · main.dart.js '.$result['main_sha256']],180);
        }catch(\Throwable $e){
            set_transient(self::resultKey(),['ok'=>false,'message'=>$e->getMessage()],180);
        }
        wp_safe_redirect(admin_url('tools.php?page='.self::PAGE));
        exit;
    }

    private static function deploymentActor():?\ExcelHerbal\ERP7\Security\Actor{
        try{
            $actor=ActorResolver::current();
        }catch(\Throwable $e){
            $host=strtolower((string)parse_url((string)home_url('/'),PHP_URL_HOST));
            if(current_user_can('manage_options')&&Environment::allowsOfficeBuildUat()&&$host==='office.excelherbal.in')return null;
            throw $e;
        }
        Guard::cap($actor,Capabilities::ACCESS_MANAGE);
        return $actor;
    }

    private static function deploy(array $file,string $sourceHead):array{
        if((int)($file['error']??UPLOAD_ERR_NO_FILE)!==UPLOAD_ERR_OK)throw new \RuntimeException('Web bundle upload did not complete.');
        $tmp=(string)($file['tmp_name']??'');
        $size=(int)($file['size']??0);
        if($tmp===''||!is_uploaded_file($tmp))throw new \RuntimeException('Uploaded web bundle is invalid.');
        if($size<1024||$size>self::MAX_BYTES)throw new \RuntimeException('Web bundle ZIP size is invalid.');
        if(!class_exists('ZipArchive'))throw new \RuntimeException('ZipArchive is unavailable.');

        $uploads=wp_upload_dir();
        if(!empty($uploads['error']))throw new \RuntimeException((string)$uploads['error']);
        $base=rtrim((string)$uploads['basedir'],'/\\');
        $id=bin2hex(random_bytes(8));
        $stage=$base.'/eh7-flutter-web.__new_'.$id;
        $target=$base.'/eh7-flutter-web';
        $backup=$base.'/eh7-flutter-web.__rollback_'.gmdate('Ymd_His');
        if(!wp_mkdir_p($stage))throw new \RuntimeException('Web staging directory could not be created.');

        try{
            $zip=new \ZipArchive();
            if($zip->open($tmp)!==true)throw new \RuntimeException('Web bundle ZIP could not be opened.');
            try{
                for($i=0;$i<$zip->numFiles;$i++){
                    $name=(string)$zip->getNameIndex($i);
                    self::assertSafeRelative($name);
                    if(str_ends_with($name,'/')){if(!wp_mkdir_p($stage.'/'.rtrim($name,'/')))throw new \RuntimeException('Web bundle directory could not be created.');continue;}
                    $destination=$stage.'/'.$name;
                    if(!wp_mkdir_p(dirname($destination)))throw new \RuntimeException('Web bundle directory could not be created.');
                    $in=$zip->getStream($name); if(!$in)throw new \RuntimeException('Web bundle entry could not be read.');
                    $out=fopen($destination,'wb'); if(!$out){fclose($in);throw new \RuntimeException('Web bundle entry could not be written.');}
                    try{stream_copy_to_stream($in,$out);}finally{fclose($in);fclose($out);}
                }
            }finally{$zip->close();}

            foreach(['index.html','main.dart.js','flutter_bootstrap.js','SHA256SUMS.txt'] as $required)if(!is_file($stage.'/'.$required))throw new \RuntimeException('Web bundle missing required file: '.$required);
            self::verifyManifest($stage);

            $mainHash=hash_file('sha256',$stage.'/main.dart.js');
            $manifestHash=hash_file('sha256',$stage.'/SHA256SUMS.txt');
            file_put_contents($stage.'/EH7-SOURCE-HEAD.txt',$sourceHead."\n",LOCK_EX);

            // A source-only certification commit can produce byte-identical
            // Flutter web output. Replacing the whole live directory in that
            // case creates an unnecessary availability window. If the current
            // runtime already matches both certified hashes, retain it and
            // atomically advance only the source marker.
            if(is_dir($target)
                && is_file($target.'/main.dart.js')
                && is_file($target.'/SHA256SUMS.txt')
                && hash_equals($mainHash,(string)(hash_file('sha256',$target.'/main.dart.js')?:''))
                && hash_equals($manifestHash,(string)(hash_file('sha256',$target.'/SHA256SUMS.txt')?:''))){
                $markerTmp=$target.'/EH7-SOURCE-HEAD.txt.__new_'.$id;
                if(file_put_contents($markerTmp,$sourceHead."\n",LOCK_EX)===false)throw new \RuntimeException('Web source marker could not be staged.');
                if(!rename($markerTmp,$target.'/EH7-SOURCE-HEAD.txt')){
                    @unlink($markerTmp);
                    throw new \RuntimeException('Web source marker could not be activated.');
                }
                self::removeTree($stage);
                return ['main_sha256'=>$mainHash,'manifest_sha256'=>$manifestHash,'rollback'=>null];
            }

            $moved=false;
            if(is_dir($target)){
                if(!rename($target,$backup))throw new \RuntimeException('Current web runtime could not be preserved for rollback.');
                $moved=true;
            }
            if(!rename($stage,$target)){
                if($moved&&!is_dir($target)&&is_dir($backup))@rename($backup,$target);
                throw new \RuntimeException('Certified web runtime could not be activated.');
            }
            return ['main_sha256'=>$mainHash,'manifest_sha256'=>$manifestHash,'rollback'=>$moved?basename($backup):null];
        }catch(\Throwable $e){
            if(is_dir($stage))self::removeTree($stage);
            throw $e;
        }
    }

    private static function verifyManifest(string $stage):void{
        $lines=file($stage.'/SHA256SUMS.txt',FILE_IGNORE_NEW_LINES|FILE_SKIP_EMPTY_LINES);
        if(!$lines)throw new \RuntimeException('Web SHA-256 manifest is empty.');
        foreach($lines as $line){
            if(!preg_match('/^([a-f0-9]{64})  (.+)$/',trim((string)$line),$m))throw new \RuntimeException('Web SHA-256 manifest is invalid.');
            $rel=(string)$m[2]; self::assertSafeRelative($rel);
            $path=$stage.'/'.$rel;
            if(!is_file($path)||!hash_equals((string)$m[1],hash_file('sha256',$path)))throw new \RuntimeException('Web SHA-256 verification failed: '.$rel);
        }
    }

    private static function assertSafeRelative(string $path):void{
        if($path===''||strpos($path,"\0")!==false||strpos($path,'\\')!==false||str_starts_with($path,'/')||preg_match('#(^|/)\.\.(/|$)#',$path)||preg_match('/^[A-Za-z]:/',$path))throw new \RuntimeException('Unsafe web bundle path detected.');
    }

    private static function removeTree(string $dir):void{
        if(!is_dir($dir))return;
        $it=new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($dir,\FilesystemIterator::SKIP_DOTS),\RecursiveIteratorIterator::CHILD_FIRST);
        foreach($it as $item)$item->isDir()?@rmdir($item->getPathname()):@unlink($item->getPathname());
        @rmdir($dir);
    }

    private static function resultKey():string{return 'eh7_uat_web_deploy_'.get_current_user_id();}
}
