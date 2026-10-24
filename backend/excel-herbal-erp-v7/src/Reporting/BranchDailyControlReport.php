<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP7\Reporting;

use ExcelHerbal\ERP7\Core\Input;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities,Guard};

/**
 * Branch-manager one-day closing report, READ ONLY, canonical V7 data.
 *
 * Daily Order sales, counter sales, custody movements and points are
 * independently sourced to prevent multi-line join multiplication.
 * Report amounts are NOT independent cashier receipt or bank proofs.
 */
interface BranchDailyControlReader {
    public function cycles(int $company,int $branch,string $date):array;
    public function custody(int $company,int $branch,string $utcStart,string $utcEnd):array;
    public function performance(int $company,int $branch,string $date):array;
    public function counterSales(int $company,int $branch,string $utcStart,string $utcEnd):array;
}

final class BranchDailyControlReport {
    private static function scaled(mixed $raw,int $places):int {
        if(!is_string($raw)&&!is_int($raw))
            throw new DomainException('Branch report numeric source must be exact DECIMAL.','branch_report_source_invalid',500);
        $v=(string)$raw;
        if(!preg_match('/^(0|[1-9][0-9]{0,11})(?:\.([0-9]{1,3}))?$/D',$v,$m)
            ||strlen($m[2]??'')>$places)
            throw new DomainException('Branch report invalid canonical precision.','branch_report_source_invalid',500);
        $unit=10**$places;
        if((int)$m[1]>intdiv(PHP_INT_MAX,$unit))
            throw new DomainException('Branch report total too large.','branch_report_source_invalid',500);
        return (int)$m[1]*$unit+(int)str_pad($m[2]??'',$places,'0');
    }
    private static function fixed(int $n,int $places):string {
        $unit=10**$places;
        return intdiv($n,$unit).'.'.str_pad((string)($n%$unit),$places,'0',STR_PAD_LEFT);
    }
    private static function add(int &$total,int $value):void {
        if($value<0||$total>PHP_INT_MAX-$value)
            throw new DomainException('Branch report sum overflow.','branch_report_source_invalid',500);
        $total+=$value;
    }
    public static function view(Actor $actor,int $branch,string $date,?BranchDailyControlReader $reader=null):array {
        Guard::branch($actor,$branch,Capabilities::REPORTS_VIEW);
        $date=Input::date($date,'Branch reporting date');
        [$startUtc,$endUtc]=Input::utcBoundsForBusinessRange($date,$date,'Branch reporting date');
        $reader=$reader??new BranchDailyControlWpReader();
        $cycles=$reader->cycles($actor->companyId,$branch,$date);
        $custody=$reader->custody($actor->companyId,$branch,$startUtc,$endUtc);
        $performance=$reader->performance($actor->companyId,$branch,$date);
        $counter=$reader->counterSales($actor->companyId,$branch,$startUtc,$endUtc);
        foreach([$cycles,$custody,$performance,$counter] as $set)
            if(!is_array($set)||count($set)>2000)
                throw new DomainException('Branch daily report exceeded complete-source limit.','branch_report_source_invalid',500);
        $rows=[];$seenCycles=[];
        $empty=static fn(int $employee,string $name):array=>[
            'employee_id'=>$employee,'employee_name'=>$name,
            'cycle_id'=>null,'cycle_status'=>'missing_daily_cycle',
            'settlement_status'=>'missing','posted_sale_amount'=>'0.00',
            'posted_cash_split'=>'0.00','posted_upi_split'=>'0.00',
            'issued_quantity'=>'0.000','sold_quantity'=>'0.000','returned_quantity'=>'0.000',
            'custody_in_quantity'=>'0.000','custody_out_quantity'=>'0.000',
            'performance_points'=>'0.00','pending_requests'=>0,'exceptions'=>[],
        ];
        $tot=['posted_daily_order_sales'=>0,'cash_split'=>0,'upi_split'=>0,
            'issued_pcs'=>0,'sold_pcs'=>0,'returned_pcs'=>0,
            'custody_in_pcs'=>0,'custody_out_pcs'=>0,'performance_points'=>0,
            'posted_daily_orders'=>0,'pending_cycles'=>0,'pending_requests'=>0,
            'employees_with_activity'=>0,'employees_needing_attention'=>0,
            'counter_sales_gross'=>0,'counter_sales_paid'=>0,
            'counter_sales_outstanding'=>0,'posted_counter_sales'=>0];
        foreach($cycles as $cycle){
            if(!is_array($cycle)||(int)($cycle['employee_id']??0)<1
                ||(int)($cycle['cycle_id']??0)<1
                ||(int)($cycle['branch_id']??0)!==$branch)
                throw new DomainException('Invalid branch daily cycle source.','branch_report_source_invalid',500);
            $employee=(int)$cycle['employee_id'];
            if(isset($rows[$employee]))throw new DomainException('Duplicate Daily Order for one branch/employee/day.','branch_report_source_invalid',500);
            $rows[$employee]=$empty($employee,(string)($cycle['employee_name']??''));
            $r=&$rows[$employee];$r['cycle_id']=(int)$cycle['cycle_id'];
            $r['cycle_status']=(string)$cycle['cycle_status'];
            $r['settlement_status']=(string)($cycle['settlement_status']??'missing');
            $posted=$r['cycle_status']==='completed'&&$r['settlement_status']==='posted';
            $r['pending_requests']=(int)($cycle['pending_requests']??0);
            if($r['pending_requests']<0)throw new DomainException('Negative pending request count.','branch_report_source_invalid',500);
            self::add($tot['pending_requests'],$r['pending_requests']);
            if(!$posted){self::add($tot['pending_cycles'],1);$r['exceptions'][]='evening_not_posted';}
            if($r['pending_requests']>0)$r['exceptions'][]='pending_stock_approval_or_issue';
            $issue=self::scaled((string)($cycle['issued_quantity']??'0'),3);
            $sold=$posted?self::scaled((string)($cycle['sold_quantity']??'0'),3):0;
            $returned=$posted?self::scaled((string)($cycle['returned_quantity']??'0'),3):0;
            $r['issued_quantity']=self::fixed($issue,3);
            $r['sold_quantity']=self::fixed($sold,3);
            $r['returned_quantity']=self::fixed($returned,3);
            self::add($tot['issued_pcs'],$issue);self::add($tot['sold_pcs'],$sold);
            self::add($tot['returned_pcs'],$returned);
            if($posted){
                $sale=self::scaled((string)$cycle['expected_amount'],2);
                $cash=self::scaled((string)$cycle['cash_amount'],2);
                $upi=self::scaled((string)$cycle['upi_amount'],2);
                $lines=self::scaled((string)($cycle['closing_sale_amount']??'0'),2);
                $r['posted_sale_amount']=self::fixed($sale,2);
                $r['posted_cash_split']=self::fixed($cash,2);
                $r['posted_upi_split']=self::fixed($upi,2);
                self::add($tot['posted_daily_order_sales'],$sale);
                self::add($tot['cash_split'],$cash);self::add($tot['upi_split'],$upi);
                self::add($tot['posted_daily_orders'],1);
                if($sale!==$cash+$upi||$sale!==$lines)
                    $r['exceptions'][]='posted_amount_split_mismatch';
                if($issue!==$sold+$returned)
                    $r['exceptions'][]='issued_sold_returned_mismatch';
            }
            unset($r);
        }
        foreach($custody as $line) {
            if(!is_array($line)||(int)($line['branch_id']??0)!==$branch)
                throw new DomainException('Custody movement branch leak.','branch_report_source_invalid',500);
            $employee=(int)($line['employee_id']??0);
            $in=self::scaled((string)($line['qty_in']??'0'),3);
            $out=self::scaled((string)($line['qty_out']??'0'),3);
            // Branch warehouse movements do not belong to employee custody.
            if($employee===0)continue;
            if($employee<0)throw new DomainException('Invalid custody employee.','branch_report_source_invalid',500);
            $rows[$employee]??=$empty($employee,(string)($line['employee_name']??''));
            $rows[$employee]['custody_in_quantity']=self::fixed($in,3);
            $rows[$employee]['custody_out_quantity']=self::fixed($out,3);
            self::add($tot['custody_in_pcs'],$in);self::add($tot['custody_out_pcs'],$out);
        }
        foreach($performance as $line){
            if(!is_array($line)||(int)($line['branch_id']??0)!==$branch
                ||(int)($line['employee_id']??0)<1)
                throw new DomainException('Performance branch/employee leak.','branch_report_source_invalid',500);
            $employee=(int)$line['employee_id'];
            $points=self::scaled((string)($line['points']??'0'),2);
            $rows[$employee]??=$empty($employee,(string)($line['employee_name']??''));
            $rows[$employee]['performance_points']=self::fixed($points,2);
            self::add($tot['performance_points'],$points);
        }
        foreach($rows as &$row){
            if($row['cycle_id']===null)$row['exceptions'][]='activity_without_daily_cycle';
            if($row['exceptions'])self::add($tot['employees_needing_attention'],1);
        }
        unset($row);
        self::add($tot['employees_with_activity'],count($rows));
        foreach($counter as $sale){
            if(!is_array($sale)||(int)($sale['branch_id']??0)!==$branch||($sale['status']??null)!=='posted')
                throw new DomainException('Counter sale branch/status mismatch.','branch_report_source_invalid',500);
            self::add($tot['counter_sales_gross'],self::scaled((string)($sale['gross_amount']??''),2));
            self::add($tot['counter_sales_paid'],self::scaled((string)($sale['paid_amount']??''),2));
            self::add($tot['counter_sales_outstanding'],self::scaled((string)($sale['outstanding_amount']??''),2));
            self::add($tot['posted_counter_sales'],1);
        }
        ksort($rows,SORT_NUMERIC);
        return [
            'branch_id'=>$branch,'business_date'=>$date,'read_only'=>true,
            'scope'=>'single_authorized_branch_canonical_v7',
            'totals'=>[
                'posted_daily_order_sales'=>self::fixed($tot['posted_daily_order_sales'],2),
                'daily_cash_split'=>self::fixed($tot['cash_split'],2),
                'daily_upi_split'=>self::fixed($tot['upi_split'],2),
                'counter_sales_gross'=>self::fixed($tot['counter_sales_gross'],2),
                'counter_sales_paid'=>self::fixed($tot['counter_sales_paid'],2),
                'counter_sales_outstanding'=>self::fixed($tot['counter_sales_outstanding'],2),
                'issued_quantity'=>self::fixed($tot['issued_pcs'],3),
                'sold_quantity'=>self::fixed($tot['sold_pcs'],3),
                'returned_quantity'=>self::fixed($tot['returned_pcs'],3),
                'custody_in_quantity'=>self::fixed($tot['custody_in_pcs'],3),
                'custody_out_quantity'=>self::fixed($tot['custody_out_pcs'],3),
                'performance_points'=>self::fixed($tot['performance_points'],2),
                'posted_daily_orders'=>$tot['posted_daily_orders'],
                'pending_cycles'=>$tot['pending_cycles'],
                'pending_requests'=>$tot['pending_requests'],
                'posted_counter_sales'=>$tot['posted_counter_sales'],
                'employees_with_activity'=>$tot['employees_with_activity'],
                'employees_needing_attention'=>$tot['employees_needing_attention'],
            ],
            'employees'=>array_values($rows),
            'coverage'=>[
                'sales_sources'=>['posted_v7_daily_orders','posted_v7_counter_sales'],
                'retailer_b2b_optional_sources'=>'not_included_without_migration',
                'cashier_handover_verified'=>false,
                'upi_bank_verified'=>false,
                'physical_stock_count_verified'=>false,
                'stock_movement_scope'=>'employee_custody_movements_not_branch_warehouse_balance',
            ],
            'warning'=>'Cash and UPI are posted Daily Order allocations, not independent cashier deposit/bank proof. Counter Sales are separate and NOT added to employee Daily Order totals.'
        ];
    }
}

