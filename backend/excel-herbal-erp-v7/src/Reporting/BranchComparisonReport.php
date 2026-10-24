<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP7\Reporting;

use ExcelHerbal\ERP7\Core\Input;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities,Guard};

/**
 * Multi-branch managerial comparison over canonical V7 BranchPeriodControlReport,
 * with explicitly authorized scope and optional formula-injection-safe CSV.
 * No new sale, stock, Cash, journal or UPI verification records.
 */
final class BranchComparisonReport {
    private const LIMIT_BRANCHES=12;
    private const MAX_EMPLOYEES_PER_BRANCH=2500;
    private const MAX_CSV_BYTES=2000000;
    private const MONEY_KEYS=[
        'posted_daily_order_sales','daily_cash_allocations','daily_upi_allocations',
        'counter_sales_gross','counter_sales_paid','counter_sales_outstanding',
    ];
    private const QTY_KEYS=[
        'issued_quantity','sold_quantity','returned_quantity',
        'custody_in_quantity','custody_out_quantity',
    ];
    private const COUNT_KEYS=[
        'posted_daily_orders','pending_daily_orders','pending_stock_requests',
        'sale_amount_mismatches','stock_quantity_mismatches','posted_counter_sales',
        'employees_with_activity','employees_needing_attention',
    ];

