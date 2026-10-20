<?php
declare(strict_types=1);
/** Disposable v8_test only; no WordPress or production writes. */
if(!function_exists('current_time')){
 function current_time(string $format,bool $gmt=false):string {
    return $format==='Y-m-d'?'2026-10-20':'2026-10-20 12:00:00';
 }
}
if(!function_exists('wp_json_encode')){
 function wp_json_encode(mixed $v,int $flags=0):string{return json_encode($v,$flags|JSON_THROW_ON_ERROR);}
}
if(!defined('ARRAY_A'))define('ARRAY_A','ARRAY_A');
$dsn=getenv('V8_TEST_DSN');
if(!$dsn){fwrite(STDOUT,"SKIP submission MariaDB: V8_TEST_DSN missing\n");exit(0);}
try{
 $pdo=new PDO($dsn,getenv('V8_TEST_USER')?:'v8',getenv('V8_TEST_PASSWORD')?:'v8',[
     PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,
     PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC
 ]);
 if($pdo->query('SELECT DATABASE()')->fetchColumn()!=='v8_test')
     throw new RuntimeException('Refuse reporting workflow tests outside v8_test');
 $root=dirname(__DIR__,3);
 $src=$root.'/backend/excel-herbal-erp-v7/src/';
 foreach(['Domain/DomainException.php','Security/Actor.php','Security/Capabilities.php',
          'Security/Guard.php','Core/Input.php','Database/Db.php','Database/Schema.php',
          'Database/Transaction.php','Security/Audit.php',
          'Reporting/ReportingSubmissionService.php'] as $file)require_once $src.$file;
 $schemas=\ExcelHerbal\ERP7\Database\Schema::definitions();
 foreach(['report_submissions','report_submission_events','audit_log'] as $table){
    if(!isset($schemas[$table]))throw new RuntimeException('Missing V7 report definition: '.$table);
    $pdo->exec("CREATE TABLE IF NOT EXISTS wp_eh7_".$table." (".$schemas[$table].") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
 }
 $GLOBALS['wpdb']=new class($pdo){
    public string $prefix='wp_';public int $insert_id=0;public string $last_error='';
    public function __construct(private PDO $db){}
    public function prepare(string $sql,mixed ...$args):string{
      if(count($args)===1&&is_array($args[0]))$args=$args[0];
      $at=0;
      $query=preg_replace_callback('/%[ds]/',function($m)use(&$at,$args){
        if(!array_key_exists($at,$args))throw new RuntimeException('Missing SQL binding');
        $v=$args[$at++];return $m[0]==='%d'?(string)(int)$v:$this->db->quote((string)$v);
      },$sql);
      if($at!==count($args))throw new RuntimeException('Unexpected SQL binding');
      return (string)$query;
    }
    public function query(string $sql):int|false{
      try{return (int)$this->db->exec($sql);}
      catch(Throwable $e){$this->last_error=$e->getMessage();return false;}
    }
    public function get_row(string $sql,mixed $mode=null):?array{
      $stmt=$this->db->query($sql);$row=$stmt->fetch(PDO::FETCH_ASSOC);return $row?:null;
    }
    public function get_results(string $sql,mixed $mode=null):array{
      return $this->db->query($sql)->fetchAll(PDO::FETCH_ASSOC);
    }
    public function insert(string $table,array $fields):int|false{
      $names=array_keys($fields);
      $sql='INSERT INTO '.$table.' ('.implode(',',$names).') VALUES('.
        implode(',',array_fill(0,count($names),'?')).')';
      try{
        $q=$this->db->prepare($sql);$q->execute(array_values($fields));
        $this->insert_id=(int)$this->db->lastInsertId();return $q->rowCount();
      }catch(Throwable $e){$this->last_error=$e->getMessage();return false;}
    }
    public function update(string $table,array $fields,array $where):int|false{
      $sets=array_map(fn($k)=>$k.'=?',array_keys($fields));
      $conditions=array_map(fn($k)=>$k.'=?',array_keys($where));
      $sql='UPDATE '.$table.' SET '.implode(',',$sets).' WHERE '.implode(' AND ',$conditions);
      try{
        $q=$this->db->prepare($sql);$q->execute([...array_values($fields),...array_values($where)]);
        return $q->rowCount();
      }catch(Throwable $e){$this->last_error=$e->getMessage();return false;}
    }
 };
 $n=0;$assert=static function(bool $good,string $message)use(&$n):void{
    if(!$good)throw new RuntimeException('FAIL '.$message);
    $n++;echo "PASS {$message}\n";
 };
 $company=987670901;$branch=8201;$other=8202;
 $bm=new \ExcelHerbal\ERP7\Security\Actor(301,901,$company,$branch,[$branch],
      [\ExcelHerbal\ERP7\Security\Capabilities::REPORTS_VIEW,
       \ExcelHerbal\ERP7\Security\Capabilities::REPORT_SUBMIT],'BM');
 $regional=new \ExcelHerbal\ERP7\Security\Actor(302,902,$company,$other,[$branch,$other],
      [\ExcelHerbal\ERP7\Security\Capabilities::REPORTS_VIEW,
       \ExcelHerbal\ERP7\Security\Capabilities::REPORT_REVIEW],'RM');
 $payload=['branch_id'=>$branch,'report_type'=>'weekly_report',
      'period_date'=>'2026-10-19',
      'summary_text'=>'Verified field visit summary shared for regional review'];
 try{
   $created=\ExcelHerbal\ERP7\Reporting\ReportingSubmissionService::submit($bm,$payload);
   $id=$created['id'];
   $assert($id>0&&$created['status']==='submitted'
     &&$created['revision']===1,'real MariaDB creates one report attestation');
   $duplicate=false;
   try{\ExcelHerbal\ERP7\Reporting\ReportingSubmissionService::submit($bm,$payload);}
   catch(\ExcelHerbal\ERP7\Domain\DomainException $e){
     $duplicate=$e->codeKey==='report_submission_duplicate';
   }
   $assert($duplicate,'real SQL unique report period rejects duplicate');
   $reject=\ExcelHerbal\ERP7\Reporting\ReportingSubmissionService::decide(
     $regional,$id,['decision'=>'reject','note'=>'Missing field visit details']);
   $assert($reject['status']==='rejected','regional rejection commits atomically to MariaDB');
   $revision=\ExcelHerbal\ERP7\Reporting\ReportingSubmissionService::submit(
     $bm,[...$payload,'summary_text'=>'Updated field visit details with branch stock overview']);
   $assert($revision['revision']===2
       &&$revision['content_sha256']!==$created['content_sha256'],
       'resubmitted revision 2 gets distinct immutable hash');
   $approve=\ExcelHerbal\ERP7\Reporting\ReportingSubmissionService::decide(
     $regional,$id,['decision'=>'approve','note'=>'Checked the report submission']);
   $assert($approve['status']==='approved','regional approval commits to unique version two');
   $events=\ExcelHerbal\ERP7\Reporting\ReportingSubmissionService::history($bm,$id);
   $assert(count($events['history'])===4
      &&$events['history'][0]['content_sha256']===$created['content_sha256']
      &&$events['history'][2]['content_sha256']===$revision['content_sha256'],
      'append-only events contain original/revised immutable content snapshots');
   $list=\ExcelHerbal\ERP7\Reporting\ReportingSubmissionService::list($regional,$branch,'approved');
   $assert(count($list['records'])===1&&$list['records'][0]['id']==$id,
      'real SQL report listing scoped to authorized branch and review status');
   $otherBranchList=\ExcelHerbal\ERP7\Reporting\ReportingSubmissionService::list($regional,$other);
   $assert(count($otherBranchList['records'])===0,'regional other branch does not inherit first branch data');
   $foreign=new \ExcelHerbal\ERP7\Security\Actor(303,903,$company+1,$branch,[$branch],
      [\ExcelHerbal\ERP7\Security\Capabilities::REPORTS_VIEW,
       \ExcelHerbal\ERP7\Security\Capabilities::REPORT_REVIEW],'RM');
   $blocked=false;
   try{\ExcelHerbal\ERP7\Reporting\ReportingSubmissionService::history($foreign,$id);}
   catch(\ExcelHerbal\ERP7\Domain\DomainException $e){
      $blocked=$e->codeKey==='report_submission_not_found';
   }
   $assert($blocked,'cross-company approval audit not visible');
   $audits=$pdo->prepare("SELECT action,entity_id FROM wp_eh7_audit_log WHERE company_id=? AND entity_type='report_submission' AND entity_id=? ORDER BY id");
   $audits->execute([$company,(string)$id]);
   $log=$audits->fetchAll();
   $assert(count($log)===4,'four transitions write matching canonical audit_log events');
 }finally{
    $pdo->prepare('DELETE FROM wp_eh7_audit_log WHERE company_id=? AND entity_type=?')
       ->execute([$company,'report_submission']);
    $pdo->prepare('DELETE FROM wp_eh7_report_submission_events WHERE company_id=?')
       ->execute([$company]);
    $pdo->prepare('DELETE FROM wp_eh7_report_submissions WHERE company_id=?')
       ->execute([$company]);
 }
 echo "BRANCH SUBMISSION MAKER-CHECKER REAL MARIADB: {$n}/{$n} PASS; disposable v8_test only\n";
}catch(Throwable $e){
 fwrite(STDERR,'REPORT SUBMISSION MARIADB FAILED '.$e::class.' '.$e->getMessage().
   ' @ '.$e->getFile().':'.$e->getLine()."\n");exit(1);
}
