<?php
declare(strict_types=1);
require_once __DIR__.'/../src/B2B/RetailerCashSale.php';
require_once __DIR__.'/../src/B2B/TrustedTenderIntake.php';
require_once __DIR__.'/../src/B2B/PdoTrustedTenderIntakeGateway.php';

use ExcelHerbal\ERP8\B2B\TrustedTenderIntake;
use ExcelHerbal\ERP8\B2B\PdoTrustedTenderIntakeGateway;
use ExcelHerbal\ERP8\B2B\RetailerSaleError;

$dsn=getenv('V8_TEST_DSN');
if(!$dsn){echo "SKIP: no disposable V8_TEST_DSN; MariaDB intake NOT tested.\n";exit(0);}
if(!in_array('mysql',PDO::getAvailableDrivers(),true)){
    fwrite(STDERR,"ERROR: pdo_mysql required for requested MariaDB verification\n");exit(2);
}
try{
    $pdo=new PDO($dsn,getenv('V8_TEST_USER')?:'v8',getenv('V8_TEST_PASSWORD')?:'v8',[
      PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC,
    ]);
    if($pdo->query('SELECT DATABASE()')->fetchColumn()!=='v8_test'){
        throw new RuntimeException('Refusing to run UAT fixture against a non-v8_test database.');
    }
    foreach(['001_b2b_preview_mysql.sql','004_trusted_tender_intake_UAT.sql'] as $filename){
        $sql=file_get_contents(__DIR__.'/../schema/'.$filename);
        $sql=preg_replace('/^\s*--[^\r\n]*$/m','',$sql);
        foreach(preg_split('/;\s*(?:\r?\n|$)/',$sql) as $statement){
            $statement=trim($statement);if($statement!=='')$pdo->exec($statement);
        }
    }
    // Use a synthetic company ID, not a real ERP company. Delete only synthetic fixtures.
    $company=987654321;$branch=15;
    $pdo->prepare('DELETE FROM v8_b2b_tender_intake_evidence_uat WHERE company_id=?')->execute([$company]);
    $pdo->prepare('DELETE FROM v8_b2b_verified_tenders WHERE company_id=?')->execute([$company]);
    $pdo->prepare('DELETE FROM v8_b2b_payment_intents_uat WHERE company_id=?')->execute([$company]);
    $insert=$pdo->prepare("INSERT INTO v8_b2b_payment_intents_uat(company_id,branch_id,channel,employee_id,payment_mode,amount_paise,merchant_order_id) VALUES(?,?,?,?,?,?,?)");
    $insert->execute([$company,$branch,'field',42,'cash',500000,null]);$fieldId=(int)$pdo->lastInsertId();
    $insert->execute([$company,$branch,'counter',null,'cash',100000,null]);$counterId=(int)$pdo->lastInsertId();
    $insert->execute([$company,$branch,'counter',null,'upi',123400,'order-test-88']);$upiId=(int)$pdo->lastInsertId();
    $insert->execute([$company,$branch,'counter',null,'upi',123400,'order-test-88']);$upiDuplicateId=(int)$pdo->lastInsertId();
    $bank=['lookup-bank-88'=>['status'=>'settled','currency'=>'INR','amount_paise'=>123400,
      'merchant_account'=>'excel-uat-upi','merchant_order_id'=>'order-test-88','transaction_id'=>'bank-UAT-UTR-88000']];
    $gateway=new PdoTrustedTenderIntakeGateway($pdo,
      static fn($c,$b,$actor,$channel,$employee)=>$c===987654321&&$b===15&&
        (($channel==='field'&&$employee===42&&$actor===501)||($channel==='counter'&&$employee===null&&$actor===777)),
      static fn($c,$b,$actor)=>$c===987654321&&$b===15&&$actor===999,
      static fn($key)=>$bank[$key]??null,
      static fn($c,$b)=>$c===987654321&&$b===15?'excel-uat-upi':''
    );
    $intake=new TrustedTenderIntake($gateway);$checks=0;
    $a=$intake->cashCollected($company,$branch,501,$fieldId);
    if($a['amount_paise']!==500000||$a['verified_source']!=='employee_cash_custody')throw new RuntimeException('Field cash evidence incorrect');$checks++;
    $b=$intake->cashCollected($company,$branch,501,$fieldId);
    if($a!==$b)throw new RuntimeException('Cash retry was not stable');$checks++;
    $c=$intake->cashCollected($company,$branch,777,$counterId);
    if($c['verified_source']!=='branch_cashier_cash')throw new RuntimeException('Counter cash evidence incorrect');$checks++;
    $d=$intake->upiSettled($company,$branch,999,$upiId,'lookup-bank-88');
    if($d['payment_reference']!=='bank-UAT-UTR-88000')throw new RuntimeException('UPI bank proof incorrect');$checks++;
    try{$intake->upiSettled($company,$branch,999,$upiDuplicateId,'lookup-bank-88');
        throw new RuntimeException('Expected replay denial');
    }catch(RetailerSaleError $e){
        // The trusted gateway can reject a duplicate transaction before the DB
        // unique constraint fires; both paths must deny replay.
        if(!str_contains($e->getMessage(),'already allocated'))throw $e;
        $checks++;
    }catch(PDOException $e){
        // In a concurrent collision the unique index remains the final guard.
        if($e->getCode()!=='23000')throw $e;
        $checks++;
    }
    $count=(int)$pdo->query('SELECT COUNT(*) FROM v8_b2b_tender_intake_evidence_uat WHERE company_id=987654321')->fetchColumn();
    $tenders=(int)$pdo->query('SELECT COUNT(*) FROM v8_b2b_verified_tenders WHERE company_id=987654321')->fetchColumn();
    if($count!==3||$tenders!==3)throw new RuntimeException('Replay or rollback created phantom evidence');$checks++;
    echo "Trusted tender MariaDB UAT: {$checks}/{$checks} PASS (disposable v8_test only)\n";
} catch(Throwable $e){fwrite(STDERR,'Tender MariaDB UAT FAILED: '.$e->getMessage()."\n");exit(1);}
