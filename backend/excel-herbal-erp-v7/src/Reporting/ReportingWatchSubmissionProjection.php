<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP7\Reporting;

use DateTimeImmutable;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities};

/**
 * Corroborates BranchReportingWatch schedules against the real V7 submission
 * registry, without treating a manager's attestation as bank/stock/payroll
 * verification. No writes, cron, queue dispatch or HTTP destinations.
 */
interface ReportingWatchSubmissionReader {
    /** @param list<int> $branches @return list<array<string,mixed>> */
    public function rows(int $company,array $branches,string $date):array;
}
final class ReportingWatchSubmissionProjection {
    private const TYPE_MAP=[
        'monday_weekly_report'=>'weekly_report',
        'monday_product_order'=>'product_order_mon',
        'tuesday_product_order'=>'product_order_tue',
        'monthly_first_report'=>'monthly_report',
        'salary_receipt_deadline'=>'salary_receipts',
    ];
    private const ACCEPT=['submitted','approved','rejected'];

    public static function view(Actor $actor,string $date,?int $branchId=null,
        ?BranchReportingWatchReader $watchSource=null,
        ?ReportingWatchSubmissionReader $source=null,
        ?DateTimeImmutable $now=null):array {
        $watch=BranchReportingWatch::view($actor,$date,$branchId,$watchSource,$now);
        $active=[];
        foreach($watch['branches'] as $branch){
            $id=(int)$branch['branch_id'];
            if($id<1||isset($active[$id]))
                throw new DomainException('Invalid watch branch projection.','report_watch_source_invalid',500);
            $active[$id]=true;
        }
        if(!$active||count($active)>12)
            throw new DomainException('Watch branch authority not available.','report_watch_source_invalid',500);
        $source??=new ReportingWatchSubmissionWpReader();
        $raw=$source->rows($actor->companyId,array_keys($active),$date);
        if(!is_array($raw)||count($raw)>60)
            throw new DomainException('Submission status query incomplete.','report_watch_source_invalid',500);

        $byBranch=[];$unverified=0;$summary=[
            'approved'=>0,'submitted'=>0,'rejected'=>0,
            'not_submitted'=>0,'hidden_salary_slots'=>0
        ];
        foreach($raw as $row){
            if(!is_array($row)
                ||(int)($row['company_id']??0)!==$actor->companyId
                ||!isset($active[(int)($row['branch_id']??0)])
                ||($row['period_date']??null)!==$date
                ||!in_array($row['report_type']??null,array_values(self::TYPE_MAP),true)
                ||!in_array($row['status']??null,self::ACCEPT,true)
                ||(int)($row['id']??0)<1||(int)($row['revision']??0)<1) {
                throw new DomainException('Submission source authority or state invalid.','report_watch_source_invalid',500);
            }
            $branch=(int)$row['branch_id'];
            $type=(string)$row['report_type'];
            if(isset($byBranch[$branch][$type]))
                throw new DomainException('Duplicate branch reporting attestation.','report_watch_source_invalid',500);
            $byBranch[$branch][$type]=[
                'status'=>$row['status'],
                'submission_id'=>(int)$row['id'],
                'revision'=>(int)$row['revision'],
                'submitted_by'=>(int)($row['submitted_by']??0),
                'reviewed_by'=>isset($row['reviewed_by'])?(int)$row['reviewed_by']:null
            ];
            if($byBranch[$branch][$type]['submitted_by']<1)
                throw new DomainException('Invalid submission owner.','report_watch_source_invalid',500);
        }
        $businessDate=$watch['business_date'];
        $clock=new DateTimeImmutable((string)$watch['as_of_local']);
        $isSalaryAllowed=$actor->can(Capabilities::SALARY_VIEW);
        $slots=[];
        foreach($watch['schedule'] as $template){
            $slotId=$template['id']??'';
            if(!isset(self::TYPE_MAP[$slotId])){
                $slots[]=$template;continue;
            }
            $type=self::TYPE_MAP[$slotId];
            if($type==='salary_receipts'&&!$isSalaryAllowed) {
                $summary['hidden_salary_slots']+=count($active);continue;
            }
            $states=[];
            foreach(array_keys($active) as $branch){
                $proof=$byBranch[$branch][$type]??null;
                $state=$proof['status']??'not_submitted';
                $details=[
                    'branch_id'=>$branch,
                    'report_type'=>$type,
                    'submission_state'=>$state,
                    'submission_id'=>$proof['submission_id']??null,
                    'revision'=>$proof['revision']??null,
                    'external_verification'=>false,
                ];
                if($proof!==null){
                    $details['submitted_by']=$proof['submitted_by'];
                    $details['reviewed_by']=$proof['reviewed_by'];
                }
                $states[]=$details;
                $summary[$state]++;
                if($state==='not_submitted')$unverified++;
            }
            $template['branch_submission_status']=$states;
            $template['submission_state']=count(array_filter($states,
                static fn(array $e):bool=>$e['submission_state']==='approved'))===count($states)
                ?'approved_all_branches'
                :(count(array_filter($states,
                    static fn(array $e):bool=>$e['submission_state']==='not_submitted'))===count($states)
                        ?'not_submitted_all_branches':'mixed_branch_submission_states');
            $template['evidence']='canonical_v7_manager_attestation_only';
            $template['notification_sent']=false;
            // 23:59:59 in the legacy watch was a display fallback, not an
            // agreed reporting SLA. It must not generate an overdue flag.
            if($template['time']===null){
                $template['due_state']=$businessDate<$clock->format('Y-m-d')
                    ?'date_passed_deadline_unspecified':'deadline_unspecified';
            }
            $slots[]=$template;
        }
        $watch['schedule']=$slots;
        foreach($watch['branches'] as &$branch){
            $id=(int)$branch['branch_id'];
            $branch['reporting_submissions']=array_values(array_filter(array_merge(
                ...array_map(static fn(array $slot):array=>$slot['branch_submission_status']??[],
                    $slots)),
                static fn(array $e):bool=>$e['branch_id']===$id));
        }
        unset($branch);
        $watch['submission_evidence_summary']=$summary;
        $watch['coverage']['weekly_monthly_product_salary_submission_evidence_integrated']=true;
        $watch['coverage']['salary_submission_evidence_hidden_without_permission']=true;
        $watch['coverage']['unverified_external_payment_or_stock']='never_claimed';
        $watch['submission_registry_read_only']=true;
        $watch['reminder_outbox_dispatch_enabled']=false;
        $watch['reminder_draft_preview']=[];
        $watch['warning']='Manager reporting submissions are human attestations only; not independent bank, physical stock, payroll or salary receipt verification. No reminders dispatched. Schedule time absent means no exact overdue SLA.';
        return $watch;
    }
}

final class ReportingWatchSubmissionWpReader implements ReportingWatchSubmissionReader {
    public function rows(int $company,array $branches,string $date):array {
        if(!$branches||count($branches)>12)
            throw new DomainException('Invalid reporting watch lookup scope.','report_watch_source_invalid',500);
        $db=Db::wpdb();
        $place=implode(',',array_fill(0,count($branches),'%d'));
        $sql='SELECT id,company_id,branch_id,report_type,period_date,status,revision,submitted_by,reviewed_by FROM '
            .Db::table('report_submissions')
            .' WHERE company_id=%d AND branch_id IN ('.$place.') AND period_date=%s LIMIT 61';
        $query=$db->prepare($sql,...array_merge([$company],$branches,[$date]));
        if(!is_string($query)||$query==='')throw new DomainException('Invalid reporting watch query.','report_watch_source_invalid',500);
        $rows=$db->get_results($query,ARRAY_A);
        if(!is_array($rows))throw new DomainException('Submission lookup failed.','report_watch_source_invalid',500);
        return $rows;
    }
}
