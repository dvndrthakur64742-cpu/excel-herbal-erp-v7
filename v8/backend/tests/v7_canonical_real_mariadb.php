<?php
declare(strict_types=1);
/**
 * CI-only, disposable MariaDB integration of actual V7 StockService and
 * AccountingService with V8 locked intent/tender on ONE PDO-backed wpdb.
 * This is NOT a WordPress REST or production migration.
 */
$dsn=getenv('V8_TEST_DSN');
if (!$dsn) {fwrite(STDOUT,"SKIP: no disposable V8_TEST_DSN\n");exit(0);}
if (!in_array('mysql',PDO::getAvailableDrivers(),true)) {fwrite(STDERR,"pdo_mysql is required\n");exit(2);}
$pdo=new PDO($dsn,getenv('V8_TEST_USER')?:'v8',getenv('V8_TEST_PASSWORD')?:'v8',[
    PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
if ($pdo->query('SELECT DATABASE()')->fetchColumn()!=='v8_test')throw new RuntimeException('Refusing anything except v8_test');
if(!defined('ARRAY_A'))define('ARRAY_A','ARRAY_A');
foreach (['EH8_ALLOW_V7_B2B_UAT_POSTING','EH8_B2B_TAX_POLICY_APPROVED','EH8_B2B_REVERSAL_POLICY_APPROVED','EH8_B2B_TRUSTED_TENDER_APPROVED'] as $flag) {
    // Only in this disposable integration test: does NOT signify owner policy approval.
    if(!defined($flag))define($flag,true);
}
function wp_get_environment_type():string{return 'development';}
function current_time(string $format,bool $gmt=false):string{
    $clock=new DateTimeImmutable('2026-10-19 15:30:00',new DateTimeZone('Asia/Kolkata'));
    if($gmt)$clock=$clock->setTimezone(new DateTimeZone('UTC'));
    if($format==='mysql')return $clock->format('Y-m-d H:i:s');
    return $clock->format($format);
}

/** Minimal faithful wpdb API subset backed by ONE PDO connection; no SQL faking. */
final class PdoWpdbUat {
    public string $prefix='wp_';
    public string $last_error='';
    public int $insert_id=0;
    public bool $failJournalInsert=false;
    public function __construct(public PDO $pdo){}
    public function prepare(string $sql,mixed ...$args):string {
        if(count($args)===1 && is_array($args[0]))$args=$args[0];
        $pos=0;
        $replaced=preg_replace_callback('/%(?:d|s|f)/',function($m)use(&$pos,$args){
            if(!array_key_exists($pos,$args))throw new RuntimeException('wpdb placeholder underflow');
            $v=$args[$pos++];
            return match($m[0]){
                '%d'=>(string)(int)$v,
                '%f'=>(string)(float)$v,
                '%s'=>$v===null?'NULL':$this->pdo->quote((string)$v),
            };
        },$sql);
        if($pos!==count($args))throw new RuntimeException('wpdb placeholder overflow');
        return (string)$replaced;
    }
    public function query(string $sql):int|false {
        $this->last_error='';
        if($this->failJournalInsert&&preg_match('/^INSERT INTO wp_eh7_journal_entries\b/i',trim($sql))) {
            $this->last_error='Test-injected journal insert failure';return false;
        }
        try {
            $count=$this->pdo->exec($sql);
            $this->insert_id=(int)$this->pdo->lastInsertId();
            return $count;
        }catch(Throwable $e){$this->last_error=$e->getMessage();return false;}
    }
    public function get_row(string $sql,mixed $format=null):?array {
        $this->last_error='';
        try{$r=$this->pdo->query($sql)->fetch(PDO::FETCH_ASSOC);return $r===false?null:$r;}
        catch(Throwable $e){$this->last_error=$e->getMessage();return null;}
    }
    public function get_results(string $sql,mixed $format=null):array {
        $this->last_error='';
        try{return $this->pdo->query($sql)->fetchAll(PDO::FETCH_ASSOC);}
        catch(Throwable $e){$this->last_error=$e->getMessage();return [];}
    }
    public function get_var(string $sql):mixed {
        $this->last_error='';
        try{return $this->pdo->query($sql)->fetchColumn();}
        catch(Throwable $e){$this->last_error=$e->getMessage();return null;}
    }
    public function insert(string $table,array $row):int|false {
        $cols=array_keys($row);
        $sql='INSERT INTO '.$table.' ('.implode(',',$cols).') VALUES ('.implode(',',array_fill(0,count($cols),'?')).')';
        $this->last_error='';
        if($this->failJournalInsert&&$table==='wp_eh7_journal_entries') {
            $this->last_error='Test-injected journal insert failure';return false;
        }
        try{$stmt=$this->pdo->prepare($sql);$stmt->execute(array_values($row));$this->insert_id=(int)$this->pdo->lastInsertId();return $stmt->rowCount();}
        catch(Throwable $e){$this->last_error=$e->getMessage();return false;}
    }
    public function update(string $table,array $data,array $where):int|false {
        $sets=[];$filters=[];$args=[];
        foreach($data as $name=>$value){$sets[]=$name.'=?';$args[]=$value;}
        foreach($where as $name=>$value){if($value===null){$filters[]=$name.' IS NULL';}else{$filters[]=$name.'=?';$args[]=$value;}}
        $this->last_error='';
        try{$stmt=$this->pdo->prepare('UPDATE '.$table.' SET '.implode(',',$sets).' WHERE '.implode(' AND ',$filters));$stmt->execute($args);return $stmt->rowCount();}
        catch(Throwable $e){$this->last_error=$e->getMessage();return false;}
    }
}
$GLOBALS['wpdb']=$wp=new PdoWpdbUat($pdo);
$base=dirname(__DIR__,3);
$legacy=$base.'/backend/excel-herbal-erp-v7/src/';
spl_autoload_register(static function(string $name)use($legacy):void{
    $prefix='ExcelHerbal\\ERP7\\';
    if(!str_starts_with($name,$prefix))return;
    $p=$legacy.str_replace('\\','/',substr($name,strlen($prefix))).'.php';
    if(is_file($p))require_once $p;
});
$src=dirname(__DIR__).'/src/B2B/';
foreach(['RetailerCashSale.php','TrustedTenderIntake.php','PdoTrustedTenderIntakeGateway.php','SignedBankReconciliationLookupUat.php','CanonicalPostingContract.php','CanonicalV7Readiness.php','V7UatCanonicalTenderBridge.php','V7UatLockedCheckoutReader.php','V7CanonicalPostingSinkUat.php','V7CanonicalCashHandoverUat.php'] as $name)require_once $src.$name;

// Canonical V7 schema definitions, not synthetic stock/accounting structures.
$canonical=\ExcelHerbal\ERP7\Database\Schema::definitions();
$tables=['companies','branches','employees','products','batches','stock_balances','stock_ledger',
  'product_commercial_revisions','accounts','accounting_periods','branch_closings',
  'journal_entries','journal_lines','number_series','parties','counter_sales'];
foreach($tables as $name){
    if(!isset($canonical[$name]))throw new RuntimeException('Missing authoritative V7 table definition: '.$name);
    $pdo->exec('CREATE TABLE IF NOT EXISTS wp_eh7_'.$name.' ('.$canonical[$name].') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
}
// The UAT writer's DRAFT source schema stays in v8_test; never run in WordPress installation.
foreach(['001_b2b_preview_mysql.sql','004_trusted_tender_intake_UAT.sql','005_sale_intent_tender_binding_UAT.sql',
  '006_immutable_checkout_intents_UAT.sql','007_immutable_sale_line_snapshots_UAT.sql','010_signed_bank_reconciliation_UAT.sql',
  '009_v7_canonical_retailer_posting_DRAFT.sql','011_v7_canonical_cash_handover_DRAFT.sql'] as $file){
    $sql=file_get_contents(dirname(__DIR__).'/schema/'.$file);
    $sql=preg_replace('/^\s*--[^\r\n]*$/m','',$sql);
    foreach(preg_split('/;\s*(?:\r?\n|$)/',$sql) as $statement){
        $statement=trim($statement);if($statement!=='')$pdo->exec($statement);
    }
}
$pdo->exec("CREATE TABLE IF NOT EXISTS wp_eh8_retailer_party_links (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,company_id BIGINT UNSIGNED NOT NULL,
 branch_id BIGINT UNSIGNED NOT NULL,party_id BIGINT UNSIGNED NOT NULL,
 status VARCHAR(20) NOT NULL DEFAULT 'active',UNIQUE KEY party_link (company_id,branch_id,party_id)
) ENGINE=InnoDB");
// Dedicated company IDs avoid collisions with the other suites sharing v8_test.
$company=987665531;$branch=4001;$user=8001;$employee=9001;$product=701;$party=551;
$mainDay='2026-10-19 15:00:00';
$pdo->prepare("INSERT INTO wp_eh7_companies(id,name,status,created_at) VALUES(?, 'Canonical UAT', 'active', ?)
 ON DUPLICATE KEY UPDATE name=VALUES(name)")->execute([$company,$mainDay]);
$pdo->prepare("INSERT INTO wp_eh7_branches(id,company_id,code,name,created_at) VALUES(?,?, 'CI-V8','Canonical UAT Branch',?)
 ON DUPLICATE KEY UPDATE name=VALUES(name)")->execute([$branch,$company,$mainDay]);
$pdo->prepare("INSERT INTO wp_eh7_employees(id,company_id,employee_code,designation_code,assigned_branch_id,full_name,created_at)
 VALUES(?,?, 'CI-EMP-9001','BM',?,'CI Employee',?) ON DUPLICATE KEY UPDATE full_name=VALUES(full_name)")->execute([$employee,$company,$branch,$mainDay]);
$pdo->prepare("INSERT INTO wp_eh7_products(id,company_id,sku,name,batch_tracking,status,created_at)
 VALUES(?,?, 'CI-SKU-701','CI Herbal Test','off','active',?) ON DUPLICATE KEY UPDATE name=VALUES(name)")->execute([$product,$company,$mainDay]);
$pdo->prepare("INSERT INTO wp_eh7_product_commercial_revisions(id,company_id,product_id,effective_from,mrp,sale_price,
 ho_amount,bm_profit,salary_fund,office_expense,points,purchase_cost,created_at)
 VALUES(90001,?,?, '2026-10-01 00:00:00','150.00','100.00','50.00','20.00','20.00','10.00','5.00','40.0000',?)
 ON DUPLICATE KEY UPDATE sale_price='100.00'")->execute([$company,$product,$mainDay]);
$pdo->prepare("INSERT INTO wp_eh7_stock_balances(company_id,branch_id,product_id,batch_key,custodian_key,quantity,average_unit_cost,updated_at)
 VALUES(?,?,?,0,0,10.000,40.0000,?) ON DUPLICATE KEY UPDATE quantity=10.000,average_unit_cost=40.0000")->execute([$company,$branch,$product,$mainDay]);
$pdo->prepare("INSERT INTO wp_eh7_parties(id,company_id,branch_id,type,name,status,created_at)
 VALUES(?,?,?,'customer','CI Retailer','active',?) ON DUPLICATE KEY UPDATE status='active'")->execute([$party,$company,$branch,$mainDay]);
$pdo->prepare("INSERT INTO wp_eh8_retailer_party_links(id,company_id,branch_id,party_id,status)
 VALUES(77,?,?,?,'active') ON DUPLICATE KEY UPDATE status='active'")->execute([$company,$branch,$party]);
$coa=['SALES'=>['income',null],'COGS'=>['expense',null],'INVENTORY'=>['asset',null],
 'BRANCH_CASH'=>['asset','cash'],'EMPLOYEE_CASH_IN_TRANSIT'=>['asset','cash'],'UPI_CLEARING'=>['asset','upi']];
foreach($coa as $code=>[$type,$subtype]){$stmt=$pdo->prepare("INSERT INTO wp_eh7_accounts(company_id,code,name,type,subtype,active)
 VALUES(?,?,?,?,?,1) ON DUPLICATE KEY UPDATE active=1");$stmt->execute([$company,$code,'CI '.$code,$type,$subtype]);}

function createIntent(PDO $db,int $company,int $branch,int $product,int $party,string $at,string $ref,
 string $channel='counter',?int $employee=null,string $mode='cash',bool $forgeBankSignature=false):array{
    if(!in_array($channel,['counter','field'],true)||!in_array($mode,['cash','upi'],true)
        ||($channel==='field')!==($employee!==null))throw new RuntimeException('Invalid test source custody');
    $source=$mode==='upi'?'bank_settlement':($channel==='field'?'employee_cash_custody':'branch_cashier_cash');
    $merchantOrder=$mode==='upi'?'CI-ORDER-'.$ref:null;
    $lines=[['product_id'=>$product,'batch_id'=>0,'quantity_pcs'=>2,'commercial_revision_id'=>90001,'unit_price_paise'=>10000,'line_total_paise'=>20000]];
    $base=['company_id'=>$company,'branch_id'=>$branch,'retailer_id'=>77,'canonical_party_id'=>$party,
      'channel'=>$channel,'employee_id'=>$employee,'business_at'=>$at,'payment_mode'=>$mode,'gross_paise'=>20000,'lines'=>$lines];
    $digest=hash('sha256',json_encode($base,JSON_THROW_ON_ERROR));
    $p=$db->prepare("INSERT INTO v8_b2b_sale_intents_uat(company_id,branch_id,retailer_id,canonical_party_id,channel,employee_id,payment_mode,merchant_order_id,currency,invoice_total_paise,quote_digest,pricing_locked) VALUES(?,?,77,?,?,?,?,?,'INR',20000,?,1)");
    $p->execute([$company,$branch,$party,$channel,$employee,$mode,$merchantOrder,$digest]);$saleId=(int)$db->lastInsertId();
    $p=$db->prepare("INSERT INTO v8_b2b_payment_intents_uat(company_id,branch_id,channel,employee_id,payment_mode,amount_paise,merchant_order_id,currency) VALUES(?,?,?,?,?,20000,?,'INR')");
    $p->execute([$company,$branch,$channel,$employee,$mode,$merchantOrder]);$paymentId=(int)$db->lastInsertId();
    $p=$db->prepare('INSERT INTO v8_b2b_issued_sale_context_uat(sale_intent_id,company_id,branch_id,business_at,quote_digest) VALUES(?,?,?,?,?)');
    $p->execute([$saleId,$company,$branch,$at,$digest]);
    $p=$db->prepare('INSERT INTO v8_b2b_sale_intent_lines_uat(sale_intent_id,company_id,branch_id,line_no,product_id,batch_id,quantity_pcs,commercial_revision_id,unit_price_paise,line_total_paise) VALUES(?,?,?,1,?,0,2,90001,10000,20000)');
    $p->execute([$saleId,$company,$branch,$product]);
    $p=$db->prepare('INSERT INTO v8_b2b_payment_intent_to_sale_uat(payment_intent_id,sale_intent_id,company_id,branch_id,quote_digest) VALUES(?,?,?,?,?)');
    $p->execute([$paymentId,$saleId,$company,$branch,$digest]);
    // Confirm original tender through an HMAC-verified internal settlement feed.
    // Signed values and signer secret are synthetic in disposable CI, NOT a live PSP.
    $secret=str_repeat('C',64);
    if($mode==='upi'){
        $proof=['company_id'=>(string)$company,'branch_id'=>(string)$branch,
            'lookup_key'=>'CI-LOOKUP-'.$ref,'status'=>'settled','currency'=>'INR',
            'amount_paise'=>'20000','merchant_account'=>'CI-UAT-MERCHANT',
            'merchant_order_id'=>$merchantOrder,'transaction_id'=>$ref,
            'observed_at'=>gmdate('Y-m-d H:i:s'),'key_id'=>'canonical-ci-key'];
        $proof['signature']=$forgeBankSignature?str_repeat('0',64):
            \ExcelHerbal\ERP8\B2B\SignedBankReconciliationLookupUat::digest($proof,$secret);
        $cols=array_keys($proof);
        $p=$db->prepare('INSERT INTO v8_b2b_signed_bank_reconciliation_uat('.implode(',',$cols).') VALUES('.implode(',',array_fill(0,count($cols),'?')).')');
        $p->execute(array_values($proof));
    }
    $bankVerifier=new \ExcelHerbal\ERP8\B2B\SignedBankReconciliationLookupUat(
        $db,static fn(string $keyId)=>$keyId==='canonical-ci-key'?$secret:null);
    $gateway=new \ExcelHerbal\ERP8\B2B\PdoTrustedTenderIntakeGateway(
        $db,
        static fn($c,$b,$actor,$ch,$emp)=>$c===$company&&$b===$branch&&
            (($ch==='field'&&$actor===8001&&$emp===$employee&&$emp!==null)
              ||($ch==='counter'&&$actor===8002&&$emp===null)),
        static fn($c,$b,$actor)=>$c===$company&&$b===$branch&&$actor===8002,
        $bankVerifier,
        static fn($c,$b)=>$c===$company&&$b===$branch?'CI-UAT-MERCHANT':''
    );
    $intake=new \ExcelHerbal\ERP8\B2B\TrustedTenderIntake($gateway);
    $confirmed=$mode==='upi'
        ?$intake->upiSettled($company,$branch,8002,$paymentId,'CI-LOOKUP-'.$ref)
        :$intake->cashCollected($company,$branch,$channel==='field'?8001:8002,$paymentId);
    if(($confirmed['verified_source']??null)!==$source)
        throw new RuntimeException('Trusted intake did not produce correct custody source.');
    $tenderId=(int)$confirmed['tender_id'];
    $proofReference=(string)$confirmed['payment_reference'];
    $p=$db->prepare('INSERT INTO v8_b2b_sale_tender_reservations_uat(company_id,branch_id,sale_intent_id,payment_intent_id,tender_id,retailer_id,canonical_party_id,channel,employee_id,payment_mode,payment_reference,verified_source,amount_paise,quote_digest) VALUES(?,?,?,?,?,77,?,?,?,?,?,?,20000,?)');
    $p->execute([$company,$branch,$saleId,$paymentId,$tenderId,$party,$channel,$employee,$mode,$proofReference,$source,$digest]);
    // No wp_eh7_b2b_verified_tenders fixture! The guarded reader must bridge
    // already-locked V8 evidence atomically into the authoritative V7 source.
    return ['sale_intent_id'=>$saleId,'payment_intent_id'=>$paymentId,'tender_id'=>$tenderId,'digest'=>$digest];
}
function checkUat(bool $valid,string $message):void {if(!$valid)throw new RuntimeException('FAIL '.$message);echo 'PASS '.$message."\n";}
function first(PDO $pdo,string $sql,array $args=[]):mixed {$stmt=$pdo->prepare($sql);$stmt->execute($args);return $stmt->fetchColumn();}
function postContext(int $sale):array{return ['company_id'=>987665531,'branch_id'=>4001,'actor_id'=>8001,'retailer_id'=>77,'sale_intent_id'=>$sale,'idempotency_key'=>'CI-CANON-'.str_pad((string)$sale,8,'0',STR_PAD_LEFT)];}
try{
    $actor=new \ExcelHerbal\ERP7\Security\Actor($user,$employee,$company,$branch,[$branch],['sales.create'],'BM');
    $writer=new \ExcelHerbal\ERP8\B2B\V7CanonicalPostingSinkUat($actor,new \ExcelHerbal\ERP8\B2B\V7UatLockedCheckoutReader());
    $pair=createIntent($pdo,$company,$branch,$product,$party,$mainDay,'CI-CASH-INT-A');
    checkUat((int)first($pdo,'SELECT COUNT(*) FROM wp_eh7_b2b_verified_tenders WHERE sale_intent_id=?',[$pair['sale_intent_id']])===0,'canonical tender is not manually pre-seeded');
    checkUat((int)first($pdo,'SELECT COUNT(*) FROM v8_b2b_tender_intake_evidence_uat WHERE intent_id=? AND confirmed_tender_id=?',[$pair['payment_intent_id'],$pair['tender_id']])===1,
        'trusted V8 intake gateway created one original payment evidence record');
    $sale=$writer->post(postContext($pair['sale_intent_id']));
    checkUat($sale['status']==='posted' && $sale['replayed']===false,'real V7 B2B sale and journal posted');
    checkUat((int)first($pdo,'SELECT COUNT(*) FROM wp_eh7_b2b_verified_tenders WHERE sale_intent_id=? AND consumed_sale_id=?',[$pair['sale_intent_id'],$sale['sale_id']])===1,
        'trusted locked V8 evidence promoted and consumed once in canonical tender table');
    checkUat((int)first($pdo,'SELECT quantity*1000 FROM wp_eh7_stock_balances WHERE company_id=? AND product_id=?',[$company,$product])===8000,'real canonical V7 stock decreased by 2 PCS');
    checkUat((int)first($pdo,"SELECT COUNT(*) FROM wp_eh7_stock_ledger WHERE source_type='b2b_retailer_sale' AND source_id=?",[$sale['sale_id']])===1,'real V7 stock ledger records one OUT');
    $dr=(float)first($pdo,'SELECT SUM(debit) FROM wp_eh7_journal_lines WHERE journal_entry_id=?',[$sale['journal_id']]);
    $cr=(float)first($pdo,'SELECT SUM(credit) FROM wp_eh7_journal_lines WHERE journal_entry_id=?',[$sale['journal_id']]);
    checkUat(abs($dr-$cr)<0.005 && $dr===280.0,'real V7 GL balanced Cash+COGS against Sales+Inventory');
    checkUat(first($pdo,'SELECT status FROM v8_b2b_sale_intents_uat WHERE id=?',[$pair['sale_intent_id']])==='posted' && first($pdo,'SELECT status FROM v8_b2b_payment_intents_uat WHERE id=?',[$pair['payment_intent_id']])==='consumed','original sale/payment intents finalized');
    checkUat(first($pdo,'SELECT status FROM v8_b2b_sale_tender_reservations_uat WHERE sale_intent_id=?',[$pair['sale_intent_id']])==='consumed' && (int)first($pdo,'SELECT consumed_sale_id FROM v8_b2b_verified_tenders WHERE id=?',[$pair['tender_id']])===$sale['sale_id'],'reservation and tender consumed exactly once');
    $again=$writer->post(postContext($pair['sale_intent_id']));
    checkUat($again['replayed']===true && $again['sale_id']===$sale['sale_id'],'same request replays original sale without another posting');
    checkUat((int)first($pdo,"SELECT COUNT(*) FROM wp_eh7_stock_ledger WHERE company_id=? AND source_type='b2b_retailer_sale'",[$company])===1 && (int)first($pdo,'SELECT COUNT(*) FROM wp_eh7_journal_entries WHERE company_id=?',[$company])===1,'retry does not duplicate V7 ledger entries');
    $bad=createIntent($pdo,$company,$branch,$product,$party,$mainDay,'CI-CASH-INT-B');
    $wp->failJournalInsert=true;
    $blocked=false;
    try{$writer->post(postContext($bad['sale_intent_id']));}catch(Throwable $e){$blocked=true;}
    $wp->failJournalInsert=false;
    checkUat($blocked,'journal insert failure rejects entire canonical transaction');
    checkUat((int)first($pdo,'SELECT COUNT(*) FROM wp_eh7_b2b_verified_tenders WHERE sale_intent_id=?',[$bad['sale_intent_id']])===0,
        'journal failure also rolls back canonical tender promotion');
    checkUat((int)first($pdo,'SELECT quantity*1000 FROM wp_eh7_stock_balances WHERE company_id=? AND product_id=?',[$company,$product])===8000,'journal failure rolls back canonical stock');
    checkUat((int)first($pdo,'SELECT COUNT(*) FROM wp_eh7_b2b_retailer_sales WHERE sale_intent_id=?',[$bad['sale_intent_id']])===0 && first($pdo,'SELECT status FROM v8_b2b_sale_intents_uat WHERE id=?',[$bad['sale_intent_id']])==='awaiting_payment','journal failure rolls back sale header and evidence state');
    checkUat((int)first($pdo,'SELECT COUNT(*) FROM wp_eh7_b2b_checkout_keys WHERE company_id=? AND request_key=?',[$company,postContext($bad['sale_intent_id'])['idempotency_key']])===0,'failed idempotency lock rolled back');
    // A forged reservation proof source must not gain a canonical tender even
    // if an original tender/evidence row is otherwise marked confirmed.
    $tampered=createIntent($pdo,$company,$branch,$product,$party,$mainDay,'CI-REJECT-PROOF-BRIDGE');
    $pdo->prepare("UPDATE v8_b2b_sale_tender_reservations_uat SET verified_source='bank_settlement' WHERE sale_intent_id=?")
        ->execute([$tampered['sale_intent_id']]);
    $rejected=false;
    try{$writer->post(postContext($tampered['sale_intent_id']));}catch(Throwable $e){$rejected=true;}
    checkUat($rejected,'mismatched reservation verification source rejects canonical tender promotion');
    checkUat((int)first($pdo,'SELECT COUNT(*) FROM wp_eh7_b2b_verified_tenders WHERE sale_intent_id=?',[$tampered['sale_intent_id']])===0,
        'rejected bridge cannot leave a canonical tender or financial posting');
    // End-to-end FIELD Cash: the collection is employee custody, not cashier remittance.
    $pdo->prepare("INSERT INTO wp_eh7_stock_balances(company_id,branch_id,product_id,batch_key,custodian_key,quantity,average_unit_cost,updated_at)
      VALUES(?,?,?,0,?,5.000,40.0000,?) ON DUPLICATE KEY UPDATE quantity=5.000,average_unit_cost=40.0000")
        ->execute([$company,$branch,$product,$employee,$mainDay]);
    $field=createIntent($pdo,$company,$branch,$product,$party,$mainDay,'CI-FIELD-CASH-1','field',$employee);
    $fieldSale=$writer->post(postContext($field['sale_intent_id']));
    checkUat($fieldSale['status']==='posted' && $fieldSale['employee_cash_to_remit_paise']===20000,'field cash posts as employee liability pending physical deposit');
    checkUat(first($pdo,'SELECT verified_source FROM wp_eh7_b2b_verified_tenders WHERE sale_intent_id=?',[$field['sale_intent_id']])==='employee_cash_custody',
        'field cash canonical bridge preserves employee-custody source');
    checkUat((int)first($pdo,'SELECT quantity*1000 FROM wp_eh7_stock_balances WHERE company_id=? AND product_id=? AND custodian_key=?',[$company,$product,$employee])===3000,'field cash only reduces employee stock custody');
    checkUat((int)first($pdo,'SELECT quantity*1000 FROM wp_eh7_stock_balances WHERE company_id=? AND product_id=? AND custodian_key=0',[$company,$product])===8000,'field cash does not take stock from branch warehouse');
    $transitId=(int)first($pdo,"SELECT id FROM wp_eh7_accounts WHERE company_id=? AND code='EMPLOYEE_CASH_IN_TRANSIT'",[$company]);
    checkUat((float)first($pdo,'SELECT debit FROM wp_eh7_journal_lines WHERE journal_entry_id=? AND account_id=?',[$fieldSale['journal_id'],$transitId])===200.0,'field cash debits Employee Cash in Transit, not Branch Cash');
    checkUat(first($pdo,'SELECT party_type FROM wp_eh7_journal_lines WHERE journal_entry_id=? AND account_id=?',[$fieldSale['journal_id'],$transitId])==='employee'
        && (int)first($pdo,'SELECT party_id FROM wp_eh7_journal_lines WHERE journal_entry_id=? AND account_id=?',[$fieldSale['journal_id'],$transitId])===$employee,'field Cash journal is tagged to the correct employee ledger');

    // CANONICAL CASH HANDOVER UAT: independent authenticated cashier evidence
    // plus real V7 AccountingService journal on the SAME PDO-backed WordPress DB.
    // The receipt and remittance table are disposable DRAFT source/audit records;
    // wp_eh7_journal_entries / journal_lines remain the ONLY GL.
    $financeActor=new \ExcelHerbal\ERP7\Security\Actor(
        8002,9002,$company,$branch,[$branch],
        [\ExcelHerbal\ERP7\Security\Capabilities::ACCOUNTING_VIEW],'BM');
    $cashierAuthority=static fn($action,$actor,$c,$b)=>
        in_array($action,['cash_receipt.attest','cash_remittance.post'],true)
        &&$actor===8002&&$c===$company&&$b===$branch;
    $cashier=new \ExcelHerbal\ERP8\B2B\V7CanonicalCashHandoverUat($financeActor,$cashierAuthority);
    $cashDenied=false;
    try{$cashier->post($branch,$fieldSale['sale_id'],'CI-CASH-HANDOVER-001');}
    catch(\ExcelHerbal\ERP8\B2B\RetailerSaleError $e){$cashDenied=true;}
    checkUat($cashDenied,'unattested field Cash cannot be reclassified in canonical V7 GL');
    $selfActor=new \ExcelHerbal\ERP7\Security\Actor(
        $user,$employee,$company,$branch,[$branch],
        [\ExcelHerbal\ERP7\Security\Capabilities::ACCOUNTING_VIEW],'BM');
    $selfCashier=new \ExcelHerbal\ERP8\B2B\V7CanonicalCashHandoverUat(
        $selfActor,static fn()=>true);
    $selfDenied=false;
    try{$selfCashier->attest($branch,$fieldSale['sale_id'],'CI-CASHIER-REF-001');}
    catch(\ExcelHerbal\ERP8\B2B\RetailerSaleError $e){$selfDenied=true;}
    checkUat($selfDenied,'original field seller cannot self-attest branch cashier receipt');
    $wrongBranch=false;
    try{$cashier->attest($branch+1,$fieldSale['sale_id'],'CI-CASHIER-REF-001');}
    catch(Throwable $e){$wrongBranch=true;}
    checkUat($wrongBranch,'cashier cannot attest outside authorized branch');
    $unprivileged=new \ExcelHerbal\ERP8\B2B\V7CanonicalCashHandoverUat(
        new \ExcelHerbal\ERP7\Security\Actor(8003,9003,$company,$branch,[$branch],[],'FSE'),
        static fn()=>true);
    $unprivilegedDenied=false;
    try{$unprivileged->attest($branch,$fieldSale['sale_id'],'CI-CASHIER-REF-001');}
    catch(Throwable $e){$unprivilegedDenied=true;}
    checkUat($unprivilegedDenied,'server-side finance permission blocks unauthorized cashier');
    $receipt=$cashier->attest($branch,$fieldSale['sale_id'],'CI-CASHIER-REF-001');
    checkUat($receipt['amount_paise']===20000 && !$receipt['already_attested'],
        'independent cashier receipt derives exact Cash amount from V7 posted sale');
    $receiptRetry=$cashier->attest($branch,$fieldSale['sale_id'],'CI-CASHIER-REF-001');
    checkUat($receiptRetry['receipt_id']===$receipt['receipt_id']&&$receiptRetry['already_attested'],
        'cashier exact duplicate attestation does not create a second physical receipt');
    $newRefDenied=false;
    try{$cashier->attest($branch,$fieldSale['sale_id'],'CI-CASHIER-REF-ALTERED');}
    catch(\ExcelHerbal\ERP8\B2B\RetailerSaleError $e){$newRefDenied=true;}
    checkUat($newRefDenied,'cashier receipt cannot change after attestation');
    $pdo->beginTransaction();
    try {
        $pdo->prepare('UPDATE wp_eh7_b2b_cashier_receipts_uat SET amount_paise=19999 WHERE id=?')
            ->execute([$receipt['receipt_id']]);
        $tamperedRejected=false;
        try{$cashier->post($branch,$fieldSale['sale_id'],'CI-CASH-HANDOVER-001');}
        catch(\ExcelHerbal\ERP8\B2B\RetailerSaleError $e){$tamperedRejected=true;}
        checkUat($tamperedRejected,'forged short cashier receipt cannot post canonical GL');
    } finally {if($pdo->inTransaction())$pdo->rollBack();}
    // Closed posting period must fail before any Cash reclassification.
    $pdo->prepare("INSERT INTO wp_eh7_accounting_periods(company_id,period_start,period_end,status)
      VALUES(?,'2026-10-19','2026-10-19','closed')")->execute([$company]);
    $closedDenied=false;
    try{$cashier->post($branch,$fieldSale['sale_id'],'CI-CASH-HANDOVER-001');}
    catch(Throwable $e){$closedDenied=true;}
    checkUat($closedDenied,'canonical accounting period close blocks Cash handover journal');
    checkUat((int)first($pdo,'SELECT COUNT(*) FROM wp_eh7_b2b_cash_remittances WHERE company_id=?',[$company])===0,
        'period close creates no Cash remittance source');
    $pdo->prepare("DELETE FROM wp_eh7_accounting_periods WHERE company_id=? AND status='closed'")->execute([$company]);
    // Force real AccountingService journal write to fail to test atomic rollback.
    $wp->failJournalInsert=true;
    $failedRemit=false;
    try{$cashier->post($branch,$fieldSale['sale_id'],'CI-CASH-HANDOVER-001');}
    catch(Throwable $e){$failedRemit=true;}
    $wp->failJournalInsert=false;
    checkUat($failedRemit,'injected V7 GL journal failure rejects Cash handover');
    checkUat((int)first($pdo,'SELECT COUNT(*) FROM wp_eh7_b2b_cash_remittances WHERE company_id=?',[$company])===0
      && first($pdo,'SELECT consumed_remittance_id FROM wp_eh7_b2b_cashier_receipts_uat WHERE id=?',[$receipt['receipt_id']])===null,
      'journal failure rolls back Cash source and preserves unconsumed cashier proof');
    $remit=$cashier->post($branch,$fieldSale['sale_id'],'CI-CASH-HANDOVER-001');
    checkUat($remit['status']==='posted' && !$remit['replayed'] && $remit['amount_paise']===20000,
        'full Cash handover created one posted V7 canonical reclassification');
    checkUat((int)first($pdo,"SELECT COUNT(*) FROM wp_eh7_journal_entries WHERE company_id=? AND source_type='b2b_cash_remittance' AND source_id=?",[$company,$remit['remittance_id']])===1,
        'exactly one Cash remittance posted via existing AccountingService');
    $branchCashId=(int)first($pdo,"SELECT id FROM wp_eh7_accounts WHERE company_id=? AND code='BRANCH_CASH'",[$company]);
    checkUat((float)first($pdo,'SELECT debit FROM wp_eh7_journal_lines WHERE journal_entry_id=? AND account_id=?',[$remit['journal_id'],$branchCashId])===200.0
        &&(float)first($pdo,'SELECT credit FROM wp_eh7_journal_lines WHERE journal_entry_id=? AND account_id=?',[$remit['journal_id'],$transitId])===200.0,
        'canonical GL Dr Branch Cash / Cr Employee Cash in Transit for exact ₹200');
    checkUat((int)first($pdo,'SELECT SUM(debit)*100 FROM wp_eh7_journal_lines WHERE journal_entry_id=?',[$remit['journal_id']])===20000
        &&(int)first($pdo,'SELECT SUM(credit)*100 FROM wp_eh7_journal_lines WHERE journal_entry_id=?',[$remit['journal_id']])===20000,
        'canonical cash handover journal balances to the paise');
    checkUat(first($pdo,'SELECT party_type FROM wp_eh7_journal_lines WHERE journal_entry_id=? AND account_id=?',[$remit['journal_id'],$transitId])==='employee'
      &&(int)first($pdo,'SELECT party_id FROM wp_eh7_journal_lines WHERE journal_entry_id=? AND account_id=?',[$remit['journal_id'],$transitId])===$employee,
      'canonical employee ledger pairs sale-time Cash debit with cashier-time Cash credit');
    checkUat((int)first($pdo,'SELECT COUNT(*) FROM wp_eh7_b2b_retailer_sales WHERE company_id=? AND sale_intent_id=?',[$company,$field['sale_intent_id']])===1
      &&(int)first($pdo,"SELECT COUNT(*) FROM wp_eh7_stock_ledger WHERE source_type='b2b_retailer_sale' AND source_id=?",[$fieldSale['sale_id']])===1,
      'Cash handover does not create another sale or subtract employee stock twice');
    checkUat((int)first($pdo,'SELECT consumed_remittance_id FROM wp_eh7_b2b_cashier_receipts_uat WHERE id=?',[$receipt['receipt_id']])===$remit['remittance_id'],
      'single original cashier attestation consumed once by canonical remittance');
    $remitRetry=$cashier->post($branch,$fieldSale['sale_id'],'CI-CASH-HANDOVER-001');
    checkUat($remitRetry['replayed']===true && $remitRetry['journal_id']===$remit['journal_id'],
      'exact idempotent Cash retry returns original canonical journal');
    $newKeyDenied=false;
    try{$cashier->post($branch,$fieldSale['sale_id'],'CI-CASH-HANDOVER-NEW-KEY');}
    catch(\ExcelHerbal\ERP8\B2B\RetailerSaleError $e){$newKeyDenied=true;}
    checkUat($newKeyDenied,'same field sale cannot remittance-post under another idempotency key');
    $receiptAfter=$cashier->attest($branch,$fieldSale['sale_id'],'CI-CASHIER-REF-001');
    checkUat($receiptAfter['consumed']===true,'cashier receipt replay identifies previously consumed evidence');
    $afterJournal=$pdo->prepare(
        "SELECT j.source_type,j.source_id,l.debit,l.credit FROM wp_eh7_journal_entries j
          JOIN wp_eh7_journal_lines l ON l.journal_entry_id=j.id
          WHERE j.company_id=? AND l.party_type='employee' AND l.party_id=?
            AND j.source_type IN ('b2b_retailer_sale','b2b_cash_remittance')
          ORDER BY j.id");
    $afterJournal->execute([$company,$employee]);
    $employeeLedger=$afterJournal->fetchAll(PDO::FETCH_ASSOC);
    checkUat(count($employeeLedger)===2
      &&(float)$employeeLedger[0]['debit']===200.0
      &&(float)$employeeLedger[1]['credit']===200.0,
      'real employee-linked person ledger shows matching Cash collection and cashier handover');
    // UPI: bank settlement is distinct from both employee cash and branch cash.
    $upi=createIntent($pdo,$company,$branch,$product,$party,$mainDay,'CI-UPI-TXN-001','counter',null,'upi');
    checkUat(first($pdo,'SELECT verified_by FROM v8_b2b_tender_intake_evidence_uat WHERE intent_id=?',[$upi['payment_intent_id']])==8002,
        'UPI evidence came from separate synthetic verifier actor through trusted intake');
    $upiSale=$writer->post(postContext($upi['sale_intent_id']));
    $upiId=(int)first($pdo,"SELECT id FROM wp_eh7_accounts WHERE company_id=? AND code='UPI_CLEARING'",[$company]);
    checkUat($upiSale['status']==='posted' && $upiSale['employee_cash_to_remit_paise']===0,'UPI posts without employee cash remittance');
    checkUat(first($pdo,'SELECT verified_source FROM wp_eh7_b2b_verified_tenders WHERE sale_intent_id=?',[$upi['sale_intent_id']])==='bank_settlement',
        'UPI canonical bridge preserves bank-settlement source');
    checkUat((float)first($pdo,'SELECT debit FROM wp_eh7_journal_lines WHERE journal_entry_id=? AND account_id=?',[$upiSale['journal_id'],$upiId])===200.0,'UPI payment debits UPI clearing not physical cash');
    checkUat(first($pdo,'SELECT status FROM v8_b2b_sale_intents_uat WHERE id=?',[$upi['sale_intent_id']])==='posted'
         && first($pdo,'SELECT status FROM v8_b2b_payment_intents_uat WHERE id=?',[$upi['payment_intent_id']])==='consumed','UPI posting finalizes original payment evidence');
    // A forged bank signature must fail BEFORE a payment evidence row exists or
    // the actual V7 stock/accounting writer may post.
    $signedEvidenceBefore=(int)first($pdo,"SELECT COUNT(*) FROM v8_b2b_tender_intake_evidence_uat WHERE company_id=? AND payment_mode='upi'",[$company]);
    $forgeryRejected=false;
    try{createIntent($pdo,$company,$branch,$product,$party,$mainDay,'CI-UPI-FORGED-MAC','counter',null,'upi',true);}
    catch(\ExcelHerbal\ERP8\B2B\RetailerSaleError $e){$forgeryRejected=true;}
    checkUat($forgeryRejected,'real PDO canonical UPI intake rejects forged reconciliation HMAC');
    checkUat((int)first($pdo,"SELECT COUNT(*) FROM v8_b2b_tender_intake_evidence_uat WHERE company_id=? AND payment_mode='upi'",[$company])===$signedEvidenceBefore,
      'forged HMAC cannot create evidence for V7 posting');
    // Deterministic concurrency test: two INDEPENDENT MariaDB sessions contend
    // for the same immutable source row. Do not turn off unique constraints.
    $pdo->exec('SET SESSION innodb_lock_wait_timeout=1');
    $peer=new PDO($dsn,getenv('V8_TEST_USER')?:'v8',getenv('V8_TEST_PASSWORD')?:'v8',[
        PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
    if($peer->query('SELECT DATABASE()')->fetchColumn()!=='v8_test')
        throw new RuntimeException('Refusing concurrency test outside v8_test');
    $held=createIntent($pdo,$company,$branch,$product,$party,$mainDay,'CI-ROW-LOCK-CONC-001');
    $heldContext=postContext($held['sale_intent_id']);
    $branchBefore=(int)first($pdo,'SELECT quantity*1000 FROM wp_eh7_stock_balances WHERE company_id=? AND branch_id=? AND product_id=? AND custodian_key=0',[$company,$branch,$product]);
    $peer->beginTransaction();
    try{
        $q=$peer->prepare('SELECT id FROM v8_b2b_sale_intents_uat WHERE company_id=? AND id=? FOR UPDATE');
        $q->execute([$company,$held['sale_intent_id']]);
        if((int)$q->fetchColumn()!==$held['sale_intent_id'])throw new RuntimeException('Second session could not lock source intent');
        $conflict=false;
        try{$writer->post($heldContext);}catch(Throwable $e){$conflict=true;}
        checkUat($conflict,'second connection cannot post while source intent is row-locked');
        checkUat((int)first($pdo,'SELECT COUNT(*) FROM wp_eh7_b2b_retailer_sales WHERE sale_intent_id=?',[$held['sale_intent_id']])===0
            && first($pdo,'SELECT status FROM v8_b2b_sale_intents_uat WHERE id=?',[$held['sale_intent_id']])==='awaiting_payment',
            'lock timeout rolls back sale and preserves open intent');
        checkUat((int)first($pdo,'SELECT quantity*1000 FROM wp_eh7_stock_balances WHERE company_id=? AND branch_id=? AND product_id=? AND custodian_key=0',[$company,$branch,$product])===$branchBefore,
            'blocked transaction does not reduce V7 stock');
    }finally{if($peer->inTransaction())$peer->rollBack();}
    $released=$writer->post($heldContext);
    checkUat($released['status']==='posted' && $released['replayed']===false,'posting succeeds after competing source-row lock releases');
    checkUat((int)first($pdo,"SELECT COUNT(*) FROM wp_eh7_stock_ledger WHERE source_type='b2b_retailer_sale' AND source_id=?",[$released['sale_id']])===1
        && (int)first($pdo,'SELECT COUNT(*) FROM wp_eh7_journal_entries WHERE company_id=? AND source_type=? AND source_id=?',[$company,'b2b_retailer_sale',$released['sale_id']])===1,
        'lock retry produces exactly one stock movement and one journal');
    $differentKey=$heldContext;$differentKey['idempotency_key'].='-DIFFERENT';
    $rejected=false;
    try{$writer->post($differentKey);}catch(Throwable $e){$rejected=true;}
    checkUat($rejected,'same issued payment cannot post again under a different idempotency key');
    checkUat((int)first($pdo,'SELECT COUNT(*) FROM wp_eh7_b2b_checkout_keys WHERE company_id=? AND request_key=?',[$company,$differentKey['idempotency_key']])===0,
        'rejected alternate idempotency key leaves no persistent lock row');
    // A UNIQUE key held by a different transaction must stop a competing writer;
    // rolling back the losing/competing writer must not leave sale or evidence.
    $heldKey=createIntent($pdo,$company,$branch,$product,$party,$mainDay,'CI-UNIQUE-LOCK-CONC-002');
    $keyContext=postContext($heldKey['sale_intent_id']);
    $peer->beginTransaction();
    try{
        $q=$peer->prepare('INSERT INTO wp_eh7_b2b_checkout_keys(company_id,request_key) VALUES(?,?)');
        $q->execute([$company,$keyContext['idempotency_key']]);
        $blocked=false;
        try{$writer->post($keyContext);}catch(Throwable $e){$blocked=true;}
        checkUat($blocked,'in-flight identical idempotency key serializes competing posting');
        checkUat((int)first($pdo,'SELECT COUNT(*) FROM wp_eh7_b2b_retailer_sales WHERE sale_intent_id=?',[$heldKey['sale_intent_id']])===0
            && first($pdo,'SELECT status FROM v8_b2b_sale_intents_uat WHERE id=?',[$heldKey['sale_intent_id']])==='awaiting_payment',
            'concurrent idempotency conflict leaves no partial canonical posting');
    }finally{if($peer->inTransaction())$peer->rollBack();}
    $final=$writer->post($keyContext);
    checkUat($final['status']==='posted' && $writer->post($keyContext)['replayed']===true,
        'released unique key posts once and subsequent request replays safely');
    echo "CANONICAL V7 REAL MARIADB UAT: ${GLOBALS['v7_checks'] ?? 'cash handover extended'} PASS; v8_test only; no WordPress deployment\n";
}catch(Throwable $e){fwrite(STDERR,'CANONICAL V7 MARIADB UAT FAILED: '.$e::class.' '.$e->getMessage().' at '.$e->getFile().':'.$e->getLine()."\n");exit(1);}
