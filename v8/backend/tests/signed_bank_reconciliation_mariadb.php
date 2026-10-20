<?php
declare(strict_types=1);

/** Disposable MariaDB tests: authenticated internal bank-feed receipt, NOT a PSP integration. */
require_once __DIR__.'/../src/B2B/RetailerCashSale.php';
require_once __DIR__.'/../src/B2B/TrustedTenderIntake.php';
require_once __DIR__.'/../src/B2B/PdoTrustedTenderIntakeGateway.php';
require_once __DIR__.'/../src/B2B/SignedBankReconciliationLookupUat.php';

use ExcelHerbal\ERP8\B2B\SignedBankReconciliationLookupUat;
use ExcelHerbal\ERP8\B2B\TrustedTenderIntake;
use ExcelHerbal\ERP8\B2B\PdoTrustedTenderIntakeGateway;
use ExcelHerbal\ERP8\B2B\RetailerSaleError;

$dsn=getenv('V8_TEST_DSN');
if(!$dsn){echo "SKIP signed bank reconciliation: V8_TEST_DSN absent\n";exit(0);}
try{
 $db=new PDO($dsn,getenv('V8_TEST_USER')?:'v8',getenv('V8_TEST_PASSWORD')?:'v8',[
 PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
 if($db->query('SELECT DATABASE()')->fetchColumn()!=='v8_test')throw new RuntimeException('Refuse non-v8_test database');
 $dir=__DIR__.'/../schema/';
 foreach(['001_b2b_preview_mysql.sql','004_trusted_tender_intake_UAT.sql'] as $file){
  $s=preg_replace('/^\s*--[^\r\n]*$/m','',file_get_contents($dir.$file));
  foreach(preg_split('/;\s*(?:\r?\n|$)/',$s) as $query)if(trim($query)!=='')$db->exec(trim($query));
 }
 $sql=preg_replace('/^\s*--[^\r\n]*$/m','',file_get_contents(__DIR__.'/../schema/010_signed_bank_reconciliation_UAT.sql'));
 foreach(preg_split('/;\s*(?:\r?\n|$)/',$sql) as $query)if(trim($query)!=='')$db->exec(trim($query));
 $company=987654888;$branch=588;$actor=979;
 foreach(['v8_b2b_tender_intake_evidence_uat','v8_b2b_verified_tenders','v8_b2b_signed_bank_reconciliation_uat','v8_b2b_payment_intents_uat'] as $table){
  $db->prepare('DELETE FROM '.$table.' WHERE company_id=?')->execute([$company]);
 }
 $secret=str_repeat('K',64);
 $trustedKeys=static fn(string $keyId)=>$keyId==='CI-key-v1'?$secret:null;
 $lookup=new SignedBankReconciliationLookupUat($db,$trustedKeys);
 $gateway=new PdoTrustedTenderIntakeGateway($db,
  static fn()=>false,
  static fn($c,$b,$staff)=>$c===$company&&$b===$branch&&$staff===$actor,
  $lookup(...),
  static fn($c,$b)=>$c===$company&&$b===$branch?'CI-MERCHANT-588':''
 );
 $intake=new TrustedTenderIntake($gateway);
 $checks=0;
 $assert=static function(bool $ok,string $msg)use(&$checks){if(!$ok)throw new RuntimeException('FAIL '.$msg);$checks++;echo 'PASS '.$msg."\n";};
 $make=static function(string $tag,array $override=[])use($db,$company,$branch,$secret):array{
  $order='CI-ORD-'.$tag;
  $payment=$db->prepare("INSERT INTO v8_b2b_payment_intents_uat(company_id,branch_id,channel,employee_id,payment_mode,amount_paise,merchant_order_id) VALUES(?,?,'counter',NULL,'upi',250000,?)");
  $payment->execute([$company,$branch,$order]);$id=(int)$db->lastInsertId();
  $record=['company_id'=>(string)$company,'branch_id'=>(string)$branch,
   'lookup_key'=>'CI-LOOKUP-'.$tag,'status'=>'settled','currency'=>'INR',
   'amount_paise'=>'250000','merchant_account'=>'CI-MERCHANT-588',
   'merchant_order_id'=>$order,'transaction_id'=>'CI-TXN-'.$tag,
   'observed_at'=>gmdate('Y-m-d H:i:s'),'key_id'=>'CI-key-v1'];
  $record=array_replace($record,$override);
  $record['signature']=SignedBankReconciliationLookupUat::digest($record,$secret);
  $columns=array_keys($record);$stmt=$db->prepare('INSERT INTO v8_b2b_signed_bank_reconciliation_uat('.implode(',',$columns).') VALUES('.implode(',',array_fill(0,count($columns),'?')).')');
  $stmt->execute(array_values($record));
  return [$id,$record];
 };
 $reject=static function(int $id,string $lookupKey,string $needle='')use($intake,$company,$branch,$actor):bool{
  try{$intake->upiSettled($company,$branch,$actor,$id,$lookupKey);}
  catch(RetailerSaleError $e){return $needle===''||str_contains($e->getMessage(),$needle);}
  return false;
 };
 $assert($lookup('CI-LOOKUP-absent')===null,'bank feed cannot be read outside a locked payment transaction');
 [$id,$r]=$make('ACCEPT-01');
 $good=$intake->upiSettled($company,$branch,$actor,$id,$r['lookup_key']);
 $assert($good['payment_reference']===$r['transaction_id']&&$good['amount_paise']===250000,'signed reconciled UPI creates exact confirmed original tender');
 $retry=$intake->upiSettled($company,$branch,$actor,$id,$r['lookup_key']);
 $assert($retry===$good,'exact signed UPI retry is idempotent');
 [$id,$r]=$make('BAD-MAC-02');
 $db->prepare('UPDATE v8_b2b_signed_bank_reconciliation_uat SET signature=? WHERE lookup_key=?')->execute([str_repeat('0',64),$r['lookup_key']]);
 $assert($reject($id,$r['lookup_key'],'settled INR'),'tampered HMAC is rejected before payment evidence');
 [$id,$r]=$make('PRICE-03');
 $db->prepare('UPDATE v8_b2b_signed_bank_reconciliation_uat SET amount_paise=12345 WHERE lookup_key=?')->execute([$r['lookup_key']]);
 $assert($reject($id,$r['lookup_key'],'settled INR'),'tampered amount fails HMAC and cannot confirm payment');
 [$id,$r]=$make('MERCHANT-04');
 $db->prepare('UPDATE v8_b2b_signed_bank_reconciliation_uat SET merchant_account=? WHERE lookup_key=?')->execute(['evil-account',$r['lookup_key']]);
 $assert($reject($id,$r['lookup_key'],'settled INR'),'tampered merchant account fails signed evidence');
 [$id,$r]=$make('STALE-05',['observed_at'=>gmdate('Y-m-d H:i:s',time()-49*3600)]);
 $assert($reject($id,$r['lookup_key'],'settled INR'),'old reconciliation signature cannot be reused after freshness window');
 [$id,$r]=$make('FUTURE-06',['observed_at'=>gmdate('Y-m-d H:i:s',time()+3600)]);
 $assert($reject($id,$r['lookup_key'],'settled INR'),'future-dated bank reconciliation rejected');
 [$id,$r]=$make('UNKNOWN-07',['key_id'=>'missing-key']);
 $assert($reject($id,$r['lookup_key'],'settled INR'),'unknown rotation key cannot verify bank evidence');
 [$id,$r]=$make('ORDER-08',['merchant_order_id'=>'other-merchant-order']);
 $assert($reject($id,$r['lookup_key'],'server-created merchant order'),'valid signature for wrong order still rejected against issued intent');
 [$id,$r]=$make('DEST-09',['merchant_account'=>'OTHER-MERCHANT']);
 $assert($reject($id,$r['lookup_key'],'different or unconfigured merchant'),'valid signature for wrong merchant account still rejected');
 [$id,$r]=$make('CURRENCY-10',['currency'=>'USD']);
 $assert($reject($id,$r['lookup_key'],'settled INR'),'non-INR proof cannot be settled');
 $duplicateBlocked=false;
 try{$make('REPLAY-11',['transaction_id'=>'CI-TXN-ACCEPT-01']);}
 catch(PDOException $e){$duplicateBlocked=$e->getCode()==='23000';}
 $assert($duplicateBlocked,'MariaDB refuses repeated merchant and bank settlement reference');
 [$id,$r]=$make('BRANCH-12',['branch_id'=>(string)($branch+1)]);
 $assert($reject($id,$r['lookup_key'],'company or branch'),'signed record for different branch cannot confirm issued intent');
 $total=(int)$db->query('SELECT COUNT(*) FROM v8_b2b_tender_intake_evidence_uat WHERE company_id='.$company)->fetchColumn();
 $assert($total===1,'only genuine signed payment produced original V8 intake evidence');
 echo "SIGNED BANK RECONCILIATION MARIADB UAT: {$checks}/{$checks} PASS; synthetic signed feed only\n";
}catch(Throwable $e){fwrite(STDERR,'SIGNED BANK RECONCILIATION FAILED: '.$e::class.' '.$e->getMessage()."\n");exit(1);}
