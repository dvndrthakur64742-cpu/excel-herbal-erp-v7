<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP7\Reporting;

use ExcelHerbal\ERP7\Database\{Db,Transaction};
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities,Guard,Audit};

/**
 * Manual, internal DRAFT ONLY outbox. No email, SMS, FCM, WhatsApp or cron
 * adapter is referenced, and no API transition can set a sent/queued state.
 */
final class ReportReminderDrafts {
    private const MAX_DRAFTS=2000;

    private static function requireReviewer(Actor $actor,int $branch):void {
        Guard::branch($actor,$branch,Capabilities::REPORT_REVIEW);
        Guard::cap($actor,Capabilities::REPORTS_VIEW);
    }
    /** Always lists immutable draft rows; never a delivery state claim. */
    public static function list(Actor $actor,int $branch,string $date):array {
        self::requireReviewer($actor,$branch);
        $date=\ExcelHerbal\ERP7\Core\Input::date($date,'Reminder draft date');
        $db=Db::wpdb();$t=Db::table('report_reminder_drafts');
        $rows=$db->get_results($db->prepare(
            "SELECT id,branch_id,report_type,period_date,target_employee_id,reason,state,dedupe_key,created_at
             FROM {$t} WHERE company_id=%d AND branch_id=%d AND period_date=%s
               AND state='draft' ORDER BY id ASC LIMIT 2001",
            $actor->companyId,$branch,$date),ARRAY_A);
        if(!is_array($rows)||count($rows)>self::MAX_DRAFTS)
            throw new DomainException('Draft list incomplete.','report_draft_source_invalid',500);
        return ['read_only'=>true,'branch_id'=>$branch,'business_date'=>$date,
            'drafts'=>$rows,'dispatch_enabled'=>false,
            'evidence'=>'internal_followup_draft_only_no_delivery'];
    }

    /** Human reviewer discards a stale/internal draft. Does not send, queue or
     * modify the original Daily Order / report attestation.
     */
    public static function dismiss(Actor $actor,int $branch,int $id,string $reason):array {
        self::requireReviewer($actor,$branch);
        $reason=trim($reason);
        if($id<1||strlen($reason)<12||strlen($reason)>500
            ||preg_match('/[\x00-\x08\x0B\x0C\x0E-\x1F]/',$reason))
            throw new DomainException('Invalid dismissal reference or reason.','report_draft_dismiss_invalid',422);
        return Transaction::run(static function()use($actor,$branch,$id,$reason){
            $db=Db::wpdb();$t=Db::table('report_reminder_drafts');
            $row=$db->get_row($db->prepare(
                "SELECT id,state FROM {$t} WHERE id=%d AND company_id=%d AND branch_id=%d FOR UPDATE",
                $id,$actor->companyId,$branch),ARRAY_A);
            if(!is_array($row))
                throw new DomainException('Draft not found in authorized branch.','report_draft_not_found',404);
            if($row['state']!=='draft')
                throw new DomainException('Draft already reviewed.','report_draft_already_dismissed',409);
            $updated=$db->update($t,[
                'state'=>'dismissed','dismissed_by'=>$actor->employeeId,
                'dismissed_at'=>Db::now(),'dismissal_reason'=>$reason,
            ],['id'=>$id,'company_id'=>$actor->companyId,'branch_id'=>$branch,'state'=>'draft']);
            if($updated!==1)
                throw new DomainException('Draft state changed during review.','report_draft_conflict',409);
            Audit::add($actor,'report.reminder_draft.dismiss','report_reminder_draft',$id,
                ['branch_id'=>$branch,'reason'=>$reason,'delivery'=>false]);
            return ['id'=>$id,'branch_id'=>$branch,'state'=>'dismissed',
                'dispatch_enabled'=>false,'notifications_sent'=>0,
                'dismissed_by'=>$actor->employeeId];
        });
    }
    public static function prepare(Actor $actor,int $branch,string $date,
        ?BranchReportingWatchReader $watchReader=null,
        ?ReportingWatchSubmissionReader $submissionReader=null,
        ?\DateTimeImmutable $now=null):array {
        self::requireReviewer($actor,$branch);
        // Projection validates date, active branch and current canonical facts.
        $watch=ReportingWatchSubmissionProjection::view($actor,$date,$branch,$watchReader,$submissionReader,$now);
        $date=$watch['business_date'];
        $eligible=[];
        foreach($watch['reminder_candidates'] as $candidate){
            if((int)$candidate['branch_id']!==$branch
                ||(string)$candidate['business_date']!==$date
                ||(int)$candidate['employee_id']<1
                ||!in_array($candidate['reason'],['no_daily_cycle','evening_not_posted'],true)
                ||($candidate['delivery_state']??null)!=='not_dispatched'){
                throw new DomainException('Invalid canonical daily reminder candidate.','report_draft_source_invalid',500);
            }
            $eligible[]=['type'=>'evening_daily_closing',
                'employee_id'=>(int)$candidate['employee_id'],
                'reason'=>$candidate['reason']];
        }
        foreach($watch['schedule'] as $slot){
            if(!isset($slot['branch_submission_status'])
                ||!is_array($slot['branch_submission_status']))continue;
            // Only report types with a specified 10:30 cutoff can be flagged
            // as time-overdue. For missing Monday/product/salary reports with
            // NO exact SLA, do not create fabricated missed-deadline drafts.
            if(($slot['time']??null)===null
                ||($slot['due_state']??null)!=='past_due')continue;
            foreach($slot['branch_submission_status'] as $state){
                if((int)$state['branch_id']!==$branch)continue;
                if(in_array($state['submission_state'],['not_submitted','rejected'],true)){
                    $eligible[]=['type'=>$state['report_type'],
                        'employee_id'=>0,'reason'=>$state['submission_state']];
                }
            }
        }
        if(count($eligible)>self::MAX_DRAFTS)
            throw new DomainException('Excess follow-up candidates.','report_draft_source_invalid',500);
        return Transaction::run(function()use($actor,$branch,$date,$eligible){
            $db=Db::wpdb();$table=Db::table('report_reminder_drafts');$created=0;
            foreach($eligible as $draft){
                $type=$draft['type'];$employee=$draft['employee_id'];
                $hash=hash('sha256',$actor->companyId.'|'.$branch.'|'.$date.'|'.$type.'|'.$employee);
                // DB-enforced dedupe; duplicate prepares create no new entries.
                $sql=$db->prepare(
                    "INSERT IGNORE INTO {$table}
                     (company_id,branch_id,report_type,period_date,target_employee_id,reason,state,
                      dedupe_key,created_by,created_at)
                     VALUES(%d,%d,%s,%s,%d,%s,'draft',%s,%d,%s)",
                    $actor->companyId,$branch,$type,$date,$employee,$draft['reason'],$hash,
                    $actor->employeeId,Db::now());
                $affected=$db->query($sql);
                if($affected===false)
                    throw new DomainException('Reminder draft write failed.','report_draft_write_failed',500);
                $created+=(int)$affected;
            }
            if($created>0)Audit::add($actor,'report.reminder_draft.prepare','report_reminder_draft',
                $branch,['branch_id'=>$branch,'date'=>$date,'created'=>$created]);
            return ['branch_id'=>$branch,'business_date'=>$date,'eligible'=>count($eligible),
                'created'=>$created,'duplicates_skipped'=>count($eligible)-$created,
                'state'=>'draft_only','dispatch_enabled'=>false,'notifications_sent'=>0,
                'no_automatic_delivery'=>true];
        });
    }
}
