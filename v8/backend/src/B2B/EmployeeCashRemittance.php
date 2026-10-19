<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP8\B2B;

/**
 * Separate retailer payment from employee-to-branch cash custody settlement.
 * V8 design gate: only a FULL, cashier-confirmed remittance is supported here.
 * Cash shortages/partial deposits require their own approved exception policy.
 */
interface EmployeeRemittanceGateway
{
    public function atomic(callable $work): array;
    public function canConfirmRemittance(int $actorId, int $companyId, int $branchId): bool;
    public function lockRemittanceKey(int $companyId, string $key): void;
    public function remittanceByKey(int $companyId, string $key): ?array;
    /** Must lock the referenced remittance row until the atomic() transaction ends. */
    public function pendingCash(int $companyId, int $branchId, int $saleId, int $employeeId): ?array;
    /** Must lock a one-use cashier-verified receipt for exactly this sale and amount. */
    public function confirmedBranchReceipt(int $companyId, int $branchId, int $saleId, int $employeeId, string $reference, int $amountPaise): bool;
    /** Save completion, consume receipt, and post balanced journal entries atomically. */
    public function recordCashRemittance(array $record, array $journal): array;
}

final class EmployeeCashRemittance
{
    public function __construct(private EmployeeRemittanceGateway $gateway) {}

    public function confirm(array $request): array
    {
        foreach (['company_id', 'branch_id', 'actor_id', 'employee_id', 'sale_id'] as $field) {
            if (!isset($request[$field]) || !is_int($request[$field]) || $request[$field] < 1) {
                throw new RetailerSaleError("Invalid {$field}.");
            }
        }
        $company = $request['company_id'];
        $branch = $request['branch_id'];
        $actor = $request['actor_id'];
        $employee = $request['employee_id'];
        $sale = $request['sale_id'];
        $key = $request['idempotency_key'] ?? null;
        if (!is_string($key) || !preg_match('/^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$/D', $key)) {
            throw new RetailerSaleError('Valid remittance idempotency key is required.');
        }
        $reference = $request['cash_receipt_reference'] ?? null;
        if (!is_string($reference) || trim($reference) !== $reference || !preg_match('/^[A-Za-z0-9][A-Za-z0-9._:\/-]{3,127}$/D', $reference)) {
            throw new RetailerSaleError('A cashier-confirmed cash receipt reference is required.');
        }
        $amount = Paise::parse($request['amount'] ?? null);
        if ($amount < 1) throw new RetailerSaleError('Branch cash remittance must exceed zero.');
        $fingerprint = hash('sha256', json_encode([$company, $branch, $actor, $employee, $sale, $key, $reference, $amount], JSON_THROW_ON_ERROR));

        return $this->gateway->atomic(function () use ($company, $branch, $actor, $employee, $sale, $key, $reference, $amount, $fingerprint): array {
            if (!$this->gateway->canConfirmRemittance($actor, $company, $branch)) {
                throw new RetailerSaleError('Cashier remittance authority denied.');
            }
            $this->gateway->lockRemittanceKey($company, $key);
            $prior = $this->gateway->remittanceByKey($company, $key);
            if ($prior !== null) {
                if (($prior['request_fingerprint'] ?? '') !== $fingerprint) {
                    throw new RetailerSaleError('Remittance idempotency key reused with different details.');
                }
                return $prior;
            }
            $pending = $this->gateway->pendingCash($company, $branch, $sale, $employee);
            if (!$pending || ($pending['status'] ?? '') !== 'pending') {
                throw new RetailerSaleError('No pending field cash for this employee and sale.');
            }
            $due = $pending['amount_due_paise'] ?? null;
            $already = $pending['amount_remitted_paise'] ?? null;
            if (!is_int($due) || !is_int($already) || $due <= 0 || $already !== 0) {
                throw new RetailerSaleError('Remittance state invalid or partially posted.');
            }
            if ($due !== $amount) {
                throw new RetailerSaleError('Full employee cash remittance required; shortage exception is not approved.');
            }
            if (!$this->gateway->confirmedBranchReceipt($company, $branch, $sale, $employee, $reference, $amount)) {
                throw new RetailerSaleError('Branch cashier receipt is not independently confirmed or already consumed.');
            }
            $journal = [
                ['account' => 'BRANCH_CASH', 'debit_paise' => $amount, 'credit_paise' => 0],
                ['account' => 'EMPLOYEE_CASH_IN_TRANSIT', 'debit_paise' => 0, 'credit_paise' => $amount],
            ];
            return $this->gateway->recordCashRemittance([
                'company_id' => $company, 'branch_id' => $branch, 'actor_id' => $actor,
                'employee_id' => $employee, 'sale_id' => $sale,
                'amount_paise' => $amount, 'cash_receipt_reference' => $reference,
                'idempotency_key' => $key, 'request_fingerprint' => $fingerprint,
                'status' => 'posted',
            ], $journal);
        });
    }
}