    private static function scaled(mixed $value,int $digits,bool $signed=false):int {
        if(!is_string($value)&&!is_int($value))
            throw new DomainException('Comparison source has invalid DECIMAL type.','branch_compare_source_invalid',500);
        $s=(string)$value;
        $rule=$signed?'/^-?(0|[1-9][0-9]{0,11})(?:\.([0-9]{1,3}))?$/D':'/^(0|[1-9][0-9]{0,11})(?:\.([0-9]{1,3}))?$/D';
        if(!preg_match($rule,$s,$m)||strlen($m[2]??'')>$digits)
            throw new DomainException('Comparison source precision invalid.','branch_compare_source_invalid',500);
        $unit=10**$digits;$major=(int)$m[1];
        if($major>intdiv(PHP_INT_MAX,$unit))
            throw new DomainException('Comparison amount overflow.','branch_compare_source_invalid',500);
        $n=$major*$unit+(int)str_pad($m[2]??'',$digits,'0');
        return str_starts_with($s,'-')?-$n:$n;
    }
    private static function fmt(int $value,int $digits):string {
        if($value===PHP_INT_MIN)throw new DomainException('Comparison amount underflow.','branch_compare_source_invalid',500);
        $unit=10**$digits;$abs=abs($value);
        return ($value<0?'-':'').intdiv($abs,$unit).'.'
            .str_pad((string)($abs%$unit),$digits,'0',STR_PAD_LEFT);
    }
    private static function add(int $one,int $two):int {
        if(($two>0&&$one>PHP_INT_MAX-$two)||($two<0&&$one<PHP_INT_MIN-$two))
            throw new DomainException('Comparison total overflow.','branch_compare_source_invalid',500);
        return $one+$two;
    }
    private static function branches(Actor $actor,string $selected):array {
        $authorized=$actor->branchIds;
        $authorized=array_values(array_unique(array_filter($authorized,
            static fn($b):bool=>is_int($b)&&$b>0)));
        sort($authorized,SORT_NUMERIC);
        if(!$authorized)
            throw new DomainException('No authorized branch available.','branch_forbidden',403);
        if($selected==='')$branches=$authorized;
        else {
            if(!preg_match('/^[1-9][0-9]*(?:,[1-9][0-9]*){0,11}$/D',$selected))
                throw new DomainException('Invalid branch ID selection.','branch_compare_branches_invalid',422);
            $branches=array_map('intval',explode(',',$selected));
            if(count($branches)!==count(array_unique($branches)))
                throw new DomainException('Duplicate branch IDs forbidden.','branch_compare_branches_invalid',422);
            sort($branches,SORT_NUMERIC);
        }
        if(count($branches)>self::LIMIT_BRANCHES)
            throw new DomainException('Branch comparison exceeds 12-branch report limit.','branch_compare_too_many_branches',422);
        foreach($branches as $branch)Guard::branch($actor,$branch,Capabilities::REPORTS_VIEW);
        return $branches;
    }
    private static function totals(array $row):array {
        $out=[];
        foreach(self::MONEY_KEYS as $key)$out[$key]=self::fmt(self::scaled($row[$key]??null,2),2);
        foreach(self::QTY_KEYS as $key)$out[$key]=self::fmt(self::scaled($row[$key]??null,3),3);
        $out['performance_points']=self::fmt(self::scaled($row['performance_points']??null,2,true),2);
        foreach(self::COUNT_KEYS as $key){
            $n=$row[$key]??null;
            if(!is_int($n)||$n<0)
                throw new DomainException('Invalid comparison count source.','branch_compare_source_invalid',500);
            $out[$key]=$n;
        }
        return $out;
    }
    private static function aggregateTotals(array $items):array {
        $sums=[];
        foreach($items as $r){
            foreach(self::MONEY_KEYS as $k)$sums[$k]=self::add($sums[$k]??0,self::scaled($r[$k],2));
            foreach(self::QTY_KEYS as $k)$sums[$k]=self::add($sums[$k]??0,self::scaled($r[$k],3));
            $sums['performance_points']=self::add($sums['performance_points']??0,
                self::scaled($r['performance_points'],2,true));
            foreach(self::COUNT_KEYS as $k)$sums[$k]=self::add($sums[$k]??0,$r[$k]);
        }
        $out=[];
        foreach(self::MONEY_KEYS as $k)$out[$k]=self::fmt($sums[$k]??0,2);
        foreach(self::QTY_KEYS as $k)$out[$k]=self::fmt($sums[$k]??0,3);
        $out['performance_points']=self::fmt($sums['performance_points']??0,2);
        foreach(self::COUNT_KEYS as $k)$out[$k]=$sums[$k]??0;
        return $out;
    }
    private static function employee(array $raw):array {
        $id=$raw['employee_id']??null;
        if(!is_int($id)||$id<1||!is_string($raw['employee_name']??null)
            ||strlen($raw['employee_name'])>250)
            throw new DomainException('Invalid employee comparison row.','branch_compare_source_invalid',500);
        $out=['employee_id'=>$id,'employee_name'=>$raw['employee_name']];
        foreach(['posted_daily_order_sales','daily_cash_allocations','daily_upi_allocations'] as $k)
            $out[$k]=self::fmt(self::scaled($raw[$k]??null,2),2);
        foreach(['issued_quantity','sold_quantity','returned_quantity',
            'custody_in_quantity','custody_out_quantity'] as $k)
            $out[$k]=self::fmt(self::scaled($raw[$k]??null,3),3);
        $out['performance_points']=self::fmt(self::scaled($raw['performance_points']??null,2,true),2);
        foreach(['posted_days','pending_days','pending_requests','sale_amount_mismatches','stock_quantity_mismatches'] as $k){
            if(!is_int($raw[$k]??null)||$raw[$k]<0)
                throw new DomainException('Invalid employee period count.','branch_compare_source_invalid',500);
            $out[$k]=$raw[$k];
        }
        $out['needs_attention']=$out['pending_days']>0||$out['pending_requests']>0
            ||$out['sale_amount_mismatches']>0||$out['stock_quantity_mismatches']>0;
        return $out;
    }

