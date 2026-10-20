<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP7\Reporting;

use DateTimeImmutable;
use DateTimeZone;
use ExcelHerbal\ERP7\Core\Input;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities,Guard};

/**
 * UAT READ-ONLY schedule-aware manager dashboard. Does not send reminders,
 * mutate WordPress data, start a cron job or assert submitted reports without
 * independent submission evidence. Only V7 FSE active/eligible roster and
 * posted Daily Order evening settlements are corroborated.
 */
interface BranchReportingWatchReader {
    /** @param int[] $ids @return array<int,string> active branch id => name */
    public function branches(int $company,array $ids):array;
    /** @return list<array<string,mixed>> FSE roster with cycle/settlement evidence */
    public function dailyRoster(int $company,int $branch,string $date):array;
    /** @return array<string,mixed> canonical existing daily report */
    public function dailyReport(Actor $actor,int $branch,string $date):array;
}

final class BranchReportingWatch {
    private const DAILY_CUTOFF='19:30:00';
    private const MONTHLY_CUTOFF='10:30:00';
    private const MAX_BRANCHES=12;
    private const MAX_FIELD_STAFF=2000;

    private static function schedule(string $businessDate,DateTimeImmutable $asOf):array {
        $d=new DateTimeImmutable($businessDate.' 00:00:00',$asOf->getTimezone());
        $day=(int)$d->format('N');$monthDay=(int)$d->format('j');
        $slots=[['id'=>'evening_daily_closing','label'=>'Evening Daily Closing',
            'time'=>'19:30','evidence'=>'v7_posted_evening_settlement']];
        if($day===1){
            $slots[]=['id'=>'monday_weekly_report','label'=>'Monday Weekly Branch Report',
                'time'=>null,'evidence'=>'submission_registry_not_integrated'];
            $slots[]=['id'=>'monday_product_order','label'=>'Monday Product Order',
                'time'=>null,'evidence'=>'submission_registry_not_integrated'];
        }
        if($day===2)$slots[]=['id'=>'tuesday_product_order','label'=>'Tuesday Product Order',
            'time'=>null,'evidence'=>'submission_registry_not_integrated'];
        if($monthDay===1)$slots[]=['id'=>'monthly_first_report','label'=>'1st Monthly Report',
            'time'=>'10:30','evidence'=>'submission_registry_not_integrated'];
        if($monthDay===10)$slots[]=['id'=>'salary_receipt_deadline','label'=>'Salary Receipt Report Due by 10th',
            'time'=>null,'evidence'=>'submission_registry_not_integrated'];
        foreach($slots as &$slot){
            $cutoff=$slot['time']===null?'23:59:59':$slot['time'].':00';
            $deadline=new DateTimeImmutable($businessDate.' '.$cutoff,$asOf->getTimezone());
            $slot['deadline_at']=$deadline->format('Y-m-d\TH:i:sP');
            $slot['due_state']=$asOf>$deadline?'past_due':($asOf->format('Y-m-d')===$businessDate?'due_today':'scheduled');
            $slot['submission_state']=$slot['evidence']==='submission_registry_not_integrated'
                ?'verification_unavailable':'evaluate_daily_closing';
            $slot['notification_sent']=false;
        }
        unset($slot);
        return $slots;
    }

