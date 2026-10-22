<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP8\B2B;

use Closure;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Organization\EmployeeCashControlWpReader;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities,Guard};

/**
 * DISPOSABLE v8_test only: independent signed-document SOURCE-LINE association.
 * This is a financial review gate, NOT an automatic same-sale determination.
 * No HTTP route, posting, rewrite, dedupe, stock effect or employee liability.
 */
final class V7CrossSourceReferenceReviewUat
{
    private const SIGNED_FIELDS=[
        'company_id','branch_id','employee_id','legacy_daily_cycle_id',
        'legacy_evening_line_id','b2b_sale_id','b2b_sale_line_id',
        'business_date','original_order_reference','original_receipt_reference',
        'source_document_sha256','evidence_product_id','evidence_quantity_pcs',
        'evidence_line_paise','witness_user_id','reviewer_user_id',
    ];

    /** UAT fixture signer; only a server-owned key makes a verifiable signature. */
    public static function signature(array $row,string $serverKey):string
    {
        if(strlen($serverKey)<32)throw new RetailerSaleError('Trusted evidence signing key unavailable.');
        $payload=[];
        foreach(self::SIGNED_FIELDS as $field){
            if(!array_key_exists($field,$row)
                ||(!is_string($row[$field])&&!is_int($row[$field])))
                throw new RetailerSaleError('Cross-source signed evidence field missing.');
            $payload[]=(string)$row[$field];
        }
        return hash_hmac('sha256',json_encode($payload,JSON_THROW_ON_ERROR),$serverKey);
    }

    private static function id(mixed $raw):int
    {
        if((!is_string($raw)&&!is_int($raw))
           ||!preg_match('/^[1-9][0-9]{0,15}$/D',(string)$raw))
            throw new RetailerSaleError('Cross-source identifier invalid.');
        return (int)$raw;
    }

    private static function paise(mixed $raw):int
    {
        if((!is_string($raw)&&!is_int($raw))
           ||!preg_match('/^(0|[1-9][0-9]{0,11})(?:\.([0-9]{1,2}))?$/D',(string)$raw,$m))
            throw new RetailerSaleError('Cross-source money invalid.');
        return ((int)$m[1])*100+(int)str_pad($m[2]??'',2,'0');
    }

    private static function pcs(mixed $raw):int
    {
        if((!is_string($raw)&&!is_int($raw))
           ||!preg_match('/^(0|[1-9][0-9]{0,11})(?:\.([0-9]{1,3}))?$/D',(string)$raw,$m))
            throw new RetailerSaleError('Cross-source quantity invalid.');
        $scaled=(int)$m[1]*1000+(int)str_pad($m[2]??'',3,'0');
        if($scaled%1000!==0)throw new RetailerSaleError('Whole PCS required for B2B cross-source provenance.');
        return intdiv($scaled,1000);
    }

