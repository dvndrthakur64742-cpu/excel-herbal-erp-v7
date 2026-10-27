<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP7\Reporting;

use DateTimeImmutable;
use ExcelHerbal\ERP7\Core\Input;
use ExcelHerbal\ERP7\Database\{Db,Transaction};
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities,Guard,Audit};

/**
 * Branch reporting attestation is separate from sales, bank, salary and
 * physical inventory verification. Every state transition is atomic,
 * company+branch scoped and has an append-only signed-by-actor audit event.
 */
final class ReportingSubmissionService {
    private const TYPES=['weekly_report','product_order_mon','product_order_tue','monthly_report','salary_receipts'];
    private const STATES=['submitted','approved','rejected'];
    private static function type(string $type):string {
        $type=strtolower(trim($type));
        if(!in_array($type,self::TYPES,true))
            throw new DomainException('Unknown reporting obligation.','report_submission_type_invalid',422);
        return $type;
    }
    private static function note(string $note,string $label,int $min=12,int $max=1900):string {
        $note=trim($note);
        if(strlen($note)<$min||strlen($note)>$max||preg_match('/[\x00-\x08\x0B\x0C\x0E-\x1F]/',$note))
            throw new DomainException($label.' length or characters invalid.','report_submission_text_invalid',422);
        return $note;
    }
    private static function period(string $type,string $periodDate):string {
        $date=Input::date($periodDate,'Report period date');
        $d=new DateTimeImmutable($date);
        $day=(int)$d->format('N');
        $monthDay=(int)$d->format('j');
        if(($type==='weekly_report'||$type==='product_order_mon')&&$day!==1
           ||$type==='product_order_tue'&&$day!==2
           ||$type==='monthly_report'&&$monthDay!==1
           ||$type==='salary_receipts'&&$monthDay!==10)
            throw new DomainException('Report period does not match obligation schedule.','report_submission_schedule_invalid',422);
        $today=Input::date(Db::today(),'Business date');
        // Can submit late, not earlier than the nominal reporting date.
        if($date>$today)throw new DomainException('Future report cannot be attested as submitted.','report_submission_future',422);
        if($date<(new DateTimeImmutable($today))->modify('-180 days')->format('Y-m-d'))
            throw new DomainException('Historical report outside 180-day audit window.','report_submission_old',422);
        return $date;
    }
    private static function allow(Actor $actor,int $branch,string $type,string $cap):void {
        Guard::branch($actor,$branch,$cap);
        if($type==='salary_receipts')Guard::cap($actor,Capabilities::SALARY_VIEW);
        if($cap===Capabilities::REPORT_SUBMIT&&$branch!==$actor->assignedBranchId)
            throw new DomainException('Submission must use assigned home branch.','report_submission_branch_forbidden',403);
    }
    /** Read-only. The server never takes a client supplied company or reviewer id. */
    public static function list(Actor $actor,int $branch,string $status='all',int $limit=100):array {
        Guard::branchAny($actor,$branch,[Capabilities::REPORT_SUBMIT,Capabilities::REPORT_REVIEW]);
        if(!in_array($status,['all','submitted','approved','rejected'],true)
            ||$limit<1||$limit>100)
            throw new DomainException('Invalid submission listing filter.','report_submission_filter_invalid',422);
        $db=Db::wpdb();$t=Db::table('report_submissions');
        $statusSql=$status==='all'?'':$db->prepare(' AND status=%s',$status);
        $sql="SELECT id,company_id,branch_id,report_type,period_date,status,revision,
                submitted_by,submitted_at,reviewed_by,reviewed_at,summary_text,content_sha256
              FROM {$t} WHERE company_id=%d AND branch_id=%d {$statusSql}
              ORDER BY period_date DESC,id DESC LIMIT %d";
        $rows=$db->get_results($db->prepare($sql,$actor->companyId,$branch,$limit),ARRAY_A);
        if(!is_array($rows))throw new DomainException('Submission listing query failed.','report_submission_query_failed',500);
        $out=[];
        foreach($rows as $r){
            if((int)$r['company_id']!==$actor->companyId||(int)$r['branch_id']!==$branch)
                throw new DomainException('Submission branch scope leak.','report_submission_scope_invalid',500);
            if($r['report_type']==='salary_receipts'&&!$actor->can(Capabilities::SALARY_VIEW))continue;
            if(!$actor->can(Capabilities::REPORT_REVIEW)&&(int)$r['submitted_by']!==$actor->employeeId)continue;
            unset($r['company_id']);
            $out[]=$r;
        }
        return ['read_only'=>true,'branch_id'=>$branch,'records'=>$out,'scope'=>'authorized_branch_report_submissions',
            'evidence'=>'user_attestation_only_not_bank_payroll_or_stock_verification'];
    }
    private static function row(Actor $actor,int $id,bool $lock):array {
        if($id<1)throw new DomainException('Invalid report submission id.','report_submission_not_found',404);
        $db=Db::wpdb();$t=Db::table('report_submissions');
        $r=$db->get_row($db->prepare(
            "SELECT * FROM {$t} WHERE id=%d AND company_id=%d".($lock?' FOR UPDATE':''),$id,$actor->companyId),ARRAY_A);
        if(!is_array($r))throw new DomainException('Report submission not found.','report_submission_not_found',404);
        Guard::branchAny($actor,(int)$r['branch_id'],[Capabilities::REPORT_SUBMIT,Capabilities::REPORT_REVIEW]);
        if($r['report_type']==='salary_receipts')Guard::cap($actor,Capabilities::SALARY_VIEW);
        if(!$actor->can(Capabilities::REPORT_REVIEW)&&(int)$r['submitted_by']!==$actor->employeeId)
            throw new DomainException('Only submitter or authorized reviewer can read this.','report_submission_forbidden',403);
        return $r;
    }
    public static function history(Actor $actor,int $id):array {
        $r=self::row($actor,$id,false);
        $db=Db::wpdb();$t=Db::table('report_submission_events');
        $rows=$db->get_results($db->prepare(
            "SELECT id,revision,event_type,actor_employee_id,content_sha256,content_snapshot,note,created_at
             FROM {$t} WHERE submission_id=%d AND company_id=%d AND branch_id=%d ORDER BY id ASC LIMIT 201",
            $id,$actor->companyId,(int)$r['branch_id']),ARRAY_A);
        if(!is_array($rows)||count($rows)>200)
            throw new DomainException('Submission audit history incomplete.','report_submission_history_incomplete',500);
        return ['read_only'=>true,'id'=>$id,'branch_id'=>(int)$r['branch_id'],
            'report_type'=>$r['report_type'],'status'=>$r['status'],
            'history'=>$rows,'audit_events_append_only'=>true,
            'proof'=>'manager_attestation_and_review_not_external_bank_or_cash_verification'];
    }
    public static function submit(Actor $actor,array $body):array {
        $type=self::type((string)($body['report_type']??''));
        $branch=(int)($body['branch_id']??0);
        self::allow($actor,$branch,$type,Capabilities::REPORT_SUBMIT);
        $date=self::period($type,(string)($body['period_date']??''));
        $note=self::note((string)($body['summary_text']??''),'Submission summary',15);
        $hash=hash('sha256',$type.'|'.$date.'|'.$note);
        return Transaction::run(function()use($actor,$branch,$type,$date,$note,$hash){
            $db=Db::wpdb();$t=Db::table('report_submissions');
            // Unique company+branch+type+period; concurrent first submits must
            // fail at DB constraint rather than creating two mutable sources.
            $old=$db->get_row($db->prepare(
                "SELECT * FROM {$t} WHERE company_id=%d AND branch_id=%d AND report_type=%s AND period_date=%s FOR UPDATE",
                $actor->companyId,$branch,$type,$date),ARRAY_A);
            $now=Db::now();
            if($old){
                if($old['status']!=='rejected')
                    throw new DomainException('This report period is already submitted.','report_submission_duplicate',409);
                if((int)$old['submitted_by']!==$actor->employeeId)
                    throw new DomainException('Only original submitter may revise rejected report.','report_submission_owner_forbidden',403);
                $id=(int)$old['id'];$revision=(int)$old['revision']+1;
                if($revision>100)throw new DomainException('Too many report revisions.','report_submission_revision_limit',409);
                $changed=$db->update($t,[
                    'summary_text'=>$note,'content_sha256'=>$hash,'status'=>'submitted',
                    'revision'=>$revision,'submitted_at'=>$now,'reviewed_by'=>null,'reviewed_at'=>null,
                    'review_note'=>null
                ],['id'=>$id,'company_id'=>$actor->companyId,'branch_id'=>$branch,'status'=>'rejected']);
                if($changed!==1)throw new DomainException('Report resubmission conflicted.','report_submission_conflict',409);
                $action='resubmitted';
            }else{
                Db::mustInsert($db,$t,[
                    'company_id'=>$actor->companyId,'branch_id'=>$branch,'report_type'=>$type,
                    'period_date'=>$date,'summary_text'=>$note,'content_sha256'=>$hash,
                    'status'=>'submitted','revision'=>1,'submitted_by'=>$actor->employeeId,
                    'submitted_at'=>$now,'created_at'=>$now
                ],'This report period was submitted concurrently.','report_submission_duplicate');
                $id=(int)$db->insert_id;$revision=1;$action='submitted';
            }
            self::event($actor,$id,$branch,$revision,$action,$hash,$note,'');
            Audit::add($actor,'report.'.$action,'report_submission',$id,['branch_id'=>$branch,'type'=>$type,'period_date'=>$date,'revision'=>$revision]);
            return ['id'=>$id,'branch_id'=>$branch,'report_type'=>$type,
                'period_date'=>$date,'status'=>'submitted','revision'=>$revision,
                'content_sha256'=>$hash,'external_verification'=>false];
        });
    }
    public static function decide(Actor $actor,int $id,array $body):array {
        $decision=(string)($body['decision']??'');
        if(!in_array($decision,['approve','reject'],true))
            throw new DomainException('Decision must be approve or reject.','report_decision_invalid',422);
        $note=self::note((string)($body['note']??''),'Review reason',$decision==='reject'?12:0,500);
        return Transaction::run(function()use($actor,$id,$decision,$note){
            $r=self::row($actor,$id,true);
            self::allow($actor,(int)$r['branch_id'],$r['report_type'],Capabilities::REPORT_REVIEW);
            if((int)$r['submitted_by']===$actor->employeeId)
                throw new DomainException('Maker cannot review own submission.','report_maker_checker_forbidden',403);
            if($r['status']!=='submitted')
                throw new DomainException('Only submitted reports may be reviewed.','report_decision_conflict',409);
            $status=$decision==='approve'?'approved':'rejected';
            $db=Db::wpdb();$updated=$db->update(Db::table('report_submissions'),[
                'status'=>$status,'reviewed_by'=>$actor->employeeId,
                'reviewed_at'=>Db::now(),'review_note'=>$note
            ],['id'=>$id,'company_id'=>$actor->companyId,'branch_id'=>(int)$r['branch_id'],
               'status'=>'submitted','revision'=>(int)$r['revision']]);
            if($updated!==1)throw new DomainException('Approval state changed concurrently.','report_decision_conflict',409);
            self::event($actor,$id,(int)$r['branch_id'],(int)$r['revision'],
                $status,(string)$r['content_sha256'],(string)$r['summary_text'],$note);
            Audit::add($actor,'report.'.$status,'report_submission',$id,
                ['branch_id'=>(int)$r['branch_id'],'revision'=>(int)$r['revision']]);
            return ['id'=>$id,'branch_id'=>(int)$r['branch_id'],
                'status'=>$status,'revision'=>(int)$r['revision'],
                'content_sha256'=>$r['content_sha256'],
                'external_verification'=>false];
        });
    }
    private static function event(Actor $actor,int $id,int $branch,int $revision,
        string $action,string $sha,string $snapshot,string $note):void {
        Db::mustInsert(Db::wpdb(),Db::table('report_submission_events'),[
            'company_id'=>$actor->companyId,'branch_id'=>$branch,
            'submission_id'=>$id,'revision'=>$revision,'event_type'=>$action,
            'actor_employee_id'=>$actor->employeeId,'content_sha256'=>$sha,
            'content_snapshot'=>$snapshot,'note'=>$note,'created_at'=>Db::now()
        ]);
    }
}
