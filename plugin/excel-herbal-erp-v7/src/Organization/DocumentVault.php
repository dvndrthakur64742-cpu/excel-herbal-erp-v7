<?php
namespace ExcelHerbal\ERP7\Organization;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;

/** Encrypted document payloads; direct filesystem URLs never contain readable documents. */
final class DocumentVault {
    public static function provisionKey():void {
        if(get_option('eh7_document_key','')!=='')return;
        $db=Db::wpdb();$count=$db->get_var('SELECT COUNT(*) FROM '.Db::table('private_documents'));
        if(!empty($db->last_error)||$count===null||(int)$count>0)throw new \RuntimeException('Restore the document encryption key before proceeding.');
        if(!add_option('eh7_document_key',base64_encode(random_bytes(32)),'',false)&&get_option('eh7_document_key','')==='')throw new \RuntimeException('Unable to save document encryption key.');
    }
    private static function key():string {
        if(!function_exists('openssl_encrypt'))throw new DomainException('OpenSSL is required for private documents.','document_crypto_missing',503);
        $key=get_option('eh7_document_key','');
        $raw=base64_decode((string)$key,true);
        if($raw===false||strlen($raw)!==32)throw new DomainException('Document encryption key unavailable. Restore the key from backup.','document_key_invalid',503);
        return $raw;
    }
    public static function storeUpload():int {
        $f=$_FILES['file']??[];
        if(!is_array($f)||(int)($f['error']??UPLOAD_ERR_NO_FILE)!==UPLOAD_ERR_OK||!is_uploaded_file((string)($f['tmp_name']??'')))throw new DomainException('A valid multipart file is required.','document_upload_invalid',422);
        $path=(string)$f['tmp_name'];$size=filesize($path);
        if(!$size||$size>10485760)throw new DomainException('Document must be between 1 byte and 10 MB.','document_size_invalid',422);
        $name=sanitize_file_name((string)$f['name']);$ext=strtolower(pathinfo($name,PATHINFO_EXTENSION));
        $allowed=['pdf'=>'application/pdf','jpg'=>'image/jpeg','jpeg'=>'image/jpeg','png'=>'image/png','webp'=>'image/webp'];
        $mime=(new \finfo(FILEINFO_MIME_TYPE))->file($path);
        if(!isset($allowed[$ext])||$allowed[$ext]!==$mime)throw new DomainException('Allowed content: PDF, JPEG, PNG or WEBP.','document_type_invalid',422);
        $bytes=file_get_contents($path);if($bytes===false)throw new DomainException('Document read failed.','document_read_failed',500);
        $iv=random_bytes(12);$tag='';$cipher=openssl_encrypt($bytes,'aes-256-gcm',self::key(),OPENSSL_RAW_DATA,$iv,$tag,'eh7-document-v1');
        if($cipher===false)throw new DomainException('Document encryption failed.','document_encrypt_failed',500);
        // A database blob avoids orphan filesystem files on transaction rollback.
        // Ensure max_allowed_packet supports a 10 MB upload before production use.
        $db=Db::wpdb();Db::mustInsert($db,Db::table('private_documents'),['filename'=>$name,'mime_type'=>$mime,'payload'=>base64_encode($cipher),'iv'=>base64_encode($iv),'tag'=>base64_encode($tag),'sha256'=>hash('sha256',$bytes),'created_at'=>Db::now()]);return (int)$db->insert_id;
    }
    public static function url(string $kind,int $owner,int $document):string {
        $path=$kind==='candidate'?'candidates':'employees';
        return rest_url('excel-herbal-erp/v7/organization/'.$path.'/'.$owner.'/documents/'.$document.'/download');
    }
    public static function download(Actor $a,string $kind,int $owner,int $document):array {
        $db=Db::wpdb();$candidate=$kind==='candidate';$owners=Db::table($candidate?'hr_candidates':'employees');$branch=$candidate?'branch_id':'assigned_branch_id';
        $e=$db->get_row($db->prepare("SELECT {$branch} branch_id FROM {$owners} WHERE id=%d AND company_id=%d",$owner,$a->companyId),ARRAY_A);
        if(!$e)throw new DomainException('Document owner not found.','document_not_found',404);
        Guard::branch($a,(int)$e['branch_id'],$candidate?Capabilities::HR_VIEW:Capabilities::EMP_VIEW);
        Guard::cap($a,$candidate?Capabilities::HR_DOCUMENT_DOWNLOAD:Capabilities::EMP_DOCUMENT_DOWNLOAD);
        if(!$candidate)\ExcelHerbal\ERP7\Security\HierarchyScope::assertCanViewEmployee($a,$owner);
        $t=Db::table($candidate?'hr_candidate_documents':'employee_documents');$field=$candidate?'candidate_id':'employee_id';
        $r=$db->get_row($db->prepare("SELECT private_file_id FROM {$t} WHERE id=%d AND {$field}=%d AND company_id=%d AND status='active'",$document,$owner,$a->companyId),ARRAY_A);
        if(!$r||empty($r['private_file_id']))throw new DomainException('Private document unavailable; legacy media requires migration.','document_not_found',404);
        $blob=$db->get_row($db->prepare('SELECT * FROM '.Db::table('private_documents').' WHERE id=%d',(int)$r['private_file_id']),ARRAY_A);
        if(!$blob)throw new DomainException('Document content missing.','document_not_found',404);
        $plain=openssl_decrypt(base64_decode($blob['payload']),'aes-256-gcm',self::key(),OPENSSL_RAW_DATA,base64_decode($blob['iv']),base64_decode($blob['tag']),'eh7-document-v1');
        if($plain===false||!hash_equals($blob['sha256'],hash('sha256',$plain)))throw new DomainException('Document integrity verification failed.','document_integrity_failed',500);
        return ['bytes'=>$plain,'filename'=>$blob['filename'],'mime_type'=>$blob['mime_type']];
    }
    public static function serve($served,$result,$request,$server):bool {
        if($result instanceof \WP_REST_Response && ($result->get_headers()['X-EH7-Private-Document']??'')==='1'){
            echo $result->get_data();return true;
        }
        return (bool)$served;
    }
}
