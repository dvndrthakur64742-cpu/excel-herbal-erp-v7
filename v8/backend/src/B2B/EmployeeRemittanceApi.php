<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP8\B2B;

/**
 * Framework-independent cashier API adapter (NOT registered as a web route).
 * Company, branch and cashier actor must come from trusted authenticated context.
 * The API cannot create trusted receipt evidence; it only consumes existing proof.
 */
final class EmployeeRemittanceApi
{
    public function __construct(private EmployeeCashRemittance $service) {}

    public function confirmBranchCash(int $companyId, int $branchId, int $actorId, array $json): array
    {
        $safe = array_intersect_key($json, array_flip([
            'employee_id','sale_id','cash_receipt_reference','amount','idempotency_key',
        ]));
        $result = $this->service->confirm($safe + [
            'company_id'=>$companyId,'branch_id'=>$branchId,'actor_id'=>$actorId,
        ]);
        return array_intersect_key($result, array_flip([
            'id','company_id','branch_id','employee_id','sale_id','amount_paise',
            'cash_receipt_reference','status',
        ]));
    }
}