    public static function view(
        Actor $actor,string $date,?int $branchId=null,
        ?BranchReportingWatchReader $reader=null,?DateTimeImmutable $asOf=null
    ):array {
        Guard::cap($actor,Capabilities::REPORTS_VIEW);
        $date=Input::date($date,'Reporting watch business date');
        $asOf??=new DateTimeImmutable(current_time('mysql'),wp_timezone());
        // Compare in WordPress business timezone; an HTTP caller never supplies
        // a fake clock to accelerate reports or trigger reminder candidates.
        $asOf=$asOf->setTimezone(wp_timezone());
        $diff=(new DateTimeImmutable($date.' 00:00:00',wp_timezone()))
            ->diff(new DateTimeImmutable($asOf->format('Y-m-d').' 00:00:00',wp_timezone()));
        if((int)$diff->days>31)
            throw new DomainException('Reporting watch limited to a 31-day operational window.','watch_date_out_of_range',422);
        if($branchId!==null) {
            Guard::branch($actor,$branchId,Capabilities::REPORTS_VIEW);
            $ids=[$branchId];
        } else {
            $ids=array_values(array_unique($actor->branchIds));
            sort($ids,SORT_NUMERIC);
        }
        if(!$ids||count($ids)>self::MAX_BRANCHES)
            throw new DomainException('Watch limited to 1–12 authorized branches.','watch_branch_scope_invalid',422);
        foreach($ids as $id){
            if(!is_int($id)||$id<1)
                throw new DomainException('Invalid authorized branch identifier.','watch_branch_scope_invalid',422);
            Guard::branch($actor,$id,Capabilities::REPORTS_VIEW);
        }
        $reader??=new BranchReportingWatchWpReader();
        $names=$reader->branches($actor->companyId,$ids);
        if(!is_array($names)||count($names)!==count($ids))
            throw new DomainException('Reporting watch requires active, company-owned branches.','watch_branch_inactive',403);
        foreach($ids as $id)
            if(!isset($names[$id])||!is_string($names[$id])||trim($names[$id])==='')
                throw new DomainException('Reporting branch inactive/unnamed.','watch_branch_inactive',403);
        $templates=self::schedule($date,$asOf);
        $branchRows=[];$candidates=[];$summary=[
            'branches'=>0,'eligible_field_staff'=>0,'posted_evening_closings'=>0,
            'missing_daily_cycles'=>0,'unposted_evening_closings'=>0,
            'past_due_unposted_or_missing'=>0,'branch_exceptions'=>0];
        foreach($ids as $branch){
            $staff=$reader->dailyRoster($actor->companyId,$branch,$date);
            if(!is_array($staff)||count($staff)>self::MAX_FIELD_STAFF)
                throw new DomainException('Watch field employee roster incomplete.','watch_source_invalid',500);
            $seen=[];$eligible=0;$posted=0;$missing=0;$unposted=0;$staffRows=[];
            foreach($staff as $raw){
                if(!is_array($raw)||(int)($raw['employee_id']??0)<1
                    ||(int)($raw['branch_id']??0)!==$branch)
                    throw new DomainException('Watch employee roster authority mismatch.','watch_source_invalid',500);
                $id=(int)$raw['employee_id'];
                if(isset($seen[$id]))
                    throw new DomainException('Duplicate FSE roster entry.','watch_source_invalid',500);
                $seen[$id]=true;$eligible++;
                $cycle=$raw['cycle_id']??null;
                if($cycle!==null&&(int)$cycle<1)
                    throw new DomainException('Watch cycle reference invalid.','watch_source_invalid',500);
                $complete=($raw['cycle_status']??null)==='completed'
                    &&($raw['settlement_status']??null)==='posted';
                $state=$complete?'posted':($cycle===null?'no_daily_cycle':'evening_not_posted');
                if($complete)$posted++;
                elseif($cycle===null)$missing++;
                else $unposted++;
                $staffRows[]=[
                    'employee_id'=>$id,'employee_name'=>(string)($raw['employee_name']??''),
                    'closing_state'=>$state,'daily_cycle_id'=>$cycle===null?null:(int)$cycle,
                ];
                if(!$complete&&$asOf>new DateTimeImmutable($date.' '.self::DAILY_CUTOFF,$asOf->getTimezone())){
                    $candidates[]=[
                        'branch_id'=>$branch,'employee_id'=>$id,'business_date'=>$date,
                        'reason'=>$state,
                        'deduplication_key'=>hash('sha256',implode('|',[$actor->companyId,$branch,$date,$id,'evening_daily_closing'])),
                        'delivery_state'=>'not_dispatched',
                    ];
                }
            }
            $report=$reader->dailyReport($actor,$branch,$date);
            if(!is_array($report)||($report['read_only']??null)!==true
                ||(int)($report['branch_id']??0)!==$branch
                ||($report['business_date']??null)!==$date
                ||($report['scope']??null)!=='single_authorized_branch_canonical_v7'
                ||($report['coverage']['cashier_handover_verified']??null)!==false
                ||($report['coverage']['upi_bank_verified']??null)!==false
                ||!is_array($report['totals']??null))
                throw new DomainException('Existing canonical daily report contract invalid.','watch_source_invalid',500);
            $overdue=$asOf>new DateTimeImmutable($date.' '.self::DAILY_CUTOFF,$asOf->getTimezone())
                ?$missing+$unposted:0;
            $summary['branches']++;$summary['eligible_field_staff']+=$eligible;
            $summary['posted_evening_closings']+=$posted;
            $summary['missing_daily_cycles']+=$missing;
            $summary['unposted_evening_closings']+=$unposted;
            $summary['past_due_unposted_or_missing']+=$overdue;
            if($overdue>0||(int)($report['totals']['pending_requests']??0)>0)$summary['branch_exceptions']++;
            $branchRows[]=[
                'branch_id'=>$branch,'branch_name'=>$names[$branch],
                'eligible_field_staff'=>$eligible,
                'posted_evening_closings'=>$posted,
                'missing_daily_cycles'=>$missing,
                'unposted_evening_closings'=>$unposted,
                'past_due_unposted_or_missing'=>$overdue,
                'posted_daily_order_sales'=>$report['totals']['posted_daily_order_sales']??null,
                'pending_stock_requests'=>$report['totals']['pending_requests']??null,
                'employees'=>$staffRows,
            ];
        }
        usort($branchRows,static fn($x,$y)=>$y['past_due_unposted_or_missing']<=>$x['past_due_unposted_or_missing']
            ?: $x['branch_id']<=>$y['branch_id']);
        foreach($templates as &$slot){
            if($slot['id']==='evening_daily_closing'){
                $slot['submission_state']=$summary['eligible_field_staff']===0?'no_eligible_field_staff'
                    :($summary['posted_evening_closings']===$summary['eligible_field_staff']?'posted_for_all_eligible'
                    :($slot['due_state']==='past_due'?'overdue_evidence':'pending_before_cutoff'));
            }
        }
        unset($slot);
        return [
            'read_only'=>true,'business_date'=>$date,
            'as_of_local'=>$asOf->format('Y-m-d\TH:i:sP'),
            'timezone'=>$asOf->getTimezone()->getName(),
            'scope'=>'authenticated_authorized_active_branches_only',
            'summary'=>$summary,'branches'=>$branchRows,'schedule'=>$templates,
            'reminder_candidates'=>$candidates,
            'delivery_enabled'=>false,'automatic_notifications_sent'=>0,
            'coverage'=>[
                'fse_only_roster'=>true,
                'approved_leave_and_holiday_excluded'=>true,
                'daily_status_from_original_v7_posted_evening'=>true,
                'weekly_monthly_product_salary_submission_evidence_integrated'=>false,
                'cashier_handover_verified'=>false,'upi_bank_verified'=>false,
            ],
            'warning'=>'Schedule is evaluated on read. Reminder candidates are NOT sent. Weekly/monthly/product/salary receipt submission registry is not integrated; do not infer missed submissions. FSE roster only; holidays and approved leave excluded. Cash/UPI is not verified bank evidence.',
        ];
    }
}

