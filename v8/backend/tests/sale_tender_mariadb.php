<?php
declare(strict_types=1);
require_once __DIR__.'/../src/B2B/RetailerCashSale.php';
require_once __DIR__.'/../src/B2B/TrustedTenderIntake.php';
require_once __DIR__.'/../src/B2B/PdoTrustedTenderIntakeGateway.php';
require_once __DIR__.'/../src/B2B/SaleIntentTenderBinding.php';
require_once __DIR__.'/../src/B2B/PdoSaleIntentTenderBindingGateway.php';
use ExcelHerbal\ERP8\B2B\TrustedTenderIntake;
use ExcelHerbal\ERP8\B2B\PdoTrustedTenderIntakeGateway;
use ExcelHerbal\ERP8\B2B\SaleIntentTenderBinding;
use ExcelHerbal\ERP8\B2B\PdoSaleIntentTenderBindingGateway;
use ExcelHerbal\ERP8\B2B\RetailerSaleError;

$dsn=getenv('V8_TEST_DSN');
if(!$dsn){echo "SKIP: no V8_TEST_DSN; disposable MariaDB sale binding NOT verified.\n";exit(0);}
try {
 if(!in_array('mysql',PDO::getAvailableDrivers(),true))throw new RuntimeException('pdo_mysql required');
 $db=new PDO($dsn,getenv('V8_TEST_USER')?:'v8',getenv('V8_TEST_PASSWORD')?:'v8',[
     PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
 if($db->query('SELECT DATABASE()')->fetchColumn()!=='v8_test')throw new RuntimeException('Refusing non-v8_test database.');
 foreach(['001_b2b_preview_mysql.sql','004_trusted_tender_intake_UAT.sql','005_sale_intent_tender_binding_UAT.sql'] as $file){
     $sql=file_get_contents(__DIR__.'/../schema/'.$file);$sql=preg_replace('/^\s*--[^\r\n]*$/m','',$sql);
     foreach(preg_split('/;\s*(?:\r?\n|$)/',$sql) as $stmt){$stmt=trim($stmt);if($stmt!=='')$db->exec($stmt);}
 }
 $company=987654329;$branch=55;$digest=str_repeat('d',64);
 foreach(['v8_b2b_sale_tender_reservations_uat','v8_b2b_payment_intent_to_sale_uat','v8_b2b_tender_intake_evidence_uat','v8_b2b_verified_tenders','v8_b2b_payment_intents_uat','v8_b2b_sale_intents_uat'] as $t){
     $db->prepare('DELETE FROM '.$t.' WHERE company_id=?')->execute([$company]);
 }
 $stmt=$db->prepare('INSERT INTO v8_b2b_sale_intents_uat(company_id,branch_id,retailer_id,canonical_party_id,channel,employee_id,payment_mode,merchant_order_id,invoice_total_paise,quote_digest,pricing_locked) VALUES(?,?,?,?,?,?,?,?,?,?,?)');
 $stmt->execute([$company,$branch,700,900,'field',42,'cash',null,250000,$digest,1]);$sale=(int)$db->lastInsertId();
 $stmt=$db->prepare('INSERT INTO v8_b2b_payment_intents_uat(company_id,branch_id,channel,employee_id,payment_mode,amount_paise,merchant_order_id) VALUES(?,?,?,?,?,?,?)');
 $stmt->execute([$company,$branch,'field',42,'cash',250000,null]);$pay=(int)$db->lastInsertId();
 $stmt=$db->prepare('INSERT INTO v8_b2b_payment_intent_to_sale_uat(payment_intent_id,sale_intent_id,company_id,branch_id,quote_digest) VALUES(?,?,?,?,?)');
 $stmt->execute([$pay,$sale,$company,$branch,$digest]);
 $intake=new TrustedTenderIntake(new PdoTrustedTenderIntakeGateway($db,
     static fn($c,$b,$actor,$channel,$employee)=>$c===987654329&&$b===55&&$actor===333&&$channel==='field'&&$employee===42,
     static fn()=>false,static fn()=>null,static fn()=>''));
 $intake->cashCollected($company,$branch,333,$pay);
 $binder=new SaleIntentTenderBinding(new PdoSaleIntentTenderBindingGateway($db,
     static fn($c,$b,$actor,$sale)=>$c===987654329&&$b===55&&$actor===666&&$sale['canonical_party_id']===900));
 $request=['company_id'=>$company,'branch_id'=>$branch,'actor_id'=>666,'sale_intent_id'=>$sale,'payment_intent_id'=>$pay];
 $out=$binder->reserve($request);$retry=$binder->reserve($request);
 if($out!==$retry||$out['posting_allowed']!==false||$out['status']!=='reserved')throw new RuntimeException('Binding not stable or improperly enabled posting');
 $count=(int)$db->query('SELECT COUNT(*) FROM v8_b2b_sale_tender_reservations_uat WHERE company_id=987654329')->fetchColumn();
 if($count!==1)throw new RuntimeException('Duplicate tender binding recorded');
 $blocked=false;
 try{$binder->reserve($request+['authorized'=>true]);}catch(RetailerSaleError $e){$blocked=true;}
 // Supplied flags have no effect; backend identity and unique intent mapping prevail.
 if($blocked||$count!==1)throw new RuntimeException('Unexpected caller flag behavior');
 $db->prepare('UPDATE v8_b2b_sale_intents_uat SET quote_digest=? WHERE id=?')->execute([str_repeat('e',64),$sale]);
 try{$binder->reserve($request);throw new RuntimeException('Mutated quote unexpectedly accepted');}
 catch(RetailerSaleError $e){if(!str_contains($e->getMessage(),'exact priced sale'))throw $e;}
 $count=(int)$db->query('SELECT COUNT(*) FROM v8_b2b_sale_tender_reservations_uat WHERE company_id=987654329')->fetchColumn();
 if($count!==1)throw new RuntimeException('Quote mismatch altered the original reservation');
 echo "Sale/tender MariaDB UAT: 5/5 PASS (disposable v8_test only; no ERP posting)\n";
}catch(Throwable $e){fwrite(STDERR,"Sale/tender MariaDB UAT FAILED: {$e->getMessage()}\n");exit(1);}