    /** Export CSV as an API JSON envelope so REST authentication/errors remain intact. */
    public static function view(Actor $actor,string $mode,string $date,string $selected='',
        string $export='',?callable $source=null):array {
        Guard::cap($actor,Capabilities::REPORTS_VIEW);
        if(!in_array($mode,['week','month'],true))
            throw new DomainException('Branch comparison mode must be week or month.','branch_period_invalid',422);
        $date=Input::date($date,'Branch comparison date');
        if(!in_array($export,['','csv'],true))
            throw new DomainException('Unknown comparison export format.','branch_compare_export_invalid',422);
        $branches=self::branches($actor,trim($selected));
        $source??=static fn(Actor $a,int $branch,string $m,string $d):array=>
            BranchPeriodControlReport::view($a,$branch,$m,$d);
        $results=[];$employees=[];$dateRange=null;$priorRange=null;
        foreach($branches as $branch){
            $original=$source($actor,$branch,$mode,$date);
            if(!is_array($original)||($original['read_only']??false)!==true
                ||($original['scope']??null)!=='single_authorized_branch_canonical_v7'
                ||($original['branch_id']??null)!==$branch
                ||($original['company_id']??null)!==$actor->companyId
                ||($original['mode']??null)!==$mode
                ||!is_array($original['coverage']??null)
                ||($original['coverage']['cashier_handover_verified']??null)!==false
                ||($original['coverage']['upi_bank_verified']??null)!==false
                ||($original['coverage']['counter_sales_separate_from_daily_orders']??null)!==true
                ||!is_array($original['totals']??null)
                ||!is_array($original['previous_period']['totals']??null)
                ||!is_array($original['period']??null)
                ||!is_array($original['previous_period']['period']??null)
                ||!is_array($original['employees']??null)
                ||count($original['employees'])>self::MAX_EMPLOYEES_PER_BRANCH)
                throw new DomainException('Branch comparison source contract invalid.','branch_compare_source_invalid',500);
            if($dateRange===null){
                $dateRange=$original['period'];$priorRange=$original['previous_period']['period'];
            }
            if($dateRange!==$original['period']||$priorRange!==$original['previous_period']['period'])
                throw new DomainException('Cross-branch period mismatch.','branch_compare_source_invalid',500);
            $now=self::totals($original['totals']);
            $previous=self::totals($original['previous_period']['totals']);
            $branchEmployees=[];$seen=[];
            foreach($original['employees'] as $row){
                if(!is_array($row))throw new DomainException('Invalid employee record.','branch_compare_source_invalid',500);
                $sanitized=self::employee($row);
                $employeeId=$sanitized['employee_id'];
                if(isset($seen[$employeeId]))
                    throw new DomainException('Duplicate branch employee.','branch_compare_source_invalid',500);
                $seen[$employeeId]=true;
                $branchEmployees[]=['branch_id'=>$branch,...$sanitized];
            }
            $results[]=[
                'branch_id'=>$branch,'totals'=>$now,'previous_period_totals'=>$previous,
                'sales_change_inr'=>self::fmt(
                    self::add(self::scaled($now['posted_daily_order_sales'],2),
                        -self::scaled($previous['posted_daily_order_sales'],2)),2),
                'employees'=>$branchEmployees,
            ];
            array_push($employees,...$branchEmployees);
        }
        $combined=self::aggregateTotals(array_column($results,'totals'));
        $combinedPrior=self::aggregateTotals(array_column($results,'previous_period_totals'));
        $leader=null;$topSale=null;
        foreach($results as $row){
            $sale=self::scaled($row['totals']['posted_daily_order_sales'],2);
            if($leader===null||$sale>$topSale){$leader=$row['branch_id'];$topSale=$sale;}
        }
        $report=[
            'read_only'=>true,'scope'=>'only_effective_authorized_branches',
            'mode'=>$mode,'business_date'=>$date,'period'=>$dateRange,
            'previous_period'=>$priorRange,'company_id'=>$actor->companyId,
            'branch_ids'=>$branches,'branches'=>$results,
            'total'=>$combined,'previous_total'=>$combinedPrior,
            'sales_change_inr'=>self::fmt(
                self::add(self::scaled($combined['posted_daily_order_sales'],2),
                    -self::scaled($combinedPrior['posted_daily_order_sales'],2)),2),
            'top_posted_sales_branch_id'=>$leader,'financial_visibility'=>'no_gl_data_exported',
            'comparison_basis'=>'full_calendar_period_not_working_day_normalized',
            'coverage'=>['cashier_handover_verified'=>false,'upi_bank_verified'=>false,
                'physical_stock_verified'=>false,'counter_sales_separate_from_daily_orders'=>true],
            'warning'=>'Posted Daily Order Cash/UPI are allocations only. Counter Sales are separate. No GL, bank, cashier or physical stock proof is included in multi-branch exports.',
        ];
        if($export==='csv')return self::csv($report,$employees);
        return $report;
    }
    /** Single RFC4180 cell; dangerous spreadsheet formulas are inert text. */
    private static function cell(mixed $v):string {
        $s=is_bool($v)?($v?'yes':'no'):(string)($v??'');
        $s=str_replace("\0",'',$s);
        if(preg_match('/^[\x00-\x20\x{FEFF}]*[=+\-@]/u',$s))$s="'".$s;
        return '"'.str_replace('"','""',$s).'"';
    }
    private static function csv(array $report,array $employees):array {
        $head=['record_type','branch_id','employee_id','employee_name',
            'posted_daily_order_sales_inr','previous_period_sales_inr',
            'daily_cash_allocations_inr','daily_upi_allocations_inr',
            'counter_sales_gross_inr','issued_pcs','sold_pcs','returned_pcs',
            'performance_points','pending_daily_orders','pending_stock_requests',
            'employees_needing_attention'];
        $lines=[implode(',',array_map([self::class,'cell'],$head))];
        $put=static function(array $fields)use(&$lines):void{
            $lines[]=implode(',',array_map([self::class,'cell'],$fields));
        };
        $make=static fn(string $kind,int|string $branch,int|string $employee,string $name,
            array $t,string $previous):array=>[
            $kind,$branch,$employee,$name,$t['posted_daily_order_sales'],$previous,
            $t['daily_cash_allocations'],$t['daily_upi_allocations'],
            $t['counter_sales_gross'],$t['issued_quantity'],$t['sold_quantity'],
            $t['returned_quantity'],$t['performance_points'],$t['pending_daily_orders'],
            $t['pending_stock_requests'],$t['employees_needing_attention'],
        ];
        foreach($report['branches'] as $branch){
            $put($make('branch',$branch['branch_id'],'','',
                $branch['totals'],$branch['previous_period_totals']['posted_daily_order_sales']));
            foreach($branch['employees'] as $employee){
                $put(['employee',$branch['branch_id'],$employee['employee_id'],$employee['employee_name'],
                    $employee['posted_daily_order_sales'],'',
                    $employee['daily_cash_allocations'],$employee['daily_upi_allocations'],'',
                    $employee['issued_quantity'],$employee['sold_quantity'],
                    $employee['returned_quantity'],$employee['performance_points'],
                    $employee['pending_days'],$employee['pending_requests'],
                    $employee['needs_attention']?1:0]);
            }
        }
        $put($make('authorized_total','ALL','','',$report['total'],
            $report['previous_total']['posted_daily_order_sales']));
        $csv="\xEF\xBB\xBF".implode("\r\n",$lines)."\r\n";
        if(strlen($csv)>self::MAX_CSV_BYTES)
            throw new DomainException('Safe CSV export exceeds size limit.','branch_compare_export_too_large',422);
        return [
            'read_only'=>true,'scope'=>'only_effective_authorized_branches',
            'mime_type'=>'text/csv','encoding'=>'utf-8-sig',
            'filename'=>'excel-herbal-branch-'.$report['mode'].'-'.$report['business_date'].'.csv',
            'csv'=>$csv,'branch_ids'=>$report['branch_ids'],
            'warning'=>$report['warning'],
        ];
    }
}
