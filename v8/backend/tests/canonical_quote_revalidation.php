<?php
declare(strict_types=1);
require_once __DIR__.'/../src/B2B/RetailerCashSale.php';
require_once __DIR__.'/../src/B2B/CanonicalQuoteSnapshotRevalidation.php';
use ExcelHerbal\ERP8\B2B\{CanonicalQuoteSnapshotRevalidation,RetailerSaleError};

function reconFixtures():array
{
    $line=['product_id'=>4,'batch_id'=>0,'quantity_pcs'=>2,
        'commercial_revision_id'=>12,'unit_price_paise'=>10000,'line_total_paise'=>20000];
    $sale=['sale_intent_id'=>35,'company_id'=>1,'branch_id'=>2,'retailer_id'=>7,
        'canonical_party_id'=>17,'channel'=>'field','employee_id'=>22,'payment_mode'=>'cash',
        'invoice_total_paise'=>20000,'saved_business_at'=>'2026-10-19 11:50:00',
        'saved_lines'=>[$line],'pricing_locked'=>true,'status'=>'awaiting_payment','currency'=>'INR'];
    $snapshot=['company_id'=>1,'branch_id'=>2,'retailer_id'=>7,'canonical_party_id'=>17,
        'channel'=>'field','employee_id'=>22,'business_at'=>$sale['saved_business_at'],
        'payment_mode'=>'cash','gross_paise'=>20000,'lines'=>[$line]];
    $sale['quote_digest']=hash('sha256',json_encode($snapshot,JSON_THROW_ON_ERROR));
    $reservation=['sale_intent_id'=>35,'company_id'=>1,'branch_id'=>2,'retailer_id'=>7,
        'canonical_party_id'=>17,'channel'=>'field','employee_id'=>22,'payment_mode'=>'cash',
        'quote_digest'=>$sale['quote_digest'],'amount_paise'=>20000,
        'payment_intent_id'=>45,'tender_id'=>55,'verified_source'=>'employee_cash_custody',
        'payment_reference'=>'CASH-INT-1-2-45','status'=>'reserved'];
    $identity=['company_id'=>1,'branch_id'=>2,'retailer_id'=>7,'canonical_party_id'=>17,
        'identity_validated'=>true,'credit_allowed'=>false,'outstanding_paise'=>0,'posting_allowed'=>false];
    $fresh=['assessment'=>'canonical_read_model_validated','posting_allowed'=>false,
        'company_id'=>1,'branch_id'=>2,'channel'=>'field','employee_id'=>22,
        'payment_mode'=>'cash','business_date'=>'2026-10-19','total_paise'=>20000,
        'paid_paise'=>20000,'retailer_outstanding_paise'=>0,'lines'=>[
            'not_used'
        ]];
    $fresh['lines']=[['product_id'=>4,'batch_id'=>0,'qty_pcs'=>2,
        'commercial_revision_id'=>12,'unit_price_paise'=>10000,'line_total_paise'=>20000]];
    return [$sale,$reservation,$identity,$fresh];
}
function reconFails(callable $edit,string $fragment=''):void
{
    [$sale,$payment,$identity,$fresh]=reconFixtures();$edit($sale,$payment,$identity,$fresh);
    try{(new CanonicalQuoteSnapshotRevalidation)->compare($sale,$payment,$identity,$fresh);}
    catch(RetailerSaleError $e){if($fragment!==''&&!str_contains($e->getMessage(),$fragment))
        throw new RuntimeException('Expected '.$fragment.' but got '.$e->getMessage());return;}
    throw new RuntimeException('Unsafe quote reconciliation accepted');
}
$cases=[];
$cases['matching persisted lines, confirmed field Cash custody and V7 assessment']=function(){
    [$s,$p,$i,$f]=reconFixtures();$r=(new CanonicalQuoteSnapshotRevalidation)->compare($s,$p,$i,$f);
    assert($r['status']==='snapshot_revalidated_uat_only');
    assert($r['invoice_total_paise']===20000 && $r['posting_allowed']===false && $r['stock_reserved']===false);
};
$cases['UPI bank settlement accepted only with matching quote']=function(){
    [$s,$p,$i,$f]=reconFixtures();$s['payment_mode']='upi';$f['payment_mode']='upi';$p['payment_mode']='upi';$p['verified_source']='bank_settlement';
    $snapshot=['company_id'=>1,'branch_id'=>2,'retailer_id'=>7,'canonical_party_id'=>17,'channel'=>'field','employee_id'=>22,
        'business_at'=>$s['saved_business_at'],'payment_mode'=>'upi','gross_paise'=>20000,'lines'=>$s['saved_lines']];
    $s['quote_digest']=hash('sha256',json_encode($snapshot,JSON_THROW_ON_ERROR));$p['quote_digest']=$s['quote_digest'];
    assert((new CanonicalQuoteSnapshotRevalidation)->compare($s,$p,$i,$f)['verified_source']==='bank_settlement');
};
$cases['other branch retailer link blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$i['branch_id']=3;},'identity');
$cases['other company payment blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$p['company_id']=3;},'another sale');
$cases['wrong canonical party blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$i['canonical_party_id']=99;},'identity');
$cases['inactive or unvalidated retailer blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$i['identity_validated']=false;},'identity');
$cases['old receivables forbid B2B pay-now checkout']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$i['outstanding_paise']=10;},'identity');
$cases['closed or no longer valid current business day blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$f['business_date']='2026-10-20';},'state');
$cases['fresh price revision changed blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$f['lines'][0]['commercial_revision_id']=13;},'commercial_revision_id');
$cases['fresh product price changed blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$f['lines'][0]['unit_price_paise']=12000;},'unit_price_paise');
$cases['fresh price total changed blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$f['total_paise']=22000;},'state');
$cases['fresh quantity changed blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$f['lines'][0]['qty_pcs']=3;},'quantity_pcs');
$cases['fresh batch changed blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$f['lines'][0]['batch_id']=4;},'batch_id');
$cases['field employee cash cannot be attributed to branch cash']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$p['verified_source']='branch_cashier_cash';},'approved');
$cases['unreconciled UPI evidence rejected']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$p['verified_source']='bank_settlement';},'approved');
$cases['paid mode credit rejected']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$s['payment_mode']='credit';},'custody');
$cases['reused tender reservation blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$p['status']='consumed';},'Reserved payment');
$cases['payment reservation amount mismatch blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$p['amount_paise']=19000;},'Reserved payment');
$cases['payment reservation sale ID mismatch blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$p['sale_intent_id']=99;},'Reserved payment');
$cases['missing immutable product row blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$s['saved_lines']=[];},'product lines required');
$cases['tampered persisted price despite header hash blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$s['saved_lines'][0]['unit_price_paise']=9900;},'digest');
$cases['tampered business date against immutable digest blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$s['saved_business_at']='2026-10-19 11:51:00';},'digest');
$cases['missing/altered digest blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$s['quote_digest']=str_repeat('d',64);},'digest');
$cases['client posting approval flags cannot enable read-only reconciler']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$f['posting_allowed']=true;},'state');
$cases['employee custody mismatch blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$f['employee_id']=23;},'state');
$cases['partial retail payment blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$f['paid_paise']=15000;},'state');
$cases['zero tender reference blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$p['payment_reference']='';},'approved');
$cases['business datetime malformed blocked']=fn()=>reconFails(static function(&$s,&$p,&$i,&$f){$s['saved_business_at']='2026-10-44 24:51:11';},'business datetime');
$done=0;foreach($cases as $label=>$test){try{$test();$done++;echo "PASS $label\n";}catch(Throwable $e){fwrite(STDERR,"FAIL $label: ".$e->getMessage()."\n");exit(1);}}
echo "PASS $done/".count($cases)." canonical quote snapshot reconciliation regressions\n";
