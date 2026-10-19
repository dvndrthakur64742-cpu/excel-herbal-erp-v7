<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP8\B2B;

/**
 * UAT-only server-side tender intake. No REST route and no caller-supplied paid flag.
 * Cash: authorized collector confirms physical cash and assumes custody (not branch remittance).
 * UPI: an independently authenticated bank/PSP reconciliation source confirms settlement.
 */
interface TrustedTenderIntakeGateway
{
    public function atomic(callable $operation): array;
    /** Must SELECT ... FOR UPDATE immutable server-created payment intent. */
    public function lockedIntent(int $companyId, int $branchId, int $intentId): ?array;
    /** Implement with server-resolved RBAC and current employee/branch authority. */
    public function canCollectCash(int $companyId, int $branchId, int $actorId, string $channel, ?int $employeeId): bool;
    public function canVerifyUpi(int $companyId, int $branchId, int $actorId): bool;
    /** Trusted provider/bank SDK result. NEVER accept HTTP body or screenshot as this result. */
    public function verifiedBankPayment(string $providerLookupKey): ?array;
    /** Approved company/branch destination bank/UPI account from server configuration. */
    public function merchantAccount(int $companyId, int $branchId): string;
    /** One evidence row per intent, unique confirmed bank txn across company (including branches). */
    public function recordConfirmed(array $evidence): array;
}

final class TrustedTenderIntake
{
    public function __construct(private TrustedTenderIntakeGateway $gateway) {}

    public function cashCollected(int $companyId, int $branchId, int $actorId, int $intentId): array
    {
        self::ids($companyId, $branchId, $actorId, $intentId);
        return $this->gateway->atomic(function () use ($companyId, $branchId, $actorId, $intentId): array {
            $intent=$this->requireIntent($companyId,$branchId,$intentId,'cash');
            $channel=$intent['channel'];$employee=$intent['employee_id'];
            if (!$this->gateway->canCollectCash($companyId,$branchId,$actorId,$channel,$employee)) {
                throw new RetailerSaleError('Cash collection authority denied.');
            }
            // Actor IDs (WP users) are not employee IDs. The trusted authorization
            // callback MUST resolve actor -> assigned employee + active branch.
            return $this->gateway->recordConfirmed([
                'intent_id'=>$intentId,'company_id'=>$companyId,'branch_id'=>$branchId,
                'payment_mode'=>'cash','payment_reference'=>'CASH-INT-'.$companyId.'-'.$branchId.'-'.$intentId,
                'amount_paise'=>$intent['amount_paise'],
                'verified_source'=>$channel==='field'?'employee_cash_custody':'branch_cashier_cash',
                'verified_by'=>$actorId,'channel'=>$channel,'employee_id'=>$employee,
            ]);
        });
    }

    public function upiSettled(int $companyId,int $branchId,int $actorId,int $intentId,string $lookupKey): array
    {
        self::ids($companyId,$branchId,$actorId,$intentId);
        if (!preg_match('/^[A-Za-z0-9][A-Za-z0-9._:\/\-]{7,127}$/D',$lookupKey)) {
            throw new RetailerSaleError('Invalid bank transaction lookup key.');
        }
        return $this->gateway->atomic(function() use($companyId,$branchId,$actorId,$intentId,$lookupKey):array {
            $intent=$this->requireIntent($companyId,$branchId,$intentId,'upi');
            if (!$this->gateway->canVerifyUpi($companyId,$branchId,$actorId)) {
                throw new RetailerSaleError('UPI verification authority denied.');
            }
            $bank=$this->gateway->verifiedBankPayment($lookupKey);
            if (!is_array($bank) || ($bank['status']??null)!=='settled' || ($bank['currency']??null)!=='INR'
                || !isset($bank['amount_paise']) || !is_int($bank['amount_paise'])
                || $bank['amount_paise']!==$intent['amount_paise']) {
                throw new RetailerSaleError('Provider-verified settled INR payment for exact invoice amount required.');
            }
            $merchant=$this->gateway->merchantAccount($companyId,$branchId);
            if($merchant==='' || !is_string($bank['merchant_account']??null)
                || !hash_equals($merchant,$bank['merchant_account'])){
                throw new RetailerSaleError('Payment reached a different or unconfigured merchant account.');
            }
            $orderId=$intent['merchant_order_id']??null;
            if(!is_string($orderId)||$orderId===''||!is_string($bank['merchant_order_id']??null)
                ||!hash_equals($orderId,$bank['merchant_order_id'])){
                throw new RetailerSaleError('Bank settlement does not match the server-created merchant order.');
            }
            $reference=$bank['transaction_id']??null;
            if(!is_string($reference)||!preg_match('/^[A-Za-z0-9][A-Za-z0-9._:\/\-]{7,127}$/D',$reference)){
                throw new RetailerSaleError('Trusted provider transaction identifier required.');
            }
            return $this->gateway->recordConfirmed([
                'intent_id'=>$intentId,'company_id'=>$companyId,'branch_id'=>$branchId,
                'payment_mode'=>'upi','payment_reference'=>$reference,
                'amount_paise'=>$intent['amount_paise'],'verified_source'=>'bank_settlement',
                'verified_by'=>$actorId,'channel'=>$intent['channel'],'employee_id'=>$intent['employee_id'],
            ]);
        });
    }

    private function requireIntent(int $company,int $branch,int $intentId,string $mode):array
    {
        $row=$this->gateway->lockedIntent($company,$branch,$intentId);
        if(!is_array($row)||($row['company_id']??null)!==$company||($row['branch_id']??null)!==$branch
            ||($row['id']??null)!==$intentId||($row['payment_mode']??null)!==$mode
            ||($row['status']??null)!=='awaiting_payment'||($row['currency']??null)!=='INR'
            ||!isset($row['amount_paise'])||!is_int($row['amount_paise'])||$row['amount_paise']<=0){
            throw new RetailerSaleError('Valid open company/branch-scoped payment intent required.');
        }
        $channel=$row['channel']??null;
        $employee=$row['employee_id']??null;
        if(!in_array($channel,['field','counter'],true)
            ||($channel==='field'&&(!is_int($employee)||$employee<=0))
            ||($channel==='counter'&&$employee!==null)){
            throw new RetailerSaleError('Untrusted field/counter cash custody intent.');
        }
        return $row;
    }

    private static function ids(int ...$ids):void
    {
        foreach($ids as $id)if($id<=0)throw new RetailerSaleError('Trusted payment context requires positive identifiers.');
    }
}
