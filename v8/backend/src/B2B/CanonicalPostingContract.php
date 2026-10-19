<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP8\B2B;

/**
 * Internal-only transaction port. An implementation MUST be backed by ONE InnoDB transaction:
 * lock idempotency => lock company, branch close, stock rows and party => revalidate price,
 * period and custody => consume trusted tender => canonical sale+StockService movement+GL.
 * The port does not have a production implementation. NEVER wire it to REST until the
 * tax/pricing policy, canonical retailer identity, payment source and reversal model are approved.
 */
interface CanonicalPostingGateway
{
    /** @return array<string,mixed> */
    public function atomic(callable $work): array;
    public function lockIdempotency(int $companyId, string $key): void;
    public function findPostedByKey(int $companyId, string $key): ?array;
    public function assertReleaseGates(int $companyId, int $branchId): void;
    public function assertAuthorizedRetailer(int $companyId, int $branchId, int $retailerId, int $actorId): void;
    /**
     * Lock affected canonical source rows and re-read inside SAME transaction.
     * Must NOT reuse an earlier preview snapshot. Field stock must be employee-custodied.
     * Must reject closed accounting period/day or unregistered GL source.
     * @return array assessment format compatible with CanonicalV7Readiness::assess,
     *   but with posting_allowed=true ONLY after all real release gates pass.
     */
    public function lockedAssessment(array $trustedRequest): array;
    /**
     * Consume a unique, trusted cashier/payment-provider acknowledgement under lock.
     * A client-supplied screenshot, reference, transaction ID or flag is never proof.
     */
    public function consumeVerifiedTender(int $companyId, int $branchId, string $mode, string $reference, int $amountPaise): void;
    /** Insert exactly ONE canonical sale source (not a second stock/finance book). */
    public function createCanonicalSource(array $header, array $lines): int;
    /** Call canonical StockService::move against branch OR employee bucket, with source ID. */
    public function moveCanonicalStock(int $sourceId, array $line): void;
    /** Call canonical AccountingService::post with a registered source; return journal ID. */
    public function postCanonicalJournal(int $sourceId, array $journalLines, string $date): int;
    /** Atomically record source, journal, fingerprint, receipt and idempotency result. */
    public function finalizeCanonicalSource(int $sourceId, int $journalId, array $record): array;
}

