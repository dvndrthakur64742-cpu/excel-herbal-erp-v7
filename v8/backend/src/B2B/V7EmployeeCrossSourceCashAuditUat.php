<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP8\B2B;

use Closure;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Organization\{Employee360Service,EmployeeCashControlWpReader};
use ExcelHerbal\ERP7\Security\{Actor,Capabilities,Guard};

/**
 * UAT / disposable v8_test read-only projection of TWO distinct cash sources.
 * A legacy daily_cycle is not automatically the same sale as a canonical B2B
 * retailer sale, and their amounts must never be silently summed.
 * No production REST route, financial posting or data mutation.
 */
final class V7EmployeeCrossSourceCashAuditUat
{
    private static function paise(mixed $amount):int
    {
        if (!is_string($amount)&&!is_int($amount))
            throw new RetailerSaleError('Cash source contains invalid monetary type.');
        $v=(string)$amount;
        if (!preg_match('/^(0|[1-9][0-9]{0,11})(?:\.([0-9]{1,2}))?$/D',$v,$match))
            throw new RetailerSaleError('Cash source contains invalid monetary amount.');
        return ((int)$match[1])*100+(int)str_pad($match[2]??'',2,'0');
    }

    private static function id(mixed $raw):int
    {
        if(!is_int($raw)&&!is_string($raw))
            throw new RetailerSaleError('Cash source identifier type invalid.');
        if(!preg_match('/^[1-9][0-9]{0,15}$/D',(string)$raw))
            throw new RetailerSaleError('Cash source identifier invalid.');
        return (int)$raw;
    }

