<?php
/**
 * Employee finance cash-control report sourced only from canonical V7 posted daily cycles and journals.
 * This is an accounting cross-check, NOT evidence of physical cash remittance or bank/UPI settlement.
 */
namespace ExcelHerbal\ERP7\Organization;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;

interface EmployeeCashControlReader {
    /** Returns canonical posted-cycle Cash/UPI and complete GL debit/credit reconciliation. */
    public function posted(int $company,int $employee,string $from,string $to,array $branches,int $limit,int $offset):array;
}

final class EmployeeCashControl {
    public static function view(Actor $actor,int $employeeId,string $from,string $to,int $page=1,int $pageSize=50,?EmployeeCashControlReader $source=null,?Employee360Reader $profileReader=null):array {
        // Even an employee looking at self cannot obtain accounting data without accounting-view capability.
        if (!$actor->can(Capabilities::ACCOUNTING_VIEW))
            throw new DomainException('Finance permission required for employee cash control.','permission_denied',403);
        Employee360Service::validatePeriod($from,$to);
        if($page<1||$page>500||$pageSize<1||$pageSize>100)
            throw new DomainException('Invalid cash-control pagination.','register_pagination_invalid',422);
        $scope=Employee360Service::authorizeTarget($actor,$employeeId,$profileReader);
        $source=$source??new EmployeeCashControlWpReader();
        $items=$source->posted($actor->companyId,$employeeId,$from,$to,$scope['branches'],$pageSize+1,($page-1)*$pageSize);
        if(!is_array($items))throw new DomainException('Cash-control reader returned invalid rows.','cash_control_query_failed',500);
        $more=count($items)>$pageSize;
        $rows=[];$cash=0;$upi=0;$cashPosted=0;$upiPosted=0;$mismatched=0;$unproven=0;
        foreach(array_slice($items,0,$pageSize) as $item){
            if(!is_array($item)||!is_int($item['daily_cycle_id']??null)||$item['daily_cycle_id']<1
                ||!is_int($item['branch_id']??null)||$item['branch_id']<1
                ||!is_string($item['business_date']??null))
                throw new DomainException('Invalid canonical cash-control source row.','cash_control_corrupt',500);
            $day=\DateTimeImmutable::createFromFormat('!Y-m-d',$item['business_date']);
            if(!$day||$day->format('Y-m-d')!==$item['business_date']||$item['business_date']<$from||$item['business_date']>$to)
                throw new DomainException('Cash-control date is outside requested period.','cash_control_corrupt',500);
            if(!$scope['self']&&!in_array($item['branch_id'],$scope['branches'],true))
                throw new DomainException('Cash-control reader exceeded branch scope.','cash_control_scope_invalid',500);
            $expected=self::paise($item['expected_amount']??null);
            $reportedCash=self::paise($item['cash_amount']??null);
            $reportedUpi=self::paise($item['upi_amount']??null);
            $glCash=self::paise($item['gl_cash_debit']??null);
            $glUpi=self::paise($item['gl_upi_debit']??null);
            $glCashCredit=self::paise($item['gl_cash_credit']??null);
            $glUpiCredit=self::paise($item['gl_upi_credit']??null);
            $glSalesCredit=self::paise($item['gl_sales_credit']??null);
            $glTotalDr=self::paise($item['gl_total_debit']??null);
            $glTotalCr=self::paise($item['gl_total_credit']??null);
            $orphanAccounts=$item['gl_orphan_account_lines']??null;
            $journals=$item['journal_count']??null;
            if(!is_int($journals)||$journals<0||$journals>100
                ||!is_int($orphanAccounts)||$orphanAccounts<0||$orphanAccounts>100
                ||$expected!==$reportedCash+$reportedUpi)
                throw new DomainException('Posted settlement totals are inconsistent.','cash_control_corrupt',500);
            $postingOk=$journals===1&&$reportedCash===$glCash&&$reportedUpi===$glUpi
                &&$glCashCredit===0&&$glUpiCredit===0&&$glSalesCredit===$expected
                &&$glTotalDr===$glTotalCr&&$orphanAccounts===0;
            $status=$journals===0?'missing_journal':($journals!==1?'duplicate_journal':($postingOk?'journal_amounts_match':'journal_amount_mismatch'));
            if(!$postingOk)$mismatched++;
            if($reportedCash>0)$unproven++;
            foreach([[$cash,$reportedCash],[$upi,$reportedUpi],[$cashPosted,$glCash],[$upiPosted,$glUpi]] as [$running,$add])
                if($running>PHP_INT_MAX-$add)throw new DomainException('Cash-control amount overflow.','cash_control_corrupt',500);
            $cash+=$reportedCash;$upi+=$reportedUpi;$cashPosted+=$glCash;$upiPosted+=$glUpi;
            $rows[]=[
                'daily_cycle_id'=>$item['daily_cycle_id'],'branch_id'=>$item['branch_id'],
                'business_date'=>$item['business_date'],
                'sale_total_paise'=>$expected,'reported_cash_paise'=>$reportedCash,'reported_upi_paise'=>$reportedUpi,
                'journal_cash_debit_paise'=>$glCash,'journal_upi_debit_paise'=>$glUpi,
                'journal_cash_credit_paise'=>$glCashCredit,'journal_upi_credit_paise'=>$glUpiCredit,
                'journal_sales_credit_paise'=>$glSalesCredit,
                'journal_total_debit_paise'=>$glTotalDr,'journal_total_credit_paise'=>$glTotalCr,
                'journal_orphan_account_lines'=>$orphanAccounts,
                'journal_cash_upi_reconcile'=>$reportedCash===$glCash&&$reportedUpi===$glUpi
                    &&$glCashCredit===0&&$glUpiCredit===0,
                'journal_sales_credit_reconcile'=>$glSalesCredit===$expected,
                'journal_balanced'=>$glTotalDr===$glTotalCr&&$orphanAccounts===0,
                'posted_journal_count'=>$journals,'journal_check'=>$status,
                'cash_remittance_proof'=>$reportedCash>0?'not_evidenced_in_legacy_v7':'not_applicable',
                'upi_bank_settlement_proof'=>$reportedUpi>0?'not_verified_by_this_report':'not_applicable',
                'legacy_direct_branch_cash_posting'=>$reportedCash>0,
            ];
        }
        return [
            'employee_id'=>$employeeId,'period'=>['from'=>$from,'to'=>$to],'page'=>$page,'page_size'=>$pageSize,'has_more'=>$more,
            'rows'=>$rows,'page_totals'=>['cash_reported_paise'=>$cash,'upi_reported_paise'=>$upi,'cash_ledger_debit_paise'=>$cashPosted,'upi_ledger_debit_paise'=>$upiPosted],
            'page_flags'=>['journal_mismatch_count'=>$mismatched,'cash_remittance_unproven_count'=>$unproven],
            'cash_remittance_status'=>'not_available_in_legacy_v7','scope'=>'canonical_posted_daily_cycles_only',
            'warning'=>'Cash/UPI, SALES and journal Dr/Cr agreement is internal bookkeeping only. It does NOT prove physical employee cash handover, bank deposit, or independently verified UPI settlement.',
            'read_only'=>true,
        ];
    }