/** Pure arithmetic from locked canonical V7 data, not permission to invoice or post. */
final class CanonicalPostingPlan
{
    public static function fromLockedAssessment(array $a): array
    {
        if (($a['assessment'] ?? null) !== 'canonical_read_model_validated'
            || ($a['posting_allowed'] ?? null) !== true) {
            throw new RetailerSaleError('Canonical posting remains disabled until locked release gates pass.');
        }
        foreach (['company_id', 'branch_id', 'total_paise', 'paid_paise', 'cogs_paise'] as $k) {
            if (!isset($a[$k]) || !is_int($a[$k]) || $a[$k] < ($k === 'total_paise' || $k === 'paid_paise' ? 1 : 0)) {
                throw new RetailerSaleError('Missing or invalid canonical locked totals.');
            }
        }
        if ($a['total_paise'] !== $a['paid_paise'] || ($a['retailer_outstanding_paise'] ?? null) !== 0) {
            throw new RetailerSaleError('Retailer credit or incomplete payment is forbidden.');
        }
        $mode = $a['payment_mode'] ?? null;
        $channel = $a['channel'] ?? null;
        $employee = $a['employee_id'] ?? null;
        if (!in_array($mode, ['cash','upi'], true) || !in_array($channel,['field','counter'],true)
            || ($channel === 'field' && (!is_int($employee) || $employee <= 0))
            || ($channel === 'counter' && $employee !== null)) {
            throw new RetailerSaleError('Invalid canonical channel, custody or Cash/UPI tender.');
        }
        $paymentCode = $mode === 'upi' ? 'UPI_CLEARING'
            : ($channel === 'field' ? 'EMPLOYEE_CASH_IN_TRANSIT' : 'BRANCH_CASH');
        $coas = $a['canonical_account_ids'] ?? null;
        if (!is_array($coas)) throw new RetailerSaleError('Canonical ledger mapping required.');
        foreach ([$paymentCode,'SALES','COGS','INVENTORY'] as $code) {
            if (!isset($coas[$code]) || !is_int($coas[$code]) || $coas[$code] < 1) {
                throw new RetailerSaleError('Approved company Chart of Accounts IDs required: '.$code);
            }
        }
        if (count(array_unique([$coas[$paymentCode],$coas['SALES'],$coas['COGS'],$coas['INVENTORY']])) !== 4) {
            throw new RetailerSaleError('Payment, sales, COGS and inventory accounts must be distinct.');
        }
        $lines=$a['lines'] ?? null;
        if (!is_array($lines) || $lines===[] || count($lines)>200) throw new RetailerSaleError('Canonical stock lines required.');
        $stocks=[];$salesSum=0;$costSum=0;$seen=[];
        foreach($lines as $line){
            if (!is_array($line)) throw new RetailerSaleError('Malformed canonical posting line.');
            foreach(['product_id','batch_id','qty_pcs','canonical_stock_custodian','commercial_revision_id','unit_price_paise','line_total_paise','cogs_paise'] as $k){
                if(!array_key_exists($k,$line) || !is_int($line[$k]) || $line[$k]<0){
                    throw new RetailerSaleError('Untrusted canonical line: '.$k);
                }
            }
            if ($line['product_id']<1 || $line['qty_pcs']<1 || $line['commercial_revision_id']<1 || $line['unit_price_paise']<1) {
                throw new RetailerSaleError('Invalid canonical product quantity or price revision.');
            }
            $identity=$line['product_id'].':'.$line['batch_id'];
            if(isset($seen[$identity]))throw new RetailerSaleError('Duplicate canonical stock line.');
            $seen[$identity]=true;
            if ($line['canonical_stock_custodian']!==($employee??0)) {
                throw new RetailerSaleError('Canonical stock custody differs from authorized sales channel.');
            }
            if($line['unit_price_paise']>intdiv(PHP_INT_MAX,$line['qty_pcs'])
                || $line['line_total_paise']!==$line['unit_price_paise']*$line['qty_pcs']) {
                throw new RetailerSaleError('Canonical product amount mismatch or overflow.');
            }
            if ($salesSum>PHP_INT_MAX-$line['line_total_paise'] || $costSum>PHP_INT_MAX-$line['cogs_paise']) {
                throw new RetailerSaleError('Canonical posting totals overflow.');
            }
            $salesSum+=$line['line_total_paise'];$costSum+=$line['cogs_paise'];
            $stocks[]=['product_id'=>$line['product_id'], 'batch_id'=>$line['batch_id'],
                'custodian_employee_id'=>$employee, 'qty_pcs'=>$line['qty_pcs'],
                'commercial_revision_id'=>$line['commercial_revision_id'],
                'unit_price_paise'=>$line['unit_price_paise'],'line_total_paise'=>$line['line_total_paise'],
                'cost_paise'=>$line['cogs_paise']];
        }
        if ($salesSum!==$a['total_paise'] || $costSum!==$a['cogs_paise']) {
            throw new RetailerSaleError('Canonical locked line sums differ from payment or COGS.');
        }
        $total=$a['total_paise'];$cost=$a['cogs_paise'];
        $journal=[
            ['account_id'=>$coas[$paymentCode],'debit_paise'=>$total,'credit_paise'=>0],
            ['account_id'=>$coas['SALES'],'debit_paise'=>0,'credit_paise'=>$total],
        ];
        if($cost>0){
            $journal[]=['account_id'=>$coas['COGS'],'debit_paise'=>$cost,'credit_paise'=>0];
            $journal[]=['account_id'=>$coas['INVENTORY'],'debit_paise'=>0,'credit_paise'=>$cost];
        }
        $debit=array_sum(array_column($journal,'debit_paise'));
        $credit=array_sum(array_column($journal,'credit_paise'));
        if($debit!==$credit)throw new RetailerSaleError('Canonical journal is not balanced.');
        return ['company_id'=>$a['company_id'],'branch_id'=>$a['branch_id'],
            'business_date'=>$a['business_date']??null,'channel'=>$channel,'employee_id'=>$employee,
            'payment_mode'=>$mode,'gross_paise'=>$total,'cogs_paise'=>$cost,
            'retailer_outstanding_paise'=>0,'employee_cash_to_remit_paise'=>($mode==='cash'&&$channel==='field')?$total:0,
            'stock_movements'=>$stocks,'journal_lines'=>$journal];
    }
}

/**
 * Contract-level transaction choreography; it CAN post only with an independently
 * implemented, approved, transaction-safe canonical gateway. None is shipped in V8.
 */
final class CanonicalRetailerAtomicPosting
{
    public function __construct(private CanonicalPostingGateway $gateway) {}