    public static function inspect(Actor $actor,int $branch,int $employee,int $legacyCycleId,
        int $b2bSaleId,Closure $serverAuthority,Closure $serverKeyResolver):array
    {
        V7CanonicalPostingSinkUat::assertNonProductionEnvironment(Db::wpdb());
        Guard::branch($actor,$branch,Capabilities::ACCOUNTING_VIEW);
        if($employee<1||$legacyCycleId<1||$b2bSaleId<1)
            throw new RetailerSaleError('Positive source IDs and employee required.');
        $company=$actor->companyId;
        if($serverAuthority('employee.cash.reference_review',$actor->userId,
            $company,$branch,$employee)!==true)
            throw new RetailerSaleError('Independent cross-source review authority denied.');
        $key=$serverKeyResolver($company,$branch);
        if(!is_string($key)||strlen($key)<32)
            throw new RetailerSaleError('Independent evidence signing key unavailable.');
        $db=Db::wpdb();
        // The evidence table is synthetic and NOT installed by canonical V7.
        // All original source-line references are independently read back from
        // the existing canonical V7 schema rather than trusting stored amounts.
        $sql='SELECT ev.*,'
            .' c.company_id c_company,c.branch_id c_branch,c.employee_id c_employee,'
            .' c.business_date c_date,c.status c_status,'
            .' es.status es_status,es.cash_amount es_cash,'
            .' el.product_id el_product,el.batch_id el_batch,'
            .' el.retail_quantity el_retail,el.wholesale_quantity el_wholesale,'
            .' el.total_amount el_amount,'
            .' r.daily_cycle_id r_cycle,'
            .' b.company_id b_company,b.branch_id b_branch,b.employee_id b_employee,'
            .' b.business_date b_date,b.status b_status,'
            .' b.channel b_channel,b.payment_mode b_mode,'
            .' b.invoice_total_paise b_invoice,b.outstanding_paise b_outstanding,'
            .' bl.product_id bl_product,bl.batch_id bl_batch,'
            .' bl.quantity_pcs bl_quantity,bl.line_total_paise bl_amount '
            .'FROM v8_b2b_cross_source_reference_evidence_uat ev '
            .'LEFT JOIN '.Db::table('daily_cycles').' c ON c.id=ev.legacy_daily_cycle_id '
            .'LEFT JOIN '.Db::table('evening_settlements').' es ON es.daily_cycle_id=c.id '
            .'LEFT JOIN '.Db::table('evening_lines').' el ON el.id=ev.legacy_evening_line_id'
            .' AND el.evening_settlement_id=es.id '
            .'LEFT JOIN '.Db::table('daily_issue_lines').' il ON il.id=el.issue_line_id '
            .'LEFT JOIN '.Db::table('daily_requests').' r ON r.id=il.daily_request_id '
            .'LEFT JOIN '.Db::table('b2b_retailer_sales').' b ON b.id=ev.b2b_sale_id '
            .'LEFT JOIN '.Db::table('b2b_retailer_sale_lines').' bl ON bl.id=ev.b2b_sale_line_id'
            .' AND bl.sale_id=b.id '
            .'WHERE ev.company_id=%d AND ev.branch_id=%d AND ev.employee_id=%d'
            .' AND ev.legacy_daily_cycle_id=%d AND ev.b2b_sale_id=%d LIMIT 2';
        $prepared=$db->prepare($sql,$company,$branch,$employee,$legacyCycleId,$b2bSaleId);
        if(!is_string($prepared)||$prepared==='')throw new RetailerSaleError('Review evidence query preparation failed.');
        $rows=$db->get_results($prepared,ARRAY_A);
        if(!is_array($rows)||$db->last_error)
            throw new RetailerSaleError('Independent source reference query failed.');
        $base=[
            'read_only'=>true,'company_id'=>$company,'branch_id'=>$branch,
            'employee_id'=>$employee,'legacy_source_key'=>'daily_cycle:'.$legacyCycleId,
            'b2b_source_key'=>'b2b_retailer_sale:'.$b2bSaleId,
            'verified_transaction_links'=>[],
            'may_deduplicate'=>false,'may_net_or_adjust_stock'=>false,
            'combined_sale_total_paise'=>null,'combined_cash_outstanding_paise'=>null,
            'original_source_system_integrated'=>false,
            'release_duplicate_prevention_ready'=>false,
            'scope'=>'disposable_v8_test_signed_document_review_only',
        ];
        if(!$rows)return $base+['evidence_state'=>'missing_original_document_evidence'];
        if(count($rows)!==1)throw new RetailerSaleError('Cross-source evidence ambiguous.');
        $ev=$rows[0];
        $actualSignature=self::signature($ev,$key);
        if(!is_string($ev['proof_signature']??null)
           ||!hash_equals($actualSignature,(string)$ev['proof_signature']))
            throw new RetailerSaleError('Cross-source witness signature invalid.');
        if(($ev['status']??null)!=='reviewed'
            ||self::id($ev['witness_user_id']??null)===$actor->userId
            ||self::id($ev['reviewer_user_id']??null)!==$actor->userId
            ||self::id($ev['witness_user_id']??null)===self::id($ev['reviewer_user_id']??null)
            ||!preg_match('/^[A-Za-z0-9][A-Za-z0-9._:\/-]{7,127}$/D',
                (string)($ev['original_order_reference']??''))
            ||!preg_match('/^[A-Za-z0-9][A-Za-z0-9._:\/-]{7,127}$/D',
                (string)($ev['original_receipt_reference']??''))
            ||!preg_match('/^[a-f0-9]{64}$/D',(string)($ev['source_document_sha256']??'')))
            throw new RetailerSaleError('Independent witness and reviewer provenance invalid.');
        $date=(string)$ev['business_date'];
        if(!preg_match('/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/D',$date)
           ||$date!==(string)$ev['c_date']||$date!==(string)$ev['b_date']
           ||self::id($ev['c_company']??null)!==$company
           ||self::id($ev['b_company']??null)!==$company
           ||self::id($ev['c_branch']??null)!==$branch
           ||self::id($ev['b_branch']??null)!==$branch
           ||self::id($ev['c_employee']??null)!==$employee
           ||self::id($ev['b_employee']??null)!==$employee
           ||self::id($ev['r_cycle']??null)!==$legacyCycleId
           ||($ev['c_status']??null)!=='completed'
           ||($ev['es_status']??null)!=='posted'
           ||($ev['b_status']??null)!=='posted'
           ||($ev['b_channel']??null)!=='field'||($ev['b_mode']??null)!=='cash'
           ||(string)($ev['b_outstanding']??'')!=='0')
            throw new RetailerSaleError('Original posted Daily/B2B source provenance invalid.');
        $product=self::id($ev['evidence_product_id']??null);
        $qty=self::id($ev['evidence_quantity_pcs']??null);
        $value=self::id($ev['evidence_line_paise']??null);
        $bQty=self::id($ev['bl_quantity']??null);
        $legacyQty=self::pcs($ev['el_retail']??null)+self::pcs($ev['el_wholesale']??null);
        $legacyBatch=$ev['el_batch']===null?0:self::id($ev['el_batch']);
        $bBatch=$ev['bl_batch']===null?0:self::id($ev['bl_batch']);
        if($qty!==$bQty||$qty!==$legacyQty
            ||$product!==self::id($ev['el_product']??null)
            ||$product!==self::id($ev['bl_product']??null)
            ||$legacyBatch!==$bBatch
            ||$value!==self::paise($ev['el_amount']??null)
            ||$value!==self::id($ev['bl_amount']??null)
            ||$value>self::paise($ev['es_cash']??null)
            ||$value>self::id($ev['b_invoice']??null))
            throw new RetailerSaleError('Original line and signed Cash evidence differ.');
        // Neither valid signature nor line correspondence prove original
        // merchant/source-system creation of the shared reference. We report
        // independently reviewed evidence, NEVER a confirmed duplicate.
        $original=V7B2BCrossLedgerAuditUat::inspect($actor,$branch,$b2bSaleId);
        if(($original['cross_ledger_consistent']??false)!==true)
            throw new RetailerSaleError('Original B2B stock/tender/GL source cannot reconcile.');
        $legacy=(new EmployeeCashControlWpReader())->posted(
            $company,$employee,$date,$date,[$branch],2,0);
        if(count($legacy)!==1||(int)($legacy[0]['daily_cycle_id']??0)!==$legacyCycleId
            ||(int)($legacy[0]['journal_count']??-1)!==1
            ||(int)($legacy[0]['gl_orphan_account_lines']??-1)!==0
            ||self::paise($legacy[0]['expected_amount']??null)
                !==self::paise($legacy[0]['cash_amount']??null)+self::paise($legacy[0]['upi_amount']??null)
            ||self::paise($legacy[0]['gl_cash_debit']??null)!==self::paise($legacy[0]['cash_amount']??null)
            ||self::paise($legacy[0]['gl_upi_debit']??null)!==self::paise($legacy[0]['upi_amount']??null)
            ||self::paise($legacy[0]['gl_cash_credit']??null)!==0
            ||self::paise($legacy[0]['gl_upi_credit']??null)!==0
            ||self::paise($legacy[0]['gl_sales_credit']??null)
                !==self::paise($legacy[0]['expected_amount']??null)
            ||self::paise($legacy[0]['gl_total_debit']??null)
                !==self::paise($legacy[0]['gl_total_credit']??null))
            throw new RetailerSaleError('Legacy source GL is inconsistent with reviewed proof.');
        return $base+[
            'evidence_state'=>'signed_line_association_reviewed_uat',
            'reference_evidence_id'=>self::id($ev['id']),
            'legacy_evening_line_id'=>self::id($ev['legacy_evening_line_id']),
            'b2b_sale_line_id'=>self::id($ev['b2b_sale_line_id']),
            'original_order_reference'=>(string)$ev['original_order_reference'],
            'original_receipt_reference'=>(string)$ev['original_receipt_reference'],
            'source_document_sha256'=>(string)$ev['source_document_sha256'],
            'witness_user_id'=>self::id($ev['witness_user_id']),
            'reviewer_user_id'=>self::id($ev['reviewer_user_id']),
            'finance_gl_consistent'=>true,
            'independent_source_reference_validated_in_live_system'=>false,
            'warning'=>'Witness signature, distinct reviewer and original line correspondence verified only in synthetic UAT. No trusted original external source integration, confirmed same-sale linkage or deduplication is permitted.'
        ];
    }
}
