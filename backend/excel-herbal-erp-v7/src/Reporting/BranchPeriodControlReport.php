<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP7\Reporting;

use DateTimeImmutable;
use ExcelHerbal\ERP7\Core\Input;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities,Guard};

/**
 * Weekly/monthly branch control: read-only canonical V7 projection.
 * Each source is aggregated independently to avoid multi-batch fan-out.
 */
interface BranchPeriodControlReader {
    public function cycles(int $company,int $branch,string $from,string $to):array;
    public function custody(int $company,int $branch,string $utcStart,string $utcEnd):array;
    public function performance(int $company,int $branch,string $from,string $to):array;
    public function counter(int $company,int $branch,string $utcStart,string $utcEnd):array;
    public function employeeCashTransit(int $company,int $branch,string $start,string $end):array;
}
final class BranchPeriodControlReport {
    private static function decimal(mixed $raw,int $digits,bool $signed=false):int {
        if(!is_string($raw)&&!is_int($raw))
            throw new DomainException('Period report numeric source must be DECIMAL.','branch_period_source_invalid',500);
        $s=(string)$raw;
        if(!preg_match($signed?'/^-?(0|[1-9][0-9]{0,11})(?:\.([0-9]{1,3}))?$/D':'/^(0|[1-9][0-9]{0,11})(?:\.([0-9]{1,3}))?$/D',$s,$m)
            ||strlen($m[2]??'')>$digits)
            throw new DomainException('Period report source precision invalid.','branch_period_source_invalid',500);
        $unit=10**$digits;$major=(int)$m[1];
        if($major>intdiv(PHP_INT_MAX,$unit))
            throw new DomainException('Period report source overflow.','branch_period_source_invalid',500);
        $n=$major*$unit+(int)str_pad($m[2]??'',$digits,'0');
        return str_starts_with($s,'-')?-$n:$n;
    }
    private static function fmt(int $n,int $digits):string {
        if($n===PHP_INT_MIN)throw new DomainException('Period report output overflow.','branch_period_source_invalid',500);
        $unit=10**$digits;$v=abs($n);
        return ($n<0?'-':'').intdiv($v,$unit).'.'.str_pad((string)($v%$unit),$digits,'0');
    }
    private static function sum(int $one,int $two):int {
        if(($two>0&&$one>PHP_INT_MAX-$two)||($two<0&&$one<PHP_INT_MIN-$two))
            throw new DomainException('Period report total overflow.','branch_period_source_invalid',500);
        return $one+$two;
    }
    /** ISO Monday–Sunday or calendar month; compare with immediately previous period. */
    private static function ranges(string $mode,string $date):array {
        if(!in_array($mode,['week','month'],true))
            throw new DomainException('Period must be week or month.','branch_period_invalid',422);
        $date=Input::date($date,'Branch performance date');
        $d=new DateTimeImmutable($date);
        if($mode==='week') {
            $start=$d->modify('monday this week');
            $end=$start->modify('+6 days');
            $previous=$start->modify('-7 days');
            $previousEnd=$previous->modify('+6 days');
        }else{
            $start=$d->modify('first day of this month');
            $end=$start->modify('last day of this month');
            $previous=$start->modify('-1 month');
            $previousEnd=$previous->modify('last day of this month');
        }
        return [[$start->format('Y-m-d'),$end->format('Y-m-d')],
            [$previous->format('Y-m-d'),$previousEnd->format('Y-m-d')]];
    }
    private static function emptyEmployee(int $id,string $name):array {
        return ['employee_id'=>$id,'employee_name'=>$name,
            'posted_daily_order_sales'=>0,'cash_allocations'=>0,'upi_allocations'=>0,
            'issued_pcs'=>0,'sold_pcs'=>0,'returned_pcs'=>0,
            'custody_in_pcs'=>0,'custody_out_pcs'=>0,'points'=>0,
            'posted_days'=>0,'pending_days'=>0,'pending_requests'=>0,
            'sale_amount_mismatches'=>0,'stock_quantity_mismatches'=>0];
    }
    private static function renderEmployee(array $e,?array $cash):array {
        $record=[
            'employee_id'=>$e['employee_id'],'employee_name'=>$e['employee_name'],
            'posted_daily_order_sales'=>self::fmt($e['posted_daily_order_sales'],2),
            'daily_cash_allocations'=>self::fmt($e['cash_allocations'],2),
            'daily_upi_allocations'=>self::fmt($e['upi_allocations'],2),
            'issued_quantity'=>self::fmt($e['issued_pcs'],3),
            'sold_quantity'=>self::fmt($e['sold_pcs'],3),
            'returned_quantity'=>self::fmt($e['returned_pcs'],3),
            'custody_in_quantity'=>self::fmt($e['custody_in_pcs'],3),
            'custody_out_quantity'=>self::fmt($e['custody_out_pcs'],3),
            'performance_points'=>self::fmt($e['points'],2),
            'posted_days'=>$e['posted_days'],'pending_days'=>$e['pending_days'],
            'pending_requests'=>$e['pending_requests'],
            'sale_amount_mismatches'=>$e['sale_amount_mismatches'],
            'stock_quantity_mismatches'=>$e['stock_quantity_mismatches'],
            'needs_attention'=>$e['pending_days']>0||$e['pending_requests']>0
                ||$e['sale_amount_mismatches']>0||$e['stock_quantity_mismatches']>0,
        ];
        if($cash!==null){
            $record['tagged_cash_in_transit']=[
                'opening_debit_minus_credit'=>self::fmt($cash['opening'],2),
                'period_debit'=>self::fmt($cash['debit'],2),
                'period_credit'=>self::fmt($cash['credit'],2),
                'closing_debit_minus_credit'=>self::fmt(self::sum(self::sum($cash['opening'],$cash['debit']),-$cash['credit']),2),
                'currency'=>'INR','cashier_verified'=>false,
                'basis'=>'posted_employee_tagged_GL_branch_scope',
            ];
        }
        return $record;
    }
    private static function aggregate(BranchPeriodControlReader $source,Actor $actor,int $branch,array $range,bool $finance):array {
        [$from,$to]=$range;
        [$utcFrom,$utcTo]=Input::utcBoundsForBusinessRange($from,$to,'Branch performance period');
        $localFrom=$from.' 00:00:00';
        $localTo=(new DateTimeImmutable($to))->modify('+1 day')->format('Y-m-d').' 00:00:00';
        $c=$source->cycles($actor->companyId,$branch,$from,$to);
        $s=$source->custody($actor->companyId,$branch,$utcFrom,$utcTo);
        $p=$source->performance($actor->companyId,$branch,$from,$to);
        $sales=$source->counter($actor->companyId,$branch,$utcFrom,$utcTo);
        $cash=$finance?$source->employeeCashTransit($actor->companyId,$branch,$localFrom,$localTo):[];
        foreach([$c,$s,$p,$sales,$cash] as $rows)
            if(!is_array($rows)||count($rows)>20000)
                throw new DomainException('Period report must not be silently truncated.','branch_period_source_invalid',500);
        $e=[];$byDay=[];$cycleIds=[];
        $nums=['posted_daily_order_sales'=>0,'daily_cash_allocations'=>0,'daily_upi_allocations'=>0,
            'counter_sales_gross'=>0,'counter_sales_paid'=>0,'counter_sales_outstanding'=>0,
            'issued_quantity'=>0,'sold_quantity'=>0,'returned_quantity'=>0,
            'custody_in_quantity'=>0,'custody_out_quantity'=>0,'performance_points'=>0];
        $counts=['posted_daily_orders'=>0,'pending_daily_orders'=>0,
            'pending_stock_requests'=>0,'sale_amount_mismatches'=>0,
            'stock_quantity_mismatches'=>0,'posted_counter_sales'=>0];
        foreach($c as $r){
            if(!is_array($r)||(int)($r['branch_id']??0)!==$branch
                ||(int)($r['employee_id']??0)<1||(int)($r['cycle_id']??0)<1
                ||!is_string($r['business_date']??null)||$r['business_date']<$from||$r['business_date']>$to)
                throw new DomainException('Period cycle source scope mismatch.','branch_period_source_invalid',500);
            $id=(int)$r['cycle_id'];$employee=(int)$r['employee_id'];$date=$r['business_date'];
            if(isset($cycleIds[$id]))
                throw new DomainException('Duplicate period cycle detected.','branch_period_source_invalid',500);
            $cycleIds[$id]=true;
            $e[$employee]??=self::emptyEmployee($employee,(string)($r['employee_name']??''));
            $e[$employee]['employee_name']=(string)($r['employee_name']??$e[$employee]['employee_name']);
            $byDay[$date]??=['business_date'=>$date,'posted_sales'=>0,'cash_allocations'=>0,
                'upi_allocations'=>0,'posted_daily_orders'=>0,'pending_daily_orders'=>0];
            $pending=(int)($r['pending_requests']??0);
            if($pending<0||$pending>50000)
                throw new DomainException('Invalid period pending count.','branch_period_source_invalid',500);
            $e[$employee]['pending_requests']+=$pending;
            $counts['pending_stock_requests']+=$pending;
            $issue=self::decimal((string)($r['issued_quantity']??'0'),3);
            $nums['issued_quantity']=self::sum($nums['issued_quantity'],$issue);
            $e[$employee]['issued_pcs']=self::sum($e[$employee]['issued_pcs'],$issue);
            $posted=$r['cycle_status']==='completed'&&($r['settlement_status']??null)==='posted';
            if(!$posted){
                $counts['pending_daily_orders']++;
                $e[$employee]['pending_days']++;
                $byDay[$date]['pending_daily_orders']++;
                continue;
            }
            $amount=self::decimal($r['expected_amount']??null,2);
            $cashPaid=self::decimal($r['cash_amount']??null,2);
            $upi=self::decimal($r['upi_amount']??null,2);
            $lineAmount=self::decimal((string)($r['closing_sale_amount']??'0'),2);
            $sold=self::decimal((string)($r['sold_quantity']??'0'),3);
            $returned=self::decimal((string)($r['returned_quantity']??'0'),3);
            foreach([
                ['posted_daily_order_sales','posted_daily_order_sales',$amount],
                ['daily_cash_allocations','cash_allocations',$cashPaid],
                ['daily_upi_allocations','upi_allocations',$upi],
                ['sold_quantity','sold_pcs',$sold],
                ['returned_quantity','returned_pcs',$returned],
            ] as [$totalKey,$employeeKey,$value]){
                $nums[$totalKey]=self::sum($nums[$totalKey],$value);
                $e[$employee][$employeeKey]=self::sum($e[$employee][$employeeKey],$value);
            }
            $counts['posted_daily_orders']++;$e[$employee]['posted_days']++;
            $byDay[$date]['posted_daily_orders']++;
            foreach([['posted_sales',$amount],['cash_allocations',$cashPaid],['upi_allocations',$upi]] as [$k,$v])
                $byDay[$date][$k]=self::sum($byDay[$date][$k],$v);
            if($amount!==self::sum($cashPaid,$upi)||$amount!==$lineAmount){
                $counts['sale_amount_mismatches']++;$e[$employee]['sale_amount_mismatches']++;
            }
            if($issue!==self::sum($sold,$returned)){
                $counts['stock_quantity_mismatches']++;$e[$employee]['stock_quantity_mismatches']++;
            }
        }
        foreach($s as $r){
            if(!is_array($r)||(int)($r['branch_id']??0)!==$branch||(int)($r['employee_id']??0)<1)
                throw new DomainException('Custody period employee/branch mismatch.','branch_period_source_invalid',500);
            $id=(int)$r['employee_id'];$e[$id]??=self::emptyEmployee($id,(string)($r['employee_name']??''));
            foreach([['custody_in_quantity','custody_in_pcs','qty_in'],
                     ['custody_out_quantity','custody_out_pcs','qty_out']] as [$global,$emp,$raw]){
                $v=self::decimal((string)($r[$raw]??'0'),3);
                $nums[$global]=self::sum($nums[$global],$v);
                $e[$id][$emp]=self::sum($e[$id][$emp],$v);
            }
        }
        foreach($p as $r){
            if(!is_array($r)||(int)($r['branch_id']??0)!==$branch||(int)($r['employee_id']??0)<1)
                throw new DomainException('Performance period scope mismatch.','branch_period_source_invalid',500);
            $id=(int)$r['employee_id'];$e[$id]??=self::emptyEmployee($id,(string)($r['employee_name']??''));
            $points=self::decimal((string)($r['points']??'0'),2,true);
            $e[$id]['points']=self::sum($e[$id]['points'],$points);
            $nums['performance_points']=self::sum($nums['performance_points'],$points);
        }
        foreach($sales as $r){
            if(!is_array($r)||(int)($r['branch_id']??0)!==$branch)
                throw new DomainException('Counter sales period branch mismatch.','branch_period_source_invalid',500);
            foreach([['gross_amount','counter_sales_gross'],
                     ['paid_amount','counter_sales_paid'],
                     ['outstanding_amount','counter_sales_outstanding']] as [$field,$k])
                $nums[$k]=self::sum($nums[$k],self::decimal((string)($r[$field]??'0'),2));
            $n=(int)($r['count_sales']??0);
            if($n<0)throw new DomainException('Negative posted counter sale count.','branch_period_source_invalid',500);
            $counts['posted_counter_sales']+=$n;
        }
        $cashMap=[];
        foreach($cash as $r){
            if(!is_array($r)||(int)($r['branch_id']??0)!==$branch||(int)($r['employee_id']??0)<1)
                throw new DomainException('Cash transit period company/branch mismatch.','branch_period_source_invalid',500);
            $id=(int)$r['employee_id'];
            if(isset($cashMap[$id]))throw new DomainException('Duplicate cash-transit employee.','branch_period_source_invalid',500);
            $cashMap[$id]=[
                'opening'=>self::decimal((string)($r['opening_debit_minus_credit']??'0'),2,true),
                'debit'=>self::decimal((string)($r['period_debit']??'0'),2),
                'credit'=>self::decimal((string)($r['period_credit']??'0'),2),
            ];
            $e[$id]??=self::emptyEmployee($id,(string)($r['employee_name']??''));
        }
        $employees=[];
        ksort($e,SORT_NUMERIC);
        foreach($e as $id=>$row)$employees[]=self::renderEmployee($row,$finance?($cashMap[$id]??null):null);
        $counts['employees_with_activity']=count($employees);
        $counts['employees_needing_attention']=count(array_filter($employees,fn($row)=>$row['needs_attention']));
        $totals=$counts;
        foreach($nums as $key=>$v){
            $places=in_array($key,['issued_quantity','sold_quantity','returned_quantity','custody_in_quantity','custody_out_quantity'],true)?3:2;
            $totals[$key]=self::fmt($v,$places);
        }
        ksort($byDay,SORT_STRING);
        $days=[];
        foreach($byDay as $day){
            foreach(['posted_sales','cash_allocations','upi_allocations'] as $key)$day[$key]=self::fmt($day[$key],2);
            $days[]=$day;
        }
        return ['period'=>['from'=>$from,'to'=>$to],
            'totals'=>$totals,'employees'=>$employees,'days'=>$days];
    }
    public static function view(Actor $actor,int $branch,string $mode,string $date,?BranchPeriodControlReader $reader=null):array {
        Guard::branch($actor,$branch,Capabilities::REPORTS_VIEW);
        [$current,$previous]=self::ranges($mode,$date);
        $reader??=new BranchPeriodControlWpReader();
        $finance=$actor->can(Capabilities::ACCOUNTING_VIEW);
        $now=self::aggregate($reader,$actor,$branch,$current,$finance);
        $prior=self::aggregate($reader,$actor,$branch,$previous,$finance);
        $delta=self::decimal($now['totals']['posted_daily_order_sales'],2,true)
              -self::decimal($prior['totals']['posted_daily_order_sales'],2,true);
        return [
            'read_only'=>true,'company_id'=>$actor->companyId,
            'branch_id'=>$branch,'mode'=>$mode,'period'=>$now['period'],
            'totals'=>$now['totals'],'employees'=>$now['employees'],'days'=>$now['days'],
            'previous_period'=>['period'=>$prior['period'],'totals'=>$prior['totals']],
            'posted_daily_order_sales_delta'=>self::fmt($delta,2),
            'financial_visibility'=>$finance?'accounting_role_only':'hidden',
            'comparison_basis'=>'full_calendar_period_not_working_day_normalized',
            'scope'=>'single_authorized_branch_canonical_v7',
            'coverage'=>[
                'cashier_handover_verified'=>false,'upi_bank_verified'=>false,
                'physical_stock_verified'=>false,
                'cash_transit_is_tagged_gl_not_verified_deposit'=>$finance,
                'counter_sales_separate_from_daily_orders'=>true,
                'b2b_unmigrated_preview_excluded'=>true,
            ],
            'warning'=>'Cash/UPI are posted Daily Order allocations, not independently verified bank/cashier deposits. Tagged Cash-in-Transit GL is available only to finance roles and is not a physical receipt.'
        ];
    }
}

