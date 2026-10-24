<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP8\B2B;

/**
 * UAT only. Independently attest that a branch cashier has physically received
 * the *entire* field employee cash balance for one already-paid retailer sale.
 * No public WordPress REST handler and no canonical V7 journal writer.
 */
interface IndependentCashierReceiptGateway
{
    public function atomic(callable $work): array;
    /** An active CASHIER from the server session; never a role flag in a request. */
    public function canAttest(int $actor, int $company, int $branch): bool;
    /** SELECT ... FOR UPDATE of the posted field-cash sale and its pending custody. */
    public function lockedFieldCash(int $company, int $branch, int $sale, int $employee): ?array;
    /** Cashier evidence including the signed attestation, not simply a text reference. */
    public function existingByReference(int $company, int $branch, string $reference): ?array;
    public function existingBySale(int $company, int $sale): ?array;
    /** Write unique one-use evidence and its independent maker/checker audit in one transaction. */
    public function storeAttestedReceipt(array $record): array;
}

final class IndependentCashierReceipt
{
    public function __construct(private IndependentCashierReceiptGateway $gateway) {}

    /** $context is server-trusted; a body-supplied paid flag/actor is never authority. */
    public function attest(array $context): array
    {
        foreach (['company_id','branch_id','actor_id','employee_id','sale_id'] as $key) {
            if (!isset($context[$key]) || !is_int($context[$key]) || $context[$key] <= 0) {
                throw new RetailerSaleError('Trusted positive ID required: '.$key);
            }
        }
        $ref=$context['cash_receipt_reference']??null;
        if (!is_string($ref) || trim($ref)!==$ref || !preg_match('/^[A-Za-z0-9][A-Za-z0-9._:\/-]{3,127}$/D',$ref)) {
            throw new RetailerSaleError('Valid cashier receipt reference required.');
        }
        $company=$context['company_id'];$branch=$context['branch_id'];
        $actor=$context['actor_id'];$employee=$context['employee_id'];$sale=$context['sale_id'];
        return $this->gateway->atomic(function () use ($company,$branch,$actor,$employee,$sale,$ref):array {
            if (!$this->gateway->canAttest($actor,$company,$branch)) {
                throw new RetailerSaleError('Independent branch cashier authorization denied.');
            }
            $pending=$this->gateway->lockedFieldCash($company,$branch,$sale,$employee);
            if (!is_array($pending) || ($pending['channel']??null)!=='field'
                || ($pending['payment_mode']??null)!=='cash'
                || ($pending['sale_status']??null)!=='paid_posted'
                || !is_int($pending['sale_actor_id']??null)
                || $pending['sale_actor_id']<=0
                || $pending['sale_actor_id']===$actor) {
                throw new RetailerSaleError('Cashier must be independent of a posted field Cash sale.');
            }
            $due=$pending['amount_due_paise']??null;
            if (!is_int($due) || $due<=0) throw new RetailerSaleError('Valid posted field cash liability required.');
            $byRef=$this->gateway->existingByReference($company,$branch,$ref);
            $bySale=$this->gateway->existingBySale($company,$sale);
            if ($byRef!==null || $bySale!==null) {
                if (!is_array($byRef) || !is_array($bySale)
                    || ($byRef['id']??null)!==($bySale['id']??null)
                    || ($byRef['company_id']??null)!==$company
                    || ($byRef['branch_id']??null)!==$branch
                    || ($byRef['employee_id']??null)!==$employee
                    || ($byRef['sale_id']??null)!==$sale
                    || ($byRef['amount_paise']??null)!==$due
                    || ($byRef['cash_receipt_reference']??null)!==$ref
                    || ($byRef['cashier_actor_id']??null)!==$actor
                    || ($byRef['verified_source']??null)!=='cashier'
                    || ($byRef['status']??null)!=='confirmed') {
                    throw new RetailerSaleError('Cashier receipt reference or sale has already been attested differently.');
                }
                return $byRef; // Exact replay: never acknowledge new physical cash.
            }
            if (($pending['custody_status']??null)!=='pending'
                || ($pending['amount_remitted_paise']??null)!==0) {
                throw new RetailerSaleError('Cash is already remitted or in an unsupported partial state.');
            }
            // Amount comes solely from the locked database row. Never trust cash amount
            // or 'receipt_confirmed' sent by the field employee/mobile browser.
            return $this->gateway->storeAttestedReceipt([
                'company_id'=>$company,'branch_id'=>$branch,'sale_id'=>$sale,
                'employee_id'=>$employee,'cashier_actor_id'=>$actor,
                'cash_receipt_reference'=>$ref,'amount_paise'=>$due,
                'verified_source'=>'cashier','status'=>'confirmed',
            ]);
        });
    }
}
