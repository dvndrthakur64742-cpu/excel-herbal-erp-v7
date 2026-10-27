<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP8\B2B;

use ExcelHerbal\ERP7\Core\Input;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities,Guard};

/**
 * Developer-only, READ-ONLY branch/day acceptance preflight.
 *
 * Uses the real V7 retailer sale source and the existing per-sale independent
 * cross-ledger audit. This class does not write any financial row, lock a
 * payment, queue jobs, or serve a WordPress REST endpoint.
 *
 * It is never a GST/tax, external bank, physical cash or production sign-off.
 */
final class V7B2BBranchDayPreflightUat
{
    private const MAX_SALES = 250;
    private const BLOCKERS = [
        'gst_hsn_tax_and_discount_policy_unapproved',
        'refund_and_financial_reversal_policy_unapproved',
        'real_bank_or_independent_cashier_provider_not_connected',
        'live_wordpress_migration_and_role_device_uat_not_approved',
        'owner_production_release_signoff_not_granted',
    ];

    public static function inspect(Actor $actor,int $branch,string $day):array
    {
        V7CanonicalPostingSinkUat::assertNonProductionEnvironment(Db::wpdb());
        Guard::branch($actor,$branch,Capabilities::ACCOUNTING_VIEW);
        if($branch<1)throw new RetailerSaleError('Valid accounting branch required.');
        $day=Input::date($day,'B2B staging business date');
        $db=Db::wpdb();

        // Fetch one row beyond the entire batch limit. Never report green from
        // an incomplete/paginated dataset. A large branch needs another,
        // explicitly reviewed batched snapshot protocol.
        $table=Db::table('b2b_retailer_sales');
        $query=$db->prepare(
            "SELECT id,company_id,branch_id,business_date,status,channel,payment_mode
             FROM {$table} WHERE company_id=%d AND branch_id=%d
             AND business_date=%s ORDER BY id ASC LIMIT 251",
            $actor->companyId,$branch,$day
        );
        if(!is_string($query)||$query==='')throw new RetailerSaleError('Invalid preflight source query.');
        $sales=$db->get_results($query,ARRAY_A);
        if(!is_array($sales)||!empty($db->last_error))
            throw new RetailerSaleError('Canonical branch sale listing failed; preflight refused.');
        if(count($sales)>self::MAX_SALES)
            throw new RetailerSaleError('More than 250 branch sales; cannot certify truncated preflight.');

        $counts=[
            'sales_checked'=>0,
            'counter_cash'=>0,'field_cash'=>0,'upi'=>0,
            'ledger_mismatches'=>0,'cashier_handover_pending'=>0,
            'cashier_handover_reconciled_uat'=>0,
        ];
        $entries=[];$seen=[];$previous=0;
        foreach($sales as $row){
            if(!is_array($row)||!isset($row['id'],$row['company_id'],$row['branch_id'],$row['business_date'])
                ||!ctype_digit((string)$row['id'])
                ||(int)$row['id']<1||(int)$row['id']<=$previous
                ||(int)$row['company_id']!==$actor->companyId
                ||(int)$row['branch_id']!==$branch
                ||(string)$row['business_date']!==$day)
                throw new RetailerSaleError('Cross-company, out-of-order or partial branch preflight source.');
            $id=(int)$row['id'];
            if(isset($seen[$id]))throw new RetailerSaleError('Duplicate source ID in branch preflight.');
            $seen[$id]=true;$previous=$id;

            $audit=V7B2BCrossLedgerAuditUat::inspect($actor,$branch,$id);
            if(($audit['read_only']??false)!==true
                ||($audit['scope']??'')!=='disposable_v8_test_canonical_v7_only'
                ||($audit['company_id']??0)!==$actor->companyId
                ||($audit['branch_id']??0)!==$branch
                ||($audit['sale_id']??0)!==$id
                ||($audit['production_posting_allowed']??true)!==false
                ||!is_bool($audit['cross_ledger_consistent']??null)
                ||!is_array($audit['mismatch_codes']??null))
                throw new RetailerSaleError('Cross-ledger audit evidence contract invalid; preflight refused.');
            $counts['sales_checked']++;
            if(($row['payment_mode']??'')==='upi'){
                $counts['upi']++;
            }elseif(($row['channel']??'')==='field'&&($row['payment_mode']??'')==='cash'){
                $counts['field_cash']++;
            }elseif(($row['channel']??'')==='counter'&&($row['payment_mode']??'')==='cash'){
                $counts['counter_cash']++;
            }

            $headerValid=($row['status']??null)==='posted'
                &&in_array($row['channel']??null,['field','counter'],true)
                &&in_array($row['payment_mode']??null,['cash','upi'],true);
            $ok=$audit['cross_ledger_consistent']===true&&$headerValid;
            $codes=$audit['mismatch_codes'];
            if(!$headerValid&&!in_array('invalid_source_header',$codes,true))
                $codes[]='invalid_source_header';
            $custody=(string)($audit['cash_custody_state']??'');
            if(($row['channel']??'')==='field'&&($row['payment_mode']??'')==='cash'){
                if($custody==='pending_cashier_handover'){
                    $counts['cashier_handover_pending']++;
                }elseif($custody==='cashier_handover_reconciled_uat'){
                    $counts['cashier_handover_reconciled_uat']++;
                }else{
                    // An invalid/tampered source must not disappear from the
                    // operational cash exception list.
                    $counts['cashier_handover_pending']++;
                }
            }elseif($custody!=='not_employee_cash_custody'){
                $ok=false;
                if(!in_array('unexpected_employee_cash_custody',$codes,true))
                    $codes[]='unexpected_employee_cash_custody';
            }
            if(!$ok)$counts['ledger_mismatches']++;

            $entries[]=[
                'sale_id'=>$id,
                'channel'=>$row['channel'],
                'payment_mode'=>$row['payment_mode'],
                'posted_status'=>$row['status'],
                'invoice_total_paise'=>$audit['invoice_total_paise'],
                'ledger_consistent'=>$ok,
                'cash_custody_state'=>$custody,
                'mismatch_codes'=>$codes,
            ];
        }
        $complete=count($sales)>0
            &&$counts['ledger_mismatches']===0
            &&$counts['cashier_handover_pending']===0;
        $state=count($sales)===0?'no_sales_to_assess':
            ($counts['ledger_mismatches']>0?'blocked_ledger_mismatch':
            ($counts['cashier_handover_pending']>0?'blocked_unremitted_field_cash':
            'uat_books_consistent_not_production_certified'));
        return [
            'read_only'=>true,
            'scope'=>'disposable_v8_test_canonical_v7_only',
            'company_id'=>$actor->companyId,'branch_id'=>$branch,'business_date'=>$day,
            'state'=>$state,
            'uat_reconciliation_complete'=>$complete,
            'uat_missing_sales_evidence'=>count($sales)===0,
            'counts'=>$counts,
            'entries'=>$entries,
            'complete_batch'=>true,
            'snapshot_isolation_guaranteed'=>false,
            'physical_cash_verified_in_live_erp'=>false,
            'upi_bank_provider_verified_in_live_erp'=>false,
            'gst_tax_policy_approved'=>false,
            'financial_reversal_policy_approved'=>false,
            'production_release_authorized'=>false,
            'production_release_blockers'=>self::BLOCKERS,
            'reminders_sent'=>0,
        ];
    }
}
