<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP8\B2B;

use ExcelHerbal\ERP7\Database\{Db,Transaction};
use ExcelHerbal\ERP7\Finance\AccountingService;
use ExcelHerbal\ERP7\Inventory\StockService;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities,Guard};

/**
 * INERT BY DEFAULT. Same-connection V7 stock + GL sink, for disposable v8_test
 * developer UAT only. No REST wiring, WordPress bootstrap, migration installer,
 * payment source SDK, or tax/reversal approval is provided by this class.
 *
 * The trusted $lockedReader must SELECT ... FOR UPDATE the canonical V7 product,
 * party, commercial, stock and settled tender rows *inside this transaction*.
 * Never pass an HTTP request or UI preview through that port. It MUST return
 * a fresh canonical assessment, a persisted immutable quote, and matching
 * bank/cash evidence. The UAT fixture reader is not a production substitute.
 */
final class V7CanonicalPostingSinkUat
{
    public function __construct(private Actor $actor, private $lockedReader)
    {
        if (!is_callable($lockedReader)) throw new RetailerSaleError('Trusted locked V7 reader required.');
    }

    public static function assertNonProductionEnvironment(object $db): void
    {
        if (!function_exists('wp_get_environment_type') || wp_get_environment_type() !== 'development'
            || !defined('EH8_ALLOW_V7_B2B_UAT_POSTING') || EH8_ALLOW_V7_B2B_UAT_POSTING !== true
            || !defined('EH8_B2B_TAX_POLICY_APPROVED') || EH8_B2B_TAX_POLICY_APPROVED !== true
            || !defined('EH8_B2B_REVERSAL_POLICY_APPROVED') || EH8_B2B_REVERSAL_POLICY_APPROVED !== true
            || !defined('EH8_B2B_TRUSTED_TENDER_APPROVED') || EH8_B2B_TRUSTED_TENDER_APPROVED !== true) {
            throw new RetailerSaleError('Canonical B2B posting blocked until all explicit UAT release gates pass.');
        }
        $prefix=$db->prefix??null;
        if(!is_string($prefix)||!preg_match('/^[A-Za-z0-9_]{1,60}$/D',$prefix))
            throw new RetailerSaleError('Unsafe WordPress table prefix.');
        // Check ACTUAL database, not a user-supplied DSN, env var or WordPress option.
        $database=$db->get_var('SELECT DATABASE()');
        if($database !== 'v8_test') throw new RetailerSaleError('UAT writer refuses every database except v8_test.');
    }


    /** Compare every saved line and recompute the issue-time digest from locked V7 state. */
    private static function assertImmutableSnapshot(array $q,array $a):void
    {
        $lines=$q['saved_lines']??null;$at=$q['saved_business_at']??null;
        if(!is_array($lines)||!is_array($a['lines']??null)||$lines===[]
            ||count($lines)!==count($a['lines'])||count($lines)>200
            ||!is_string($at)
            ||!preg_match('/^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$/D',$at)
            ||($time=\DateTimeImmutable::createFromFormat('!Y-m-d H:i:s',$at))===false
            ||$time->format('Y-m-d H:i:s')!==$at
            ||substr($at,0,10)!==($a['business_date']??null))
            throw new RetailerSaleError('Immutable saved business time or quote lines missing.');
        $sum=0;$seen=[];
        foreach($lines as $i=>$line){
            if(!is_array($line)||!is_array($a['lines'][$i]))
                throw new RetailerSaleError('Malformed persisted locked quote line.');
            $fresh=$a['lines'][$i];
            foreach(['product_id'=>'product_id','batch_id'=>'batch_id',
                'quantity_pcs'=>'qty_pcs','commercial_revision_id'=>'commercial_revision_id',
                'unit_price_paise'=>'unit_price_paise','line_total_paise'=>'line_total_paise'] as $saved=>$key){
                if(!is_int($line[$saved]??null)||!is_int($fresh[$key]??null)
                    ||$line[$saved]!==$fresh[$key])
                    throw new RetailerSaleError('Persisted product, stock, batch or commercial price revision changed.');
            }
            if($line['product_id']<1||$line['batch_id']<0||$line['quantity_pcs']<1
                ||$line['commercial_revision_id']<1||$line['unit_price_paise']<1
                ||$line['unit_price_paise']>intdiv(PHP_INT_MAX,$line['quantity_pcs'])
                ||$line['line_total_paise']!==$line['unit_price_paise']*$line['quantity_pcs'])
                throw new RetailerSaleError('Invalid persisted money or quantity.');
            $identifier=$line['product_id'].':'.$line['batch_id'];
            if(isset($seen[$identifier]))throw new RetailerSaleError('Duplicate immutable batch product.');
            $seen[$identifier]=true;
            if($sum>PHP_INT_MAX-$line['line_total_paise'])throw new RetailerSaleError('Quote total overflow.');
            $sum+=$line['line_total_paise'];
        }
        if($sum!==($q['invoice_total_paise']??null))
            throw new RetailerSaleError('Saved line sum and invoice amount differ.');
        $snapshot=['company_id'=>$q['company_id'],'branch_id'=>$q['branch_id'],
            'retailer_id'=>$q['retailer_id'],'canonical_party_id'=>$q['canonical_party_id'],
            'channel'=>$q['channel'],'employee_id'=>$q['employee_id'],'business_at'=>$at,
            'payment_mode'=>$q['payment_mode'],'gross_paise'=>$q['invoice_total_paise'],
            'lines'=>$lines];
        $digest=hash('sha256',json_encode($snapshot,JSON_THROW_ON_ERROR));
        if(!hash_equals($digest,(string)$q['quote_digest']))
            throw new RetailerSaleError('Immutable quote digest mismatch.');
    }

