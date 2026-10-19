<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP8\B2B;

/**
 * Framework-independent API controller. Session identity MUST come from the
 * authenticated backend, NEVER request JSON. Not registered on WordPress yet.
 */
final class RetailerApi
{
    public function __construct(private RetailerMaster $retailers, private RetailerCashSale $sales) {}

    /** Caller must resolve these from an authenticated session, not user input. */
    public function create(int $companyId, int $branchId, int $actorId, array $json): array
    {
        $safe = array_intersect_key($json, array_flip([
            'shop_name', 'contact_name', 'mobile', 'address', 'gstin', 'idempotency_key',
        ]));
        return self::present($this->retailers->register($safe + [
            'company_id' => $companyId, 'branch_id' => $branchId, 'actor_id' => $actorId,
        ]));
    }

    public function detail(int $companyId, int $branchId, int $actorId, int $retailerId): array
    {
        return self::present($this->retailers->detail($companyId, $branchId, $actorId, $retailerId));
    }

    public function list(int $companyId, int $branchId, int $actorId): array
    {
        return array_map(self::present(...), $this->retailers->all($companyId, $branchId, $actorId));
    }

    /** No internal idempotency fingerprints or access metadata sent to clients. */
    private static function present(array $row): array
    {
        return array_intersect_key($row, array_flip([
            'id', 'company_id', 'branch_id', 'type', 'shop_name', 'contact_name',
            'mobile', 'address', 'gstin', 'status', 'created_at',
        ]));
    }

    /** Business transaction is atomic; no balance/price/permissions from client. */
    public function postPaidSale(int $companyId, int $branchId, int $actorId, array $json): array
    {
        $safe = array_intersect_key($json, array_flip([
            'retailer_id', 'channel', 'employee_id', 'payment_mode',
            'payment_reference', 'paid_amount', 'idempotency_key', 'lines',
        ]));
        return $this->sales->post($safe + [
            'company_id' => $companyId, 'branch_id' => $branchId, 'actor_id' => $actorId,
        ]);
    }
}