<?php
declare(strict_types=1);
require dirname(__DIR__) . '/src/B2B/RetailerCashSale.php';
use ExcelHerbal\ERP8\B2B\RetailerCashSale;
use ExcelHerbal\ERP8\B2B\RetailerSaleGateway;
use ExcelHerbal\ERP8\B2B\RetailerSaleError;
use ExcelHerbal\ERP8\B2B\Paise;

/** Test-only fake; DOES NOT claim concurrency/database tests. */
final class FakeGateway implements RetailerSaleGateway
{
    public array $sales = [];
    public array $stock = ['1:0:0' => 10, '1:0:6' => 5];
    public array $journals = [];
    public array $stockMoves = [];
    public bool $allowed = true;
    public bool $tenderConfirmed = true;
    public bool $failSave = false;
    public array $retailerRow = ['type' => 'retailer', 'status' => 'active'];
    public array $productRow = [
        'status'=>'active', 'mrp'=>'150.00', 'sale_price'=>'100.00',
        'ho_amount'=>'50.00', 'bm_profit'=>'20.00', 'salary_fund'=>'20.00',
        'office_expense'=>'10.00', 'points'=>'5.00', 'purchase_cost'=>'40.1250',
        'batch_required' => false,
    ];
    public function atomic(callable $work): array
    {
        $snapshot = [$this->sales, $this->stock, $this->journals, $this->stockMoves];
        try { return $work(); }
        catch (Throwable $e) {
            [$this->sales, $this->stock, $this->journals, $this->stockMoves] = $snapshot;
            throw $e;
        }
    }
    public function lockIdempotency(int $companyId, string $key): void {}
    public function findByIdempotency(int $companyId, string $key): ?array { return $this->sales[$companyId . ':' . $key] ?? null; }
    public function canSell(int $actorId, int $companyId, int $branchId, string $channel, ?int $employeeId): bool { return $this->allowed; }
    public function retailer(int $companyId, int $branchId, int $retailerId): ?array { return $this->retailerRow; }
    public function product(int $companyId, int $branchId, int $productId): ?array { return $this->productRow; }
    public function availablePcs(int $companyId, int $branchId, int $productId, int $batchId, ?int $custodianId): int
    { return $this->stock[$productId . ':' . $batchId . ':' . ($custodianId ?? 0)] ?? 0; }
    public function confirmedTender(int $companyId, int $branchId, string $mode, string $reference, int $amountPaise): bool { return $this->tenderConfirmed; }
    public function record(array $sale, array $stockMoves, array $journalLines): array
    {
        foreach ($stockMoves as $m) {
            $key = $m['product_id'] . ':' . $m['batch_id'] . ':' . ($m['custodian_id'] ?? 0);
            $this->stock[$key] += $m['quantity_delta'];
        }
        $this->stockMoves = array_merge($this->stockMoves, $stockMoves);
        if ($this->failSave) throw new RuntimeException('Simulated DB error');
        $this->journals[] = $journalLines;
        $sale['id'] = count($this->sales) + 1;
        $this->sales[$sale['company_id'] . ':' . $sale['idempotency_key']] = $sale;
        return $sale;
    }
}
function request(array $overrides = []): array
{
    return array_replace([
        'company_id'=>1, 'branch_id'=>1, 'actor_id'=>2, 'retailer_id'=>55,
        'channel'=>'counter', 'employee_id'=>null, 'idempotency_key'=>'sample-key-00001',
        'payment_mode'=>'cash', 'payment_reference'=>'CASH-ACK-001',
        'paid_amount'=>'300.00', 'lines'=>[['product_id'=>1, 'batch_id'=>0, 'qty'=>3]],
    ], $overrides);
}
function expectFailure(string $reason, callable $f): void
{
    try { $f(); }
    catch (RetailerSaleError $e) {
        if (stripos($e->getMessage(), $reason) === false) {
            throw new RuntimeException("Expected error '{$reason}'; got " . $e->getMessage());
        }
        return;
    }
    throw new RuntimeException("Expected failure containing '{$reason}'");
}
$tests = [];
$tests['paid counter cash, no outstanding, balanced journal'] = function () {
    $g = new FakeGateway;
    $s = (new RetailerCashSale($g))->post(request());
    assert($s['invoice_total_paise'] === 30000 && $s['retailer_outstanding_paise'] === 0);
    assert($s['employee_cash_remittance_paise'] === 0 && $g->stock['1:0:0'] === 7);
    assert($g->journals[0][0]['account'] === 'BRANCH_CASH');
    assert(array_sum(array_column($g->journals[0], 'debit_paise')) === array_sum(array_column($g->journals[0], 'credit_paise')));
    assert($s['points_posted'] === false && $s['lines'][0]['cost_paise'] === 12038);
};
$tests['field cash is employee remittance, never retailer credit'] = function () {
    $g = new FakeGateway;
    $s = (new RetailerCashSale($g))->post(request([
        'channel'=>'field', 'employee_id'=>6, 'paid_amount'=>'200.00',
        'lines'=>[['product_id'=>1,'batch_id'=>0,'qty'=>2]],
    ]));
    assert($s['employee_cash_remittance_paise'] === 20000 && $s['retailer_outstanding_paise'] === 0);
    assert($g->journals[0][0]['account'] === 'EMPLOYEE_CASH_IN_TRANSIT' && $g->stock['1:0:6'] === 3);
};
$tests['UPI credited only through verified clearing'] = function () {
    $g = new FakeGateway;
    $s = (new RetailerCashSale($g))->post(request(['payment_mode'=>'upi','payment_reference'=>'UPI-TRX-991']));
    assert($s['payment_mode'] === 'upi' && $g->journals[0][0]['account'] === 'UPI_CLEARING');
};
$tests['reject partial payment / credit'] = function () { expectFailure('Full verified payment', fn() => (new RetailerCashSale(new FakeGateway))->post(request(['paid_amount'=>'299.99']))); };
$tests['reject excess payment'] = function () { expectFailure('Full verified payment', fn() => (new RetailerCashSale(new FakeGateway))->post(request(['paid_amount'=>'300.01']))); };
$tests['reject prohibited credit payment mode'] = function () { expectFailure('cash OR UPI', fn() => (new RetailerCashSale(new FakeGateway))->post(request(['payment_mode'=>'credit']))); };
$tests['reject mixed tender pending owner approval'] = function () { expectFailure('cash OR UPI', fn() => (new RetailerCashSale(new FakeGateway))->post(request(['payment_mode'=>'cash+upi']))); };
$tests['reject unverified UPI even full amount'] = function () { $g = new FakeGateway; $g->tenderConfirmed=false; expectFailure('not confirmed', fn() => (new RetailerCashSale($g))->post(request(['payment_mode'=>'upi']))); assert(!$g->sales && $g->stock['1:0:0']===10); };
$tests['reject inactive retailer'] = function () { $g=new FakeGateway; $g->retailerRow['status']='inactive'; expectFailure('active retailer',fn()=>(new RetailerCashSale($g))->post(request())); };
$tests['reject wrong party type'] = function () { $g=new FakeGateway; $g->retailerRow['type']='supplier'; expectFailure('active retailer',fn()=>(new RetailerCashSale($g))->post(request())); };
$tests['enforce server-side authorization'] = function () { $g=new FakeGateway; $g->allowed=false; expectFailure('Actor lacks',fn()=>(new RetailerCashSale($g))->post(request())); };
$tests['reject insufficient stock'] = function () { $g=new FakeGateway; $g->stock['1:0:0']=1; expectFailure('Insufficient',fn()=>(new RetailerCashSale($g))->post(request())); };
$tests['reject wrong employee stock bucket'] = function () { $g=new FakeGateway; $g->stock['1:0:6']=1; expectFailure('Insufficient',fn()=>(new RetailerCashSale($g))->post(request(['channel'=>'field','employee_id'=>6]))); };
$tests['reject commercial allocation mismatch'] = function () { $g=new FakeGateway; $g->productRow['bm_profit']='19.00'; expectFailure('must equal Sale Price',fn()=>(new RetailerCashSale($g))->post(request())); };
$tests['reject invalid MRP'] = function () { $g=new FakeGateway; $g->productRow['mrp']='99.00'; expectFailure('MRP',fn()=>(new RetailerCashSale($g))->post(request())); };
$tests['reject duplicate product batch'] = function () { expectFailure('Duplicate',fn()=>(new RetailerCashSale(new FakeGateway))->post(request(['lines'=>[['product_id'=>1,'batch_id'=>0,'qty'=>1],['product_id'=>1,'batch_id'=>0,'qty'=>2]]]))); };
$tests['reject decimal/negative/non-integer pieces'] = function () { expectFailure('whole PCS',fn()=>(new RetailerCashSale(new FakeGateway))->post(request(['lines'=>[['product_id'=>1,'batch_id'=>0,'qty'=>1.5]]]))); };
$tests['same idempotency request returns prior sale'] = function () { $g=new FakeGateway; $svc=new RetailerCashSale($g);$a=$svc->post(request());$b=$svc->post(request());assert($a['id']===$b['id'] && count($g->sales)===1 && $g->stock['1:0:0']===7); };
$tests['reused key with different request fails'] = function () { $g=new FakeGateway; $svc=new RetailerCashSale($g);$svc->post(request());expectFailure('different request',fn()=> $svc->post(request(['payment_reference'=>'CASH-ACK-DIFFERENT'])));assert(count($g->sales)===1); };
$tests['transaction failure rolls back stock'] = function () { $g=new FakeGateway;$g->failSave=true;try { (new RetailerCashSale($g))->post(request());throw new RuntimeException('Expected DB failure'); } catch (RuntimeException $e) { if($e->getMessage()==='Expected DB failure')throw $e; } assert($g->stock['1:0:0']===10 && !$g->sales && !$g->stockMoves); };
$tests['money precision including 4-decimal cost'] = function () { assert(Paise::parse('0.01')===1 && Paise::parse('10')===1000 && Paise::format(1001)==='10.01');assert(Paise::costTotal('40.1250',3)===12038);expectFailure('Invalid money',fn()=>Paise::parse('10.001')); };
$tests['cost multiplication overflow fails closed'] = function () {
    expectFailure('safe integer precision', fn() => Paise::costTotal('9999999999.9999',1000000));
};
$tests['sale multiplication overflow fails closed'] = function () {
    $g = new FakeGateway;
    $g->stock['1:0:0'] = 1000000;
    $g->productRow = array_replace($g->productRow, [
        'mrp' => '999999999999.00',
        'sale_price' => '999999999999.00',
        'ho_amount' => '999999999999.00',
        'bm_profit' => '0.00',
        'salary_fund' => '0.00',
        'office_expense' => '0.00',
    ]);
    expectFailure('safe integer precision', fn() => (new RetailerCashSale($g))->post(request([
        'lines'=>[['product_id'=>1,'batch_id'=>0,'qty'=>1000000]],
    ])));
    assert($g->stock['1:0:0'] === 1000000);
};
$tests['require field employee and forbid counter custodian'] = function () { expectFailure('require an employee',fn()=>(new RetailerCashSale(new FakeGateway))->post(request(['channel'=>'field'])));expectFailure('must use branch stock',fn()=>(new RetailerCashSale(new FakeGateway))->post(request(['employee_id'=>6]))); };
$tests['reject client price override via exact request schema'] = function () { $g=new FakeGateway;$s=(new RetailerCashSale($g))->post(request(['unit_price'=>'0.01']));assert($s['invoice_total_paise']===30000); };
$ok=0;
foreach($tests as $name=>$test){
    try{$test();$ok++;echo "PASS {$name}\n";}
    catch(Throwable $e){fwrite(STDERR,"FAIL {$name}: {$e->getMessage()}\n");exit(1);}
}
echo "PASS {$ok}/".count($tests)." tests\n";