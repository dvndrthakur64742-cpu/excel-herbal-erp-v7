<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP7\Reporting;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities,Guard};

/**
 * DEVELOPMENT-ONLY WordPress REST admission smoke probe.
 *
 * No V8 financial writer or PDO adapter is loaded. Even an enabled route
 * exposes only aggregate schema/transactional-engine compatibility, never
 * sales, ledgers, customer identities, prices, tender proofs, or credentials.
 */
final class B2BStagingRestProbe
{
    private const V7_SOURCES = [
        'b2b_retailer_sales','b2b_retailer_sale_lines',
        'stock_ledger','b2b_verified_tenders','journal_entries',
        'journal_lines','accounts','b2b_cash_remittances',
        'b2b_cashier_receipts_uat',
    ];
    private const V8_SOURCES = [
        'v8_b2b_sale_intents_uat','v8_b2b_verified_tenders',
        'v8_b2b_sale_tender_reservations_uat',
        'v8_b2b_payment_intents_uat','v8_b2b_tender_intake_evidence_uat',
    ];

    /**
     * Runtime registration check and independent per-request check.
     * In particular, a constant or wp_get_environment_type alone is never
     * enough: the connected *actual* database MUST be v8_test.
     */
    public static function exposable():bool
    {
        if(!function_exists('wp_get_environment_type')
            ||wp_get_environment_type()!=='development'
            ||!defined('EH8_ENABLE_B2B_STAGING_REST_PROBE')
            ||EH8_ENABLE_B2B_STAGING_REST_PROBE!==true)
            return false;
        $db=Db::wpdb();
        $prefix=$db->prefix??null;
        if(!is_string($prefix)
            ||!preg_match('/^[A-Za-z0-9_]{1,60}$/D',$prefix)
            ||!method_exists($db,'get_var'))
            return false;
        return $db->get_var('SELECT DATABASE()')==='v8_test'
            &&empty($db->last_error);
    }

    public static function view(Actor $actor,int $branch):array
    {
        // Must reject before touching company data, even when a stale route
        // callback exists after runtime config/database environment changes.
        if(!self::exposable())
            throw new DomainException(
                'Disposable B2B staging diagnostic is unavailable.',
                'b2b_staging_probe_disabled',404);
        Guard::branch($actor,$branch,Capabilities::ACCOUNTING_VIEW);
        if($actor->companyId<1)
            throw new DomainException('Company scope missing.','b2b_staging_scope_invalid',403);
        $db=Db::wpdb();
        $prefix=$db->prefix;
        $names=array_merge(
            array_map(static fn(string $v):string=>$prefix.'eh7_'.$v,self::V7_SOURCES),
            self::V8_SOURCES
        );
        if(count(array_unique($names))!==14)
            throw new DomainException('Staging dependency manifest invalid.',
                'b2b_staging_manifest_invalid',500);
        $placeholders=implode(',',array_fill(0,count($names),'%s'));
        $sql="SELECT TABLE_NAME,ENGINE FROM information_schema.TABLES
              WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME IN ({$placeholders})";
        $prepared=$db->prepare($sql,...$names);
        if(!is_string($prepared)||$prepared==='')
            throw new DomainException('Staging metadata query invalid.',
                'b2b_staging_metadata_failed',500);
        $rows=$db->get_results($prepared,ARRAY_A);
        if(!is_array($rows)||!empty($db->last_error))
            throw new DomainException('Staging metadata unavailable.',
                'b2b_staging_metadata_failed',500);
        $found=[];$allTransactional=true;
        foreach($rows as $r){
            if(!is_array($r)||!is_string($r['TABLE_NAME']??null)
                ||!in_array($r['TABLE_NAME'],$names,true)
                ||isset($found[$r['TABLE_NAME']]))
                throw new DomainException('Staging source metadata inconsistent.',
                    'b2b_staging_metadata_invalid',500);
            $found[$r['TABLE_NAME']]=true;
            if(strtoupper((string)($r['ENGINE']??''))!=='INNODB')
                $allTransactional=false;
        }
        $missing=array_values(array_diff($names,array_keys($found)));
        // This is a *structural* smoke check, not an authorization to write,
        // approve a tax policy, or claim Cash/UPI settlement in production.
        return [
            'read_only'=>true,
            'environment'=>'development_disposable_v8_test_only',
            'scope'=>'authenticated_accounting_actor_authorized_branch',
            'company_id'=>$actor->companyId,'branch_id'=>$branch,
            'dependency_table_count'=>count($names),
            'existing_source_table_count'=>count($found),
            'missing_source_table_count'=>count($missing),
            'all_sources_innodb'=>count($missing)===0&&$allTransactional,
            'structural_preflight_possible'=>count($missing)===0&&$allTransactional,
            'financial_records_disclosed'=>false,
            'financial_posting_enabled'=>false,
            'bank_payment_provider_integrated'=>false,
            'physical_cash_handover_proven'=>false,
            'snapshot_executed'=>false,
            'production_release_authorized'=>false,
            'reason'=>count($missing)>0?'incomplete_disposable_uat_schema':
                (!$allTransactional?'nontransactional_source_table':
                'structural_source_check_only_not_financial_acceptance'),
        ];
    }
}