/** Five aggregate queries per period, not 31 daily roundtrips. */
final class BranchPeriodControlWpReader implements BranchPeriodControlReader {
    private function rows(string $sql,array $args):array {
        $db=Db::wpdb();$q=$db->prepare($sql,...$args);
        if(!is_string($q)||$q==='')throw new DomainException('Branch period SQL prepare failed.','branch_period_query_failed',500);
        $rows=$db->get_results($q,ARRAY_A);
        if(!is_array($rows))throw new DomainException('Branch period SQL failed.','branch_period_query_failed',500);
        return $rows;
    }
    public function cycles(int $co,int $branch,string $from,string $to):array {
        $c=Db::table('daily_cycles');$e=Db::table('employees');
        $es=Db::table('evening_settlements');$r=Db::table('daily_requests');
        $il=Db::table('daily_issue_lines');$el=Db::table('evening_lines');
        $sql='SELECT c.id cycle_id,c.employee_id,c.branch_id,c.business_date,e.full_name employee_name,'
            .'c.status cycle_status,es.status settlement_status,es.expected_amount,es.cash_amount,es.upi_amount,'
            .'COALESCE(issued.issued_quantity,0) issued_quantity,'
            .'COALESCE(closed.sold_quantity,0) sold_quantity,'
            .'COALESCE(closed.returned_quantity,0) returned_quantity,'
            .'COALESCE(closed.closing_sale_amount,0) closing_sale_amount,'
            .'COALESCE(pending.pending_requests,0) pending_requests '
            .'FROM '.$c.' c JOIN '.$e.' e ON e.id=c.employee_id AND e.company_id=c.company_id '
            .'LEFT JOIN '.$es.' es ON es.daily_cycle_id=c.id '
            .'LEFT JOIN (SELECT r.daily_cycle_id,SUM(il.quantity) issued_quantity '
            .'FROM '.$r.' r JOIN '.$il.' il ON il.daily_request_id=r.id GROUP BY r.daily_cycle_id) issued '
            .'ON issued.daily_cycle_id=c.id '
            .'LEFT JOIN (SELECT evening_settlement_id,'
            .'SUM(retail_quantity+wholesale_quantity) sold_quantity,'
            .'SUM(return_quantity) returned_quantity,SUM(total_amount) closing_sale_amount '
            .'FROM '.$el.' GROUP BY evening_settlement_id) closed ON closed.evening_settlement_id=es.id '
            ."LEFT JOIN (SELECT daily_cycle_id,SUM(CASE WHEN status IN ('draft','submitted','approved') "
            .'THEN 1 ELSE 0 END) pending_requests FROM '.$r.' GROUP BY daily_cycle_id) pending '
            .'ON pending.daily_cycle_id=c.id '
            .'WHERE c.company_id=%d AND c.branch_id=%d AND c.business_date BETWEEN %s AND %s '
            .'ORDER BY c.business_date,c.employee_id';
        return $this->rows($sql,[$co,$branch,$from,$to]);
    }
    public function custody(int $co,int $branch,string $start,string $end):array {
        $sql='SELECT sl.branch_id,sl.custodian_employee_id employee_id,MAX(e.full_name) employee_name,'
            ."SUM(CASE WHEN sl.direction='IN' THEN sl.quantity ELSE 0 END) qty_in,"
            ."SUM(CASE WHEN sl.direction='OUT' THEN sl.quantity ELSE 0 END) qty_out "
            .'FROM '.Db::table('stock_ledger').' sl '
            .'LEFT JOIN '.Db::table('employees').' e ON e.id=sl.custodian_employee_id AND e.company_id=sl.company_id '
            .'WHERE sl.company_id=%d AND sl.branch_id=%d AND sl.custodian_employee_id IS NOT NULL '
            ."AND sl.direction IN ('IN','OUT') AND sl.occurred_at>=%s AND sl.occurred_at<%s "
            .'GROUP BY sl.branch_id,sl.custodian_employee_id';
        return $this->rows($sql,[$co,$branch,$start,$end]);
    }
    public function performance(int $co,int $branch,string $from,string $to):array {
        $sql='SELECT p.branch_id,p.employee_id,MAX(e.full_name) employee_name,SUM(p.points) points '
            .'FROM '.Db::table('performance_entries').' p '
            .'LEFT JOIN '.Db::table('employees').' e ON e.id=p.employee_id AND e.company_id=p.company_id '
            .'WHERE p.company_id=%d AND p.branch_id=%d AND p.business_date BETWEEN %s AND %s '
            .'GROUP BY p.branch_id,p.employee_id';
        return $this->rows($sql,[$co,$branch,$from,$to]);
    }
    public function counter(int $co,int $branch,string $start,string $end):array {
        $sql='SELECT branch_id,COUNT(*) count_sales,SUM(gross_amount) gross_amount,'
            .'SUM(paid_amount) paid_amount,SUM(outstanding_amount) outstanding_amount '
            .'FROM '.Db::table('counter_sales')
            ." WHERE company_id=%d AND branch_id=%d AND status='posted' "
            .'AND sale_date>=%s AND sale_date<%s GROUP BY branch_id';
        return $this->rows($sql,[$co,$branch,$start,$end]);
    }
    public function employeeCashTransit(int $co,int $branch,string $start,string $end):array {
        $sql='SELECT j.branch_id,l.party_id employee_id,MAX(e.full_name) employee_name,'
            .'SUM(CASE WHEN j.entry_date<%s THEN l.debit-l.credit ELSE 0 END) opening_debit_minus_credit,'
            .'SUM(CASE WHEN j.entry_date>=%s THEN l.debit ELSE 0 END) period_debit,'
            .'SUM(CASE WHEN j.entry_date>=%s THEN l.credit ELSE 0 END) period_credit '
            .'FROM '.Db::table('journal_lines').' l '
            .'JOIN '.Db::table('journal_entries').' j ON j.id=l.journal_entry_id '
            .'JOIN '.Db::table('accounts').' a ON a.id=l.account_id AND a.company_id=j.company_id '
            .'LEFT JOIN '.Db::table('employees').' e ON e.id=l.party_id AND e.company_id=j.company_id '
            ."WHERE j.company_id=%d AND j.branch_id=%d AND j.status='posted' "
            ."AND a.code='EMPLOYEE_CASH_IN_TRANSIT' AND l.party_type='employee' "
            .'AND j.entry_date<%s GROUP BY j.branch_id,l.party_id';
        return $this->rows($sql,[$start,$start,$start,$co,$branch,$end]);
    }
}
