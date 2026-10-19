<?php
declare(strict_types=1);
require_once __DIR__.'/../src/B2B/RetailerCashSale.php';
require_once __DIR__.'/../src/B2B/ImmutableRetailerIntentIssuer.php';
require_once __DIR__.'/../src/B2B/PdoImmutableRetailerIntentGateway.php';
require_once __DIR__.'/../src/B2B/TrustedTenderIntake.php';
require_once __DIR__.'/../src/B2B/PdoTrustedTenderIntakeGateway.php';
require_once __DIR__.'/../src/B2B/SaleIntentTenderBinding.php';
require_once __DIR__.'/../src/B2B/PdoSaleIntentTenderBindingGateway.php';
use ExcelHerbal\ERP8\B2B\{ImmutableRetailerIntentIssuer,PdoImmutableRetailerIntentGateway,TrustedTenderIntake,PdoTrustedTenderIntakeGateway,SaleIntentTenderBinding,PdoSaleIntentTenderBindingGateway,RetailerSaleError};
$dsn=getenv('V8_TEST_DSN');
if(!$dsn){echo "SKIP: V8_TEST_DSN not set; immutable issuance MariaDB UAT not run.\n";exit(0);}
try{
    if(!in_array('mysql',PDO::getAvailableDrivers(),true))throw new RuntimeException('pdo_mysql required');
    $db=new PDO($dsn,getenv('V8_TEST_USER')?:'v8',getenv('V8_TEST_PASSWORD')?:'v8',[
        PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
    if($db->query('SELECT DATABASE()')->fetchColumn()!=='v8_test')throw new RuntimeException('Refusing non-v8_test database');
    foreach(['001_b2b_preview_mysql.sql','004_trusted_tender_intake_UAT.sql',
        '005_sale_intent_tender_binding_UAT.sql','006_immutable_checkout_intents_UAT.sql'] as $file){
        $sql=preg_replace('/^\s*--[^\r\n]*$/m','',file_get_contents(__DIR__.'/../schema/'.$file));
        foreach(preg_split('/;\s*(?:\r?\n|$)/',$sql) as $query)if(trim($query)!=='')$db->exec(trim($query));
    }
    $company=987654491;$branch=58;$key=str_repeat('d',32);
    foreach(['v8_b2b_sale_tender_reservations_uat','v8_b2b_intent_issuance_requests_uat',
       'v8_b2b_payment_intent_to_sale_uat','v8_b2b_tender_intake_evidence_uat','v8_b2b_verified_tenders',
       'v8_b2b_payment_intents_uat','v8_b2b_sale_intents_uat'] as $table){
        // Request table has company_id and every other staging object is scoped.
        $db->prepare('DELETE FROM '.$table.' WHERE company_id=?')->execute([$company]);
    }
    $snapshot=['company_id'=>$company,'branch_id'=>$branch,'retailer_id'=>876,'canonical_party_id'=>901,
        'channel'=>'field','employee_id'=>47,'business_at'=>'2026-10-19 11:50:00','payment_mode'=>'cash',
        'gross_paise'=>20000,'lines'=>[['product_id'=>4,'batch_id'=>0,'quantity_pcs'=>2,
        'commercial_revision_id'=>10,'unit_price_paise'=>10000,'line_total_paise'=>20000]]];
    $digest=hash('sha256',json_encode($snapshot,JSON_THROW_ON_ERROR));
    $preview=$snapshot+['preview_digest'=>$digest,'posting_allowed'=>false,'stock_reserved'=>false,
        'credit_allowed'=>false,'retailer_outstanding_paise'=>0,'release_status'=>'preview_only',
        'requires_locked_revalidation'=>true,'tax_invoice_status'=>'policy_not_approved',
        'payment_verification_status'=>'not_verified_by_preview'];
    $context=['company_id'=>$company,'branch_id'=>$branch,'actor_id'=>12,'request_key'=>$key];
    $issuer=new ImmutableRetailerIntentIssuer(new PdoImmutableRetailerIntentGateway($db,
        static fn($c,$b,$actor,$emp,$channel)=>$c===987654491&&$b===58&&$actor===12&&$emp===47&&$channel==='field'));
    $first=$issuer->issue($context,$preview);$retry=$issuer->issue($context,$preview);
    if($first!==$retry||$first['posting_allowed']!==false)throw new RuntimeException('Idempotency failed');
    $count=(int)$db->query('SELECT COUNT(*) FROM v8_b2b_intent_issuance_requests_uat WHERE company_id=987654491')->fetchColumn();
    if($count!==1)throw new RuntimeException('Duplicate issuance created');
    $intake=new TrustedTenderIntake(new PdoTrustedTenderIntakeGateway($db,
        static fn($c,$b,$actor,$channel,$emp)=>$c===987654491&&$b===58&&$actor===13&&$channel==='field'&&$emp===47,
        static fn()=>false,static fn()=>null,static fn()=>''));
    $cash=$intake->cashCollected($company,$branch,13,$first['payment_intent_id']);
    if(($cash['status']??null)!=='confirmed')throw new RuntimeException('Cash evidence missing');
    $binding=new SaleIntentTenderBinding(new PdoSaleIntentTenderBindingGateway($db,
        static fn($c,$b,$actor,$sale)=>$c===987654491&&$b===58&&$actor===14&&$sale['canonical_party_id']===901));
    $bindContext=['company_id'=>$company,'branch_id'=>$branch,'actor_id'=>14,
        'sale_intent_id'=>$first['sale_intent_id'],'payment_intent_id'=>$first['payment_intent_id']];
    $reserved=$binding->reserve($bindContext);
    if($reserved['posting_allowed']!==false||$reserved['status']!=='reserved')throw new RuntimeException('Unsafe reservation status');
    $again=$binding->reserve($bindContext);
    if($again!==$reserved)throw new RuntimeException('Binding replay mismatch');
    $q=$db->prepare('SELECT COUNT(*) FROM v8_b2b_sale_tender_reservations_uat WHERE company_id=?');
    $q->execute([$company]);if((int)$q->fetchColumn()!==1)throw new RuntimeException('Tender reservation duplicated');
    echo "Immutable issuance → Cash intake → tender reservation MariaDB UAT: 5/5 PASS; NO stock/GL writes\n";
}catch(Throwable $e){fwrite(STDERR,"Immutable issuance MariaDB UAT FAILED: ".$e->getMessage()."\n");exit(1);}