final class BranchDailyControlWpReader implements BranchDailyControlReader {
    private function query(string $sql,array $params):array {
        $db=Db::wpdb();$prepared=$db->prepare($sql,...$params);
        if(!is_string($prepared)||$prepared==='')throw new DomainException('Branch daily SQL prepare failed.','branch_report_query_failed',500);
        $rows=$db->get_results($prepared,ARRAY_A);
        if(!is_array($rows))throw new DomainException('Branch daily SQL failed.','branch_report_query_failed',500);
        return $rows;
    }
    public function cycles(int $company,int $branch,string $date):array {
        $cycles=Db::table('daily_cycles');$employees=Db::table('employees');
        $settlements=Db::table('evening_settlements');$requests=Db::table('daily_requests');
        $issues=Db::table('daily_issue_lines');$lines=Db::table('evening_lines');
        $sql='SELECT c.id cycle_id,c.employee_id,c.branch_id,e.full_name employee_name,'
            .'c.status cycle_status,es.status settlement_status,'
            .'es.expected_amount,es.cash_amount,es.upi_amount,'
            .'COALESCE(issue_qty.issued_quantity,0) issued_quantity,'
            .'COALESCE(close_lines.sold_quantity,0) sold_quantity,'
            .'COALESCE(close_lines.returned_quantity,0) returned_quantity,'
            .'COALESCE(close_lines.closing_sale_amount,0) closing_sale_amount,'
            .'COALESCE(req.pending_requests,0) pending_requests '
            .'FROM '.$cycles.' c JOIN '.$employees.' e ON e.id=c.employee_id AND e.company_id=c.company_id '
            .'LEFT JOIN '.$settlements.' es ON es.daily_cycle_id=c.id '
            .'LEFT JOIN (SELECT r.daily_cycle_id,SUM(il.quantity) issued_quantity '
            .'FROM '.$requests.' r JOIN '.$issues.' il ON il.daily_request_id=r.id '
            .'GROUP BY r.daily_cycle_id) issue_qty ON issue_qty.daily_cycle_id=c.id '
            .'LEFT JOIN (SELECT el.evening_settlement_id,'
            .'SUM(el.retail_quantity+el.wholesale_quantity) sold_quantity,'
            .'SUM(el.return_quantity) returned_quantity,'
            .'SUM(el.total_amount) closing_sale_amount '
            .'FROM '.$lines.' el GROUP BY el.evening_settlement_id) close_lines '
            .'ON close_lines.evening_settlement_id=es.id '
            .'LEFT JOIN (SELECT daily_cycle_id,'
            ."SUM(CASE WHEN status IN ('draft','submitted','approved') THEN 1 ELSE 0 END) pending_requests "
            .'FROM '.$requests.' GROUP BY daily_cycle_id) req ON req.daily_cycle_id=c.id '
            .'WHERE c.company_id=%d AND c.branch_id=%d AND c.business_date=%s ORDER BY c.employee_id';
        return $this->query($sql,[$company,$branch,$date]);
    }
    public function custody(int $company,int $branch,string $utcStart,string $utcEnd):array {
        $sql='SELECT sl.branch_id,sl.custodian_employee_id employee_id,'
            .'MAX(e.full_name) employee_name,'
            ."SUM(CASE WHEN sl.direction='IN' THEN sl.quantity ELSE 0 END) qty_in,"
            ."SUM(CASE WHEN sl.direction='OUT' THEN sl.quantity ELSE 0 END) qty_out "
            .'FROM '.Db::table('stock_ledger').' sl '
            .'LEFT JOIN '.Db::table('employees').' e ON e.id=sl.custodian_employee_id AND e.company_id=sl.company_id '
            .'WHERE sl.company_id=%d AND sl.branch_id=%d '
            .'AND sl.occurred_at>=%s AND sl.occurred_at<%s '
            ."AND sl.direction IN ('IN','OUT') "
            .'GROUP BY sl.branch_id,sl.custodian_employee_id';
        return $this->query($sql,[$company,$branch,$utcStart,$utcEnd]);
    }
    public function performance(int $company,int $branch,string $date):array {
        $sql='SELECT pe.branch_id,pe.employee_id,MAX(e.full_name) employee_name,'
            .'SUM(pe.points) points FROM '.Db::table('performance_entries').' pe '
            .'LEFT JOIN '.Db::table('employees').' e ON e.id=pe.employee_id AND e.company_id=pe.company_id '
            .'WHERE pe.company_id=%d AND pe.branch_id=%d AND pe.business_date=%s '
            .'GROUP BY pe.branch_id,pe.employee_id';
        return $this->query($sql,[$company,$branch,$date]);
    }
    public function counterSales(int $company,int $branch,string $utcStart,string $utcEnd):array {
        $sql='SELECT branch_id,status,gross_amount,paid_amount,outstanding_amount '
            .'FROM '.Db::table('counter_sales')
            ." WHERE company_id=%d AND branch_id=%d AND status='posted' "
            .'AND sale_date>=%s AND sale_date<%s ORDER BY id';
        return $this->query($sql,[$company,$branch,$utcStart,$utcEnd]);
    }
}