final class BranchReportingWatchWpReader implements BranchReportingWatchReader {
    private function rows(string $sql,array $args):array {
        $db=Db::wpdb();$prepared=$db->prepare($sql,...$args);
        if(!is_string($prepared)||$prepared==='')
            throw new DomainException('Watch SQL preparation failed.','watch_source_invalid',500);
        $out=$db->get_results($prepared,ARRAY_A);
        if(!is_array($out))throw new DomainException('Watch SQL failed.','watch_source_invalid',500);
        return $out;
    }
    public function branches(int $company,array $ids):array {
        if(!$ids||count($ids)>12)throw new DomainException('Invalid branch count.','watch_branch_scope_invalid',422);
        $sql='SELECT id,name FROM '.Db::table('branches')
            .' WHERE company_id=%d AND status=%s AND id IN ('
            .implode(',',array_fill(0,count($ids),'%d')).')';
        $records=$this->rows($sql,array_merge([$company,'active'],$ids));
        $out=[];foreach($records as $r)$out[(int)$r['id']]=(string)$r['name'];
        return $out;
    }
    public function dailyRoster(int $company,int $branch,string $date):array {
        $sql='SELECT e.id employee_id,e.full_name employee_name,e.assigned_branch_id branch_id,'
            .'c.id cycle_id,c.status cycle_status,s.status settlement_status '
            .'FROM '.Db::table('employees').' e '
            .'LEFT JOIN '.Db::table('daily_cycles').' c ON c.company_id=e.company_id '
            .'AND c.employee_id=e.id AND c.branch_id=e.assigned_branch_id AND c.business_date=%s '
            .'LEFT JOIN '.Db::table('evening_settlements').' s ON s.daily_cycle_id=c.id '
            .'WHERE e.company_id=%d AND e.assigned_branch_id=%d '
            ."AND e.status='active' AND e.designation_code='FSE' "
            .'AND NOT EXISTS (SELECT 1 FROM '.Db::table('leave_requests')
            ." l WHERE l.company_id=e.company_id AND l.employee_id=e.id AND l.status='approved' "
            .'AND l.date_from<=%s AND l.date_to>=%s) '
            .'AND NOT EXISTS (SELECT 1 FROM '.Db::table('holidays')
            .' h WHERE h.company_id=e.company_id AND h.active=1 '
            .'AND (h.branch_id IS NULL OR h.branch_id=e.assigned_branch_id) AND h.holiday_date=%s) '
            .'ORDER BY e.id';
        return $this->rows($sql,[$date,$company,$branch,$date,$date,$date]);
    }
    public function dailyReport(Actor $actor,int $branch,string $date):array {
        return BranchDailyControlReport::view($actor,$branch,$date);
    }
}