    private static function paise(mixed $raw):int {
        if(!is_string($raw)&&!is_int($raw))throw new DomainException('Invalid canonical money field.','cash_control_corrupt',500);
        $v=(string)$raw;
        if(!preg_match('/^(0|[1-9][0-9]{0,11})(?:\.([0-9]{1,2}))?$/D',$v,$m))
            throw new DomainException('Invalid canonical monetary precision.','cash_control_corrupt',500);
        $major=(int)$m[1];
        if($major>intdiv(PHP_INT_MAX,100))throw new DomainException('Cash-control money overflow.','cash_control_corrupt',500);
        return $major*100+(int)str_pad($m[2]??'0',2,'0',STR_PAD_RIGHT);
    }
}

final class EmployeeCashControlWpReader implements EmployeeCashControlReader {
    public function posted(int $company,int $employee,string $from,string $to,array $branches,int $limit,int $offset):array {
        $db=Db::wpdb();
        $scope=$branches?' AND c.branch_id IN ('.implode(',',array_fill(0,count($branches),'%d')).')':'';
        // Aggregate journals in a subquery before joining settlements: avoids multiplication by sale lines.
        // Legacy journal source = daily_cycle. No employee remittance table exists in canonical V7.
        // Bind the journal branch to the cycle branch. A same-company, wrong-branch
        // posted journal must not be misattributed as an employee Cash/UPI receipt.
        $j='(SELECT je.company_id,je.branch_id,je.source_id,COUNT(DISTINCT je.id) journal_count,'
          ."COALESCE(SUM(CASE WHEN a.type='asset' AND LOWER(a.subtype)='cash' THEN jl.debit ELSE 0 END),0) gl_cash_debit,"
          ."COALESCE(SUM(CASE WHEN a.type='asset' AND LOWER(a.subtype)='upi' THEN jl.debit ELSE 0 END),0) gl_upi_debit,"
          ."COALESCE(SUM(CASE WHEN a.type='asset' AND LOWER(a.subtype)='cash' THEN jl.credit ELSE 0 END),0) gl_cash_credit,"
          ."COALESCE(SUM(CASE WHEN a.type='asset' AND LOWER(a.subtype)='upi' THEN jl.credit ELSE 0 END),0) gl_upi_credit,"
          ."COALESCE(SUM(CASE WHEN a.code='SALES' AND a.type='income' THEN jl.credit ELSE 0 END),0) gl_sales_credit,"
          .'COALESCE(SUM(jl.debit),0) gl_total_debit,COALESCE(SUM(jl.credit),0) gl_total_credit,'
          .'COALESCE(SUM(CASE WHEN a.id IS NULL THEN 1 ELSE 0 END),0) gl_orphan_account_lines '
          .'FROM '.Db::table('journal_entries').' je JOIN '.Db::table('journal_lines').' jl ON jl.journal_entry_id=je.id '
          .'LEFT JOIN '.Db::table('accounts').' a ON a.id=jl.account_id AND a.company_id=je.company_id '
          ."WHERE je.company_id=%d AND je.source_type='daily_cycle' AND je.status='posted' GROUP BY je.company_id,je.branch_id,je.source_id)";
        $sql='SELECT c.id daily_cycle_id,c.branch_id,c.business_date,es.expected_amount,es.cash_amount,es.upi_amount,'
            .'COALESCE(j.journal_count,0) journal_count,COALESCE(j.gl_cash_debit,0) gl_cash_debit,'
            .'COALESCE(j.gl_upi_debit,0) gl_upi_debit,'
            .'COALESCE(j.gl_cash_credit,0) gl_cash_credit,COALESCE(j.gl_upi_credit,0) gl_upi_credit,'
            .'COALESCE(j.gl_sales_credit,0) gl_sales_credit,'
            .'COALESCE(j.gl_total_debit,0) gl_total_debit,COALESCE(j.gl_total_credit,0) gl_total_credit,'
            .'COALESCE(j.gl_orphan_account_lines,0) gl_orphan_account_lines '
            .'FROM '.Db::table('daily_cycles').' c '
            .'JOIN '.Db::table('evening_settlements')." es ON es.daily_cycle_id=c.id AND es.status='posted' "
            .'LEFT JOIN '.$j." j ON j.company_id=c.company_id AND j.branch_id=c.branch_id AND j.source_id=c.id "
            ."WHERE c.company_id=%d AND c.employee_id=%d AND c.status='completed' "
            .'AND c.business_date BETWEEN %s AND %s'.$scope
            .' ORDER BY c.business_date DESC,c.id DESC LIMIT %d OFFSET %d';
        $args=array_merge([$company,$company,$employee,$from,$to],$branches,[$limit,$offset]);
        $prepared=$db->prepare($sql,...$args);
        if(!is_string($prepared)||$prepared==='')throw new DomainException('Cash-control query preparation failed.','cash_control_query_failed',500);
        $raw=$db->get_results($prepared,ARRAY_A);
        if(!is_array($raw))throw new DomainException('Cash-control query failed.','cash_control_query_failed',500);
        // wpdb exposes MySQL integer columns as decimal strings: normalize only known integer columns.
        foreach($raw as &$row){
            foreach(['daily_cycle_id','branch_id','journal_count','gl_orphan_account_lines'] as $key){
                $v=$row[$key]??null;
                if(!is_scalar($v)||!preg_match('/^(0|[1-9][0-9]*)$/D',(string)$v))
                    throw new DomainException('Cash-control source integer invalid.','cash_control_corrupt',500);
                $row[$key]=(int)$v;
            }
        }
        unset($row);
        return $raw;
    }
}