    public function post(array $trusted): array
    {
        foreach (['company_id','branch_id','actor_id','retailer_id'] as $k) {
            if (!isset($trusted[$k]) || !is_int($trusted[$k]) || $trusted[$k] <= 0) {
                throw new RetailerSaleError('Trusted posting context missing: '.$k);
            }
        }
        $key=$trusted['idempotency_key']??null;
        if(!is_string($key)||!preg_match('/^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$/D',$key)){
            throw new RetailerSaleError('Canonical posting requires an idempotency key.');
        }
        $ref=$trusted['payment_reference']??null;
        if(!is_string($ref)||!preg_match('/^[A-Za-z0-9][A-Za-z0-9._:\/\-]{3,127}$/D',$ref)){
            throw new RetailerSaleError('A payment reference is required, not proof.');
        }
        $mode=$trusted['payment_mode']??null;
        if(!in_array($mode,['cash','upi'],true))throw new RetailerSaleError('Cash OR UPI only; no credit.');
        // The *caller* MUST supply server-resolved company, branch, actor and business datetime;
        // any HTTP adapter must strip client claims, amounts/prices and payment-confirmed flags.
        $fingerprint=hash('sha256',json_encode($trusted,JSON_THROW_ON_ERROR));
        $company=$trusted['company_id'];$branch=$trusted['branch_id'];
        return $this->gateway->atomic(function() use($trusted,$key,$ref,$mode,$fingerprint,$company,$branch):array {
            $this->gateway->lockIdempotency($company,$key);
            $prior=$this->gateway->findPostedByKey($company,$key);
            if($prior!==null){
                if(!hash_equals((string)($prior['request_fingerprint']??''),$fingerprint)){
                    throw new RetailerSaleError('Idempotency key reused with different sale inputs.');
                }
                return $prior;
            }
            $this->gateway->assertReleaseGates($company,$branch);
            $this->gateway->assertAuthorizedRetailer($company,$branch,$trusted['retailer_id'],$trusted['actor_id']);
            $locked=$this->gateway->lockedAssessment($trusted);
            $plan=CanonicalPostingPlan::fromLockedAssessment($locked);
            if($plan['company_id']!==$company||$plan['branch_id']!==$branch
                ||$plan['payment_mode']!==$mode||$plan['channel']!==($trusted['channel']??null)
                ||$plan['employee_id']!==($trusted['employee_id']??null)
                ||$plan['gross_paise']!==Paise::parse($trusted['paid_amount']??null)){
                throw new RetailerSaleError('Locked canonical assessment differs from trusted sale request.');
            }
            if(!is_string($plan['business_date']) || !preg_match('/^\d{4}-\d\d-\d\d$/D',$plan['business_date'])){
                throw new RetailerSaleError('Trusted business date missing from locked assessment.');
            }
            // The trusted gateway consumes the verified one-use tender under the transaction.
            $this->gateway->consumeVerifiedTender($company,$branch,$mode,$ref,$plan['gross_paise']);
            $header=['company_id'=>$company,'branch_id'=>$branch,'retailer_id'=>$trusted['retailer_id'],
                'actor_id'=>$trusted['actor_id'],'channel'=>$plan['channel'],'employee_id'=>$plan['employee_id'],
                'payment_mode'=>$mode,'payment_reference'=>$ref,'business_date'=>$plan['business_date'],
                'gross_paise'=>$plan['gross_paise'],'cogs_paise'=>$plan['cogs_paise'],'outstanding_paise'=>0];
            $saleId=$this->gateway->createCanonicalSource($header,$plan['stock_movements']);
            if($saleId<1)throw new RetailerSaleError('Canonical source creation failed.');
            foreach($plan['stock_movements'] as $line)$this->gateway->moveCanonicalStock($saleId,$line);
            $journalId=$this->gateway->postCanonicalJournal($saleId,$plan['journal_lines'],$plan['business_date']);
            if($journalId<1)throw new RetailerSaleError('Canonical journal was not posted.');
            $receipt=$this->gateway->finalizeCanonicalSource($saleId,$journalId,$header+[
                'idempotency_key'=>$key,'request_fingerprint'=>$fingerprint,
                'journal_id'=>$journalId,'sale_id'=>$saleId,'status'=>'posted',
                'employee_cash_to_remit_paise'=>$plan['employee_cash_to_remit_paise'],
            ]);
            if(($receipt['sale_id']??null)!==$saleId || ($receipt['journal_id']??null)!==$journalId
                || ($receipt['request_fingerprint']??null)!==$fingerprint) {
                throw new RetailerSaleError('Canonical posting receipt integrity check failed.');
            }
            return $receipt;
        });
    }
}