    public function post(array $serverContext): array
    {
        $db=Db::wpdb();
        self::assertNonProductionEnvironment($db);
        foreach(['company_id','branch_id','actor_id','retailer_id','sale_intent_id'] as $key){
            if(!is_int($serverContext[$key]??null)||$serverContext[$key]<=0)
                throw new RetailerSaleError('Trusted canonical posting context required: '.$key);
        }
        $company=$serverContext['company_id'];$branch=$serverContext['branch_id'];
        if($company!==$this->actor->companyId || $serverContext['actor_id']!==$this->actor->userId)
            throw new RetailerSaleError('Company or authenticated WordPress actor mismatch.');
        Guard::branch($this->actor,$branch,Capabilities::SALES_CREATE);
        $requestKey=$serverContext['idempotency_key']??null;
        if(!is_string($requestKey)||!preg_match('/^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$/D',$requestKey))
            throw new RetailerSaleError('Invalid canonical idempotency key.');
        $saleIntent=$serverContext['sale_intent_id'];
        $fingerprint=hash('sha256',json_encode([
            $company,$branch,$this->actor->userId,$serverContext['retailer_id'],$saleIntent
        ],JSON_THROW_ON_ERROR));
        return Transaction::run(function() use ($db,$company,$branch,$requestKey,$saleIntent,$serverContext,$fingerprint):array {
            self::assertNonProductionEnvironment($db);
            AccountingService::lockCompanyForPeriod($this->actor);
            // Lock a unique idempotency key before inspecting or consuming evidence.
            $keys=Db::table('b2b_checkout_keys');
            Db::mustQuery($db,$db->prepare("INSERT INTO {$keys}(company_id,request_key) VALUES(%d,%s) ON DUPLICATE KEY UPDATE request_key=request_key",$company,$requestKey));
            $key=$db->get_row($db->prepare("SELECT * FROM {$keys} WHERE company_id=%d AND request_key=%s FOR UPDATE",$company,$requestKey),ARRAY_A);
            if(!is_array($key)) throw new RetailerSaleError('Canonical idempotency lock failed.');
            // Only an idempotent retry of the exact SAME verified sale is valid.
            if(($key['sale_id']??null)!==null){
                if((int)($key['sale_intent_id']??0)!==$saleIntent || !hash_equals((string)($key['request_fingerprint']??''),$fingerprint))
                    throw new RetailerSaleError('Canonical idempotency key reused for a different sale.');
                $posted=$db->get_row($db->prepare('SELECT id,journal_entry_id,invoice_total_paise,quote_digest FROM '.Db::table('b2b_retailer_sales').' WHERE id=%d AND company_id=%d AND status=%s FOR UPDATE',(int)$key['sale_id'],$company,'posted'),ARRAY_A);
                if(!is_array($posted)||(int)($posted['journal_entry_id']??0)<1)
                    throw new RetailerSaleError('Missing previously posted canonical receipt.');
                return ['sale_id'=>(int)$posted['id'],'journal_id'=>(int)$posted['journal_entry_id'],
                    'invoice_total_paise'=>(int)$posted['invoice_total_paise'],'status'=>'posted','replayed'=>true];
            }
            $data=($this->lockedReader)($this->actor,$serverContext,$db);
            if(!is_array($data)||!is_array($data['assessment']??null)||!is_array($data['quote']??null)
                ||!is_array($data['tender']??null)) throw new RetailerSaleError('Trusted locked sale, quote and tender missing.');
            $a=$data['assessment'];$q=$data['quote'];$proof=$data['tender'];
            // The callback is trusted UAT-only code. A caller-supplied boolean is NEVER
            // payment evidence. Compare a DB-locked stored tender and immutable quote.
            if(($a['assessment']??null)!=='canonical_read_model_validated'
                ||($a['posting_allowed']??null)!==true
                ||($a['company_id']??null)!==$company||($a['branch_id']??null)!==$branch
                ||($q['sale_intent_id']??null)!==$saleIntent
                ||($q['company_id']??null)!==$company||($q['branch_id']??null)!==$branch
                ||($q['retailer_id']??null)!==$serverContext['retailer_id']
                ||($q['invoice_total_paise']??null)!==($a['total_paise']??null)
                ||($q['currency']??null)!=='INR'||($q['pricing_locked']??null)!==true
                ||($q['status']??null)!=='awaiting_payment'
                ||($q['payment_mode']??null)!==($a['payment_mode']??null)
                ||($q['channel']??null)!==($a['channel']??null)
                ||($q['employee_id']??null)!==($a['employee_id']??null)
                ||!preg_match('/^[a-f0-9]{64}$/D',(string)($q['quote_digest']??'')))
                throw new RetailerSaleError('Immutable quote and fresh locked V7 assessment differ.');
            $expectedSource=($a['payment_mode']??null)==='upi'?'bank_settlement'
                :(($a['channel']??null)==='field'?'employee_cash_custody':'branch_cashier_cash');
            if(($proof['company_id']??null)!==$company || ($proof['branch_id']??null)!==$branch
                ||($proof['sale_intent_id']??null)!==$saleIntent
                ||($proof['quote_digest']??null)!==$q['quote_digest']
                ||($proof['verified_source']??null)!==$expectedSource
                ||($proof['payment_mode']??null)!==$a['payment_mode']
                ||($proof['amount_paise']??null)!==$a['total_paise']
                ||($proof['currency']??null)!=='INR'||($proof['status']??null)!=='confirmed'
                ||($proof['consumed_sale_id']??null)!==null
                ||!is_int($proof['id']??null)||$proof['id']<1)
                throw new RetailerSaleError('Missing independent exact-amount unconsumed Cash/UPI evidence.');
            self::assertImmutableSnapshot($q,$a);
            $plan=CanonicalPostingPlan::fromLockedAssessment($a);
            $businessDate=$plan['business_date'];
            if(!is_string($businessDate)||!preg_match('/^\d{4}-\d\d-\d\d$/D',$businessDate))
                throw new RetailerSaleError('Valid locked business date required.');
            AccountingService::assertPeriodOpen($this->actor,$businessDate);
            $day=Db::table('branch_closings');
            $closed=$db->get_var($db->prepare("SELECT id FROM {$day} WHERE company_id=%d AND branch_id=%d AND business_date=%s AND status='closed' FOR UPDATE",$company,$branch,$businessDate));
            if($closed)throw new RetailerSaleError('Cannot post into a closed branch day.');
            $link=$db->prefix.'eh8_retailer_party_links';
            $parties=Db::table('parties');
            $party=$db->get_row($db->prepare("SELECT p.id FROM {$link} l JOIN {$parties} p ON p.id=l.party_id AND p.company_id=l.company_id AND p.branch_id=l.branch_id WHERE l.company_id=%d AND l.branch_id=%d AND l.id=%d AND l.status='active' AND p.status='active' AND p.type='customer' FOR UPDATE",$company,$branch,$serverContext['retailer_id']),ARRAY_A);
            if(!is_array($party)||($q['canonical_party_id']??null)!==(int)$party['id'])
                throw new RetailerSaleError('Retailer no longer links to the active canonical V7 customer.');
            $ar=Db::table('counter_sales');
            $oldAr=$db->get_results($db->prepare("SELECT id,outstanding_amount FROM {$ar} WHERE company_id=%d AND branch_id=%d AND customer_id=%d AND status='posted' AND outstanding_amount>0 FOR UPDATE",$company,$branch,(int)$party['id']),ARRAY_A);
            if(!is_array($oldAr))throw new RetailerSaleError('Legacy customer receivables could not be locked.');
            foreach($oldAr as $arRow){
                if(Paise::parse((string)($arRow['outstanding_amount']??''))!==0)
                    throw new RetailerSaleError('Customer has unresolved legacy credit; Cash/UPI only.');
            }
            $sales=Db::table('b2b_retailer_sales');
            Db::mustInsert($db,$sales,['company_id'=>$company,'branch_id'=>$branch,
                'retailer_id'=>$serverContext['retailer_id'],'customer_id'=>(int)$party['id'],
                'sale_intent_id'=>$saleIntent,'employee_id'=>$plan['employee_id'],
                'channel'=>$plan['channel'],'payment_mode'=>$plan['payment_mode'],
                'quote_digest'=>$q['quote_digest'],'business_date'=>$businessDate,
                'invoice_total_paise'=>$plan['gross_paise'],'cogs_paise'=>$plan['cogs_paise'],
                'outstanding_paise'=>0,'status'=>'pending','created_by'=>$this->actor->employeeId,
                'created_at'=>Db::now()]);
            $sourceId=(int)$db->insert_id;
            if($sourceId<1)throw new RetailerSaleError('Canonical B2B sale source insert failed.');
            foreach($plan['stock_movements'] as $index=>$line){
                Db::mustInsert($db,Db::table('b2b_retailer_sale_lines'),[
                    'sale_id'=>$sourceId,'line_no'=>$index+1,'product_id'=>$line['product_id'],
                    'batch_id'=>$line['batch_id']>0?$line['batch_id']:null,
                    'quantity_pcs'=>$line['qty_pcs'],'commercial_revision_id'=>$line['commercial_revision_id'],
                    'unit_price_paise'=>$line['unit_price_paise'],
                    'line_total_paise'=>$line['line_total_paise'],'cogs_paise'=>$line['cost_paise']]);
                // Existing V7 StockService maintains canonical eh7_stock_balances + ledger.
                $unitApprox=$line['cost_paise'] / (100*$line['qty_pcs']);
                $effective=StockService::move($this->actor,$branch,$line['product_id'],
                    $line['batch_id']>0?$line['batch_id']:null,$plan['employee_id'],
                    'OUT',(float)$line['qty_pcs'],$unitApprox,'b2b_retailer_sale',$sourceId);
                $actual=(int)round($effective*$line['qty_pcs']*100);
                if($actual!==$line['cost_paise'])
                    throw new RetailerSaleError('Actual canonical moving-average cost changed; entire transaction rolled back.');
            }
            // Same V7 Chart of Accounts and journal lock/period checks, NO second GL.
            $journals=[];
            foreach($plan['journal_lines'] as $i=>$line){
                $jl=['account_id'=>$line['account_id'], 'debit'=>$line['debit_paise']/100,
                    'credit'=>$line['credit_paise']/100];
                if($i===0&&$plan['channel']==='field'&&$plan['payment_mode']==='cash'){
                    $jl['party_type']='employee';$jl['party_id']=$plan['employee_id'];
                    $jl['description']='Employee cash held pending cashier remittance';
                }
                $journals[]=$jl;
            }
            $journalId=AccountingService::post($this->actor,$branch,'b2b_retailer_sale',$sourceId,
                $businessDate.' 23:59:59',$journals,'Verified retailer Cash/UPI sale');
            if($journalId<1)throw new RetailerSaleError('Canonical V7 journal not posted.');
            $proofs=Db::table('b2b_verified_tenders');
            $updated=$db->query($db->prepare("UPDATE {$proofs} SET consumed_sale_id=%d WHERE id=%d AND company_id=%d AND branch_id=%d AND consumed_sale_id IS NULL AND sale_intent_id=%d",$sourceId,$proof['id'],$company,$branch,$saleIntent));
            if($updated!==1)throw new RetailerSaleError('Trusted tender already consumed; rollback canonical sale.');
            $finished=Db::mustUpdate($db,$sales,['status'=>'posted','journal_entry_id'=>$journalId],['id'=>$sourceId,'status'=>'pending']);
            if($finished!==1)throw new RetailerSaleError('Canonical B2B sale finalization failed.');
            $saved=Db::mustUpdate($db,$keys,['sale_id'=>$sourceId,'sale_intent_id'=>$saleIntent,'request_fingerprint'=>$fingerprint],['company_id'=>$company,'request_key'=>$requestKey,'sale_id'=>null]);
            if($saved!==1)throw new RetailerSaleError('Canonical idempotency finalization failed.');
            return ['sale_id'=>$sourceId,'journal_id'=>$journalId,'invoice_total_paise'=>$plan['gross_paise'],
                'employee_cash_to_remit_paise'=>$plan['employee_cash_to_remit_paise'],
                'status'=>'posted','replayed'=>false];
        });
    }
}
