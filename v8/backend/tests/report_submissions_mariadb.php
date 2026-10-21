<?php
declare(strict_types=1);
/** Disposable v8_test only; no WordPress or production writes. */
if(!function_exists('current_time')){
 function current_time(string $format,bool $gmt=false):string {
    return $format==='Y-m-d'?'2026-10-20':'2026-10-20 12:00:00';
 }
}
if(!function_exists('wp_timezone')){
 function wp_timezone():DateTimeZone{return new DateTimeZone('Asia/Kolkata');}
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
          'Reporting/ReportingSubmissionService.php',
          'Reporting/BranchReportingWatch.php',
          'Reporting/ReportingWatchSubmissionProjection.php',
          'Reporting/ReportReminderDrafts.php'] as $file)require_once $src.$file;
 $schemas=\ExcelHerbal\ERP7\Database\Schema::definitions();
 foreach(['report_submissions','report_submission_events','report_reminder_drafts','audit_log'] as $table){
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

   $watchReader=new class implements \ExcelHerbal\ERP7\Reporting\BranchReportingWatchReader {
       public function branches(int $co,array $ids):array {
           return array_intersect_key([8201=>'Test Branch',8202=>'Other'],array_flip($ids));
       }
       public function dailyRoster(int $co,int $branch,string $date):array {
           return [['employee_id'=>991,'employee_name'=>'Active Field FSE',
               'branch_id'=>$branch,'cycle_id'=>null,
               'cycle_status'=>null,'settlement_status'=>null]];
       }
       public function dailyReport(\ExcelHerbal\ERP7\Security\Actor $a,int $branch,string $date):array {
           return ['read_only'=>true,'scope'=>'single_authorized_branch_canonical_v7',
               'business_date'=>$date,'branch_id'=>$branch,
               'coverage'=>['cashier_handover_verified'=>false,'upi_bank_verified'=>false],
               'totals'=>['pending_requests'=>0,'posted_daily_order_sales'=>'0.00']];
       }
   };
   $now=new DateTimeImmutable('2026-10-19 21:00:00',wp_timezone());
   $liveWatch=\ExcelHerbal\ERP7\Reporting\ReportingWatchSubmissionProjection::view(
       $regional,'2026-10-19',$branch,$watchReader,null,$now);
   $assert($liveWatch['schedule'][1]['submission_state']==='approved_all_branches'
       &&$liveWatch['branches'][0]['reporting_submissions'][0]['submission_state']==='approved'
       &&$liveWatch['reminder_outbox_dispatch_enabled']===false,
       'real SQL approved weekly report reflected on Manager Watch without delivery');
   $draft=\ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::prepare(
       $regional,$branch,'2026-10-19',$watchReader,null,$now);
   $assert($draft['created']===1&&$draft['state']==='draft_only'
       &&$draft['dispatch_enabled']===false&&$draft['notifications_sent']===0,
       'manual draft preparation creates only one undispatched daily reminder');
   $again=\ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::prepare(
       $regional,$branch,'2026-10-19',$watchReader,null,$now);
   $assert($again['created']===0&&$again['duplicates_skipped']===1,
       'real SQL unique dedupe key prevents repeated refresh duplicate drafts');
   $drafts=\ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::list(
       $regional,$branch,'2026-10-19');
   $assert(count($drafts['drafts'])===1
       &&$drafts['drafts'][0]['state']==='draft'
       &&$drafts['drafts'][0]['target_employee_id']==991
       &&$drafts['dispatch_enabled']===false,
       'report draft rows are branch-scoped and cannot imply sending');
   $monthDraft=\ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::prepare(
       $regional,$branch,'2026-10-01',$watchReader,null,
       new DateTimeImmutable('2026-10-01 11:00:00',wp_timezone()));
   $assert($monthDraft['created']===1&&$monthDraft['eligible']===1,
       '11:00 AM known monthly 10:30 cutoff creates monthly draft, not 19:30 daily');
   $nightDraft=\ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::prepare(
       $regional,$branch,'2026-10-01',$watchReader,null,
       new DateTimeImmutable('2026-10-01 20:00:00',wp_timezone()));
   $assert($nightDraft['eligible']===2&&$nightDraft['created']===1
       &&$nightDraft['duplicates_skipped']===1,
       'at 8:00 PM existing monthly draft deduped, daily 19:30 candidate added once');


   // Current-eligibility preview: proof changes must not delete historical
   // drafts or claim that the reviewer sent anything.
   $freshTime=new DateTimeImmutable('2026-10-01 20:00:00',wp_timezone());
   $allBefore=\ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::inspect(
       $regional,$branch,'2026-10-01','all',$watchReader,null,$freshTime);
   $assert(count($allBefore['drafts'])===2
       &&$allBefore['eligibility_counts']['currently_eligible']===2
       &&$allBefore['source_rechecked']===true
       &&$allBefore['snapshot_atomic']===false,
       'read-only real SQL preview identifies monthly and daily reminder candidates');
   $monthlyReport=\ExcelHerbal\ERP7\Reporting\ReportingSubmissionService::submit(
       $bm,['branch_id'=>$branch,'report_type'=>'monthly_report',
       'period_date'=>'2026-10-01',
       'summary_text'=>'Monthly operational submission with branch report evidence']);
   $afterSubmit=\ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::inspect(
       $regional,$branch,'2026-10-01','all',$watchReader,null,$freshTime);
   $statuses=[];foreach($afterSubmit['drafts'] as $r)$statuses[$r['report_type']]=$r['source_eligibility'];
   $assert($statuses['monthly_report']==='not_currently_eligible'
       &&$statuses['evening_daily_closing']==='currently_eligible'
       &&$afterSubmit['eligibility_counts']['not_currently_eligible']===1,
       'submitted real monthly report removes due eligibility without deleting historical draft');
   \ExcelHerbal\ERP7\Reporting\ReportingSubmissionService::decide(
       $regional,$monthlyReport['id'],['decision'=>'reject',
           'note'=>'Please attach missing verified branch field summary']);
   $afterReject=\ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::inspect(
       $regional,$branch,'2026-10-01','all',$watchReader,null,$freshTime);
   $assert($afterReject['eligibility_counts']['currently_eligible']===2
       &&$afterReject['canonical_reminder_candidates']===2,
       'rejected report is eligible again after original 10:30 cutoff');
   \ExcelHerbal\ERP7\Reporting\ReportingSubmissionService::submit($bm,[
       'branch_id'=>$branch,'report_type'=>'monthly_report','period_date'=>'2026-10-01',
       'summary_text'=>'Corrected monthly submission includes complete branch review']);
   \ExcelHerbal\ERP7\Reporting\ReportingSubmissionService::decide(
       $regional,$monthlyReport['id'],['decision'=>'approve',
           'note'=>'Monthly branch report verified by human reviewer']);
   $afterApproved=\ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::inspect(
       $regional,$branch,'2026-10-01','all',$watchReader,null,$freshTime);
   $assert($afterApproved['eligibility_counts']['currently_eligible']===1
       &&$afterApproved['eligibility_counts']['not_currently_eligible']===1,
       'approved monthly report leaves historical draft visible as no longer due');
   $persisted=$pdo->prepare(
       'SELECT COUNT(*) FROM wp_eh7_report_reminder_drafts WHERE company_id=? AND branch_id=? AND period_date=? AND state=?');
   $persisted->execute([$company,$branch,'2026-10-01','draft']);
   $assert((int)$persisted->fetchColumn()===2
       &&$afterApproved['notifications_sent']===0
       &&$afterApproved['automatic_dismissal']===false,
       'snapshot does not mutate drafts or send any reminders');
   $inspectDenied=false;
   try{\ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::inspect(
       $bm,$branch,'2026-10-01','all',$watchReader,null,$freshTime);}
   catch(\ExcelHerbal\ERP7\Domain\DomainException $e){
       $inspectDenied=$e->codeKey==='permission_denied';
   }
   $assert($inspectDenied,'submit-only BM cannot access reviewer freshness inspection');

   $dismissId=(int)$drafts['drafts'][0]['id'];
   $dismissed=\ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::dismiss(
       $regional,$branch,$dismissId,'Daily closing followed up outside ERP and confirmed manually');
   $assert($dismissed['state']==='dismissed'
       &&$dismissed['dispatch_enabled']===false
       &&$dismissed['notifications_sent']===0
       &&$dismissed['dismissed_by']===$regional->employeeId,
       'regional reviewer dismisses existing draft without claiming delivery');
   $afterDismiss=\ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::list(
       $regional,$branch,'2026-10-19');
   $assert(count($afterDismiss['drafts'])===0,
       'dismissed draft disappears from active branch worklist');
   $dismissMeta=$pdo->prepare(
       'SELECT state,dismissed_by,dismissal_reason FROM wp_eh7_report_reminder_drafts WHERE id=?');
   $dismissMeta->execute([$dismissId]);$review=$dismissMeta->fetch();
   $assert($review['state']==='dismissed'
       &&(int)$review['dismissed_by']===$regional->employeeId
       &&strlen($review['dismissal_reason'])>12,
       'reviewer identity and audit reason persist in canonical draft table');
   $notReopened=\ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::prepare(
       $regional,$branch,'2026-10-19',$watchReader,null,$now);
   $assert($notReopened['created']===0&&$notReopened['duplicates_skipped']===1
       &&count(\ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::list(
           $regional,$branch,'2026-10-19')['drafts'])===0,
       'unique dedup key keeps dismissed draft closed on repeated prepare');
   $doubleDismiss=false;
   try{\ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::dismiss(
       $regional,$branch,$dismissId,'Second time attempt to dismiss same draft');}
   catch(\ExcelHerbal\ERP7\Domain\DomainException $e){
       $doubleDismiss=$e->codeKey==='report_draft_already_dismissed';
   }
   $assert($doubleDismiss,'duplicate dismissal denied with explicit state conflict');
   $crossBranchDenied=false;
   try{\ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::dismiss(
       $regional,$other,$dismissId,'Try unauthorized cross branch draft edit');}
   catch(\ExcelHerbal\ERP7\Domain\DomainException $e){
       $crossBranchDenied=$e->codeKey==='report_draft_not_found';
   }
   $assert($crossBranchDenied,'same reviewer cannot update draft using different authorized branch');
   $bmDismissDenied=false;
   try{\ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::dismiss(
       $bm,$branch,$dismissId,'Maker must not be able to review draft');}
   catch(\ExcelHerbal\ERP7\Domain\DomainException $e){
       $bmDismissDenied=$e->codeKey==='permission_denied';
   }
   $assert($bmDismissDenied,'submitter lacks reviewer draft dismissal permission');
   $auditRow=$pdo->prepare(
       "SELECT COUNT(*) FROM wp_eh7_audit_log WHERE company_id=? AND action='report.reminder_draft.dismiss' AND entity_id=?");
   $auditRow->execute([$company,$dismissId]);
   $assert((int)$auditRow->fetchColumn()===1,
       'real MariaDB immutable audit log contains one reviewer dismissal');
   $wrongCompanyDenied=false;
   try{
       \ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::list(
           $foreign,$branch,'2026-10-19');
       $foreignRows=\ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::list(
           $foreign,$branch,'2026-10-19');
       $wrongCompanyDenied=count($foreignRows['drafts'])===0;
   }catch(\ExcelHerbal\ERP7\Domain\DomainException $ignored){
       $wrongCompanyDenied=true;
   }
   $assert($wrongCompanyDenied,'foreign company sees no real draft despite same branch identifier');
   $bmDenied=false;
   try{\ExcelHerbal\ERP7\Reporting\ReportReminderDrafts::prepare(
       $bm,$branch,'2026-10-19',$watchReader,null,$now);}
   catch(\ExcelHerbal\ERP7\Domain\DomainException $ex){
       $bmDenied=$ex->codeKey==='permission_denied';
   }
   $assert($bmDenied,'BM submitter cannot prepare reviewer-only reminder drafts');
 }finally{
    $pdo->prepare('DELETE FROM wp_eh7_report_reminder_drafts WHERE company_id=?')->execute([$company]);
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