    public static function inspect(
        Actor $actor,int $branch,int $employee,string $from,string $to,
        Closure $serverAuthority,int $limit=25,int $offset=0
    ):array
    {
        V7CanonicalPostingSinkUat::assertNonProductionEnvironment(Db::wpdb());
        Guard::branch($actor,$branch,Capabilities::ACCOUNTING_VIEW);
        Employee360Service::validatePeriod($from,$to);
        if($employee<1||$limit<1||$limit>100||$offset<0||$offset>50000)
            throw new RetailerSaleError('Invalid UAT employee cash audit arguments.');
        if($serverAuthority('employee.cash.cross_source.view',$actor->userId,
            $actor->companyId,$branch,$employee)!==true)
            throw new RetailerSaleError('Cross-source employee finance authority denied.');
        $company=$actor->companyId;
        // The legacy reader reconciles only completed posted Daily Orders. It
        // already binds company/employee/branch/date and aggregates journals
        // before settlement join; never convert its GL into cashier evidence.
        $legacy=(new EmployeeCashControlWpReader())->posted(
            $company,$employee,$from,$to,[$branch],$limit+1,$offset);
        if(count($legacy)>$limit+1)
            throw new RetailerSaleError('Legacy cash source query overran its page.');
        $legacyMore=count($legacy)>$limit;
        $daily=[];
        foreach(array_slice($legacy,0,$limit) as $row){
            if(!is_array($row)||self::id($row['branch_id']??null)!==$branch)
                throw new RetailerSaleError('Daily Order Cash source crossed branch.');
            $id=self::id($row['daily_cycle_id']??null);
            $cash=self::paise($row['cash_amount']??null);
            $upi=self::paise($row['upi_amount']??null);
            $sale=self::paise($row['expected_amount']??null);
            $cashDr=self::paise($row['gl_cash_debit']??null);
            $upiDr=self::paise($row['gl_upi_debit']??null);
            $cashCr=self::paise($row['gl_cash_credit']??null);
            $upiCr=self::paise($row['gl_upi_credit']??null);
            $salesCr=self::paise($row['gl_sales_credit']??null);
            $dr=self::paise($row['gl_total_debit']??null);
            $cr=self::paise($row['gl_total_credit']??null);
            $journals=(int)($row['journal_count']??-1);
            $orphan=(int)($row['gl_orphan_account_lines']??-1);
            if($sale!==$cash+$upi||$journals<0||$orphan<0)
                throw new RetailerSaleError('Posted Daily Order settlement source inconsistent.');
            $ok=$journals===1&&$orphan===0
                &&$cashDr===$cash&&$upiDr===$upi
                &&$cashCr===0&&$upiCr===0&&$salesCr===$sale&&$dr===$cr;
            $key='daily_cycle:'.$id;
            if(isset($daily[$key]))throw new RetailerSaleError('Duplicate canonical Daily Order source.');
            $daily[$key]=[
                'source_key'=>$key,'source_type'=>'daily_cycle','source_id'=>$id,
                'business_date'=>(string)$row['business_date'],
                'posted_sale_paise'=>$sale,'field_cash_reported_paise'=>$cash,
                'upi_reported_paise'=>$upi,'journal_consistent'=>$ok,
                'journal_status'=>$journals===0?'missing_journal':($journals!==1?'duplicate_journal':($ok?'matched':'mismatch')),
                'cash_handover_verified'=>false,'upi_bank_verified'=>false,
                'liability_reclassified_into_b2b'=>false,
            ];
        }

        $db=Db::wpdb();
        $sql='SELECT id,company_id,branch_id,employee_id,business_date,invoice_total_paise,'.
             'outstanding_paise,status,channel,payment_mode FROM '.Db::table('b2b_retailer_sales').
             " WHERE company_id=%d AND branch_id=%d AND employee_id=%d".
             " AND business_date BETWEEN %s AND %s AND channel='field' AND payment_mode='cash'".
             " ORDER BY business_date DESC,id DESC LIMIT %d OFFSET %d";
        $prepared=$db->prepare($sql,$company,$branch,$employee,$from,$to,$limit+1,$offset);
        if(!is_string($prepared)||$prepared==='')
            throw new RetailerSaleError('B2B employee cash read query preparation failed.');
        $sales=$db->get_results($prepared,ARRAY_A);
        if(!is_array($sales)||$db->last_error)
            throw new RetailerSaleError('B2B employee cash read query failed.');
        if(count($sales)>$limit+1)
            throw new RetailerSaleError('B2B cash source query overran its page.');
        $b2bMore=count($sales)>$limit;
        $b2b=[];
        foreach(array_slice($sales,0,$limit) as $row){
            if(self::id($row['company_id']??null)!==$company
                ||self::id($row['branch_id']??null)!==$branch
                ||self::id($row['employee_id']??null)!==$employee
                ||($row['channel']??null)!=='field'
                ||($row['payment_mode']??null)!=='cash')
                throw new RetailerSaleError('B2B employee cash read source crossed scope.');
            $id=self::id($row['id']??null);
            $invoice=self::id($row['invoice_total_paise']??null);
            if($invoice>99999999999999 || ($row['status']??null)!=='posted'
                ||(string)($row['outstanding_paise']??'')!=='0'
                ||!preg_match('/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/D',(string)($row['business_date']??'')))
                throw new RetailerSaleError('Invalid posted B2B field Cash record.');
            $key='b2b_retailer_sale:'.$id;
            if(isset($b2b[$key]))throw new RetailerSaleError('Duplicate canonical B2B source.');
            $audit=V7B2BCrossLedgerAuditUat::inspect($actor,$branch,$id);
            $state=(string)($audit['cash_custody_state']??'');
            if(($audit['invoice_total_paise']??null)!==$invoice)
                throw new RetailerSaleError('B2B sale and canonical cross-ledger audit disagree.');
            $b2b[$key]=[
                'source_key'=>$key,'source_type'=>'b2b_retailer_sale','source_id'=>$id,
                'business_date'=>(string)$row['business_date'],
                'posted_sale_paise'=>$invoice,'field_cash_reported_paise'=>$invoice,
                'upi_reported_paise'=>0,
                'journal_consistent'=>($audit['cross_ledger_consistent']??false)===true,
                'cash_custody_state'=>$state,
                'cash_handover_verified'=>($audit['cross_ledger_consistent']??false)===true
                    &&$state==='cashier_handover_reconciled_uat',
                'upi_bank_verified'=>false,
                'mismatch_codes'=>$audit['mismatch_codes']??[],
            ];
        }
        return [
            'company_id'=>$company,'branch_id'=>$branch,'employee_id'=>$employee,
            'period'=>['from'=>$from,'to'=>$to],
            'source_pages'=>[
                'legacy_daily_orders'=>['rows'=>array_values($daily),'has_more'=>$legacyMore],
                'canonical_b2b_field_cash'=>['rows'=>array_values($b2b),'has_more'=>$b2bMore],
            ],
            'source_keys_independent'=>true,
            'same_sale_across_sources_not_proven'=>true,
            'combined_sale_total_paise'=>null,
            'combined_employee_cash_outstanding_paise'=>null,
            'page_totals_not_a_full_period'=>true,
            'read_only'=>true,'snapshot_isolation_guaranteed'=>false,
            'physical_legacy_daily_cash_verified'=>false,
            'external_bank_deposit_verified'=>false,
            'scope'=>'disposable_v8_test_finance_review_only',
            'warning'=>'Legacy Daily Order and canonical B2B are separate sources. Their records may describe overlapping physical sales: no global totals, inferred cashier handover, cross-source netting or automatic employee shortage.'
        ];
    }
}
