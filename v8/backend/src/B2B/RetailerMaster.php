<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP8\B2B;

/** Store operations are transactional and must enforce company/branch scoping. */
interface RetailerMasterGateway
{
    public function atomic(callable $work): array;
    public function canManage(int $actorId, int $companyId, int $branchId): bool;
    public function findByKey(int $companyId, int $branchId, string $key): ?array;
    public function create(array $record): array;
    public function get(int $companyId, int $branchId, int $retailerId): ?array;
    public function list(int $companyId, int $branchId, int $limit = 100): array;
}

/** A retailer is a CUSTOMER TYPE. Counter/field are SALE CHANNELS. */
final class RetailerMaster
{
    public function __construct(private RetailerMasterGateway $gateway) {}

    public function register(array $input): array
    {
        foreach (['company_id', 'branch_id', 'actor_id'] as $key) {
            if (!isset($input[$key]) || !is_int($input[$key]) || $input[$key] < 1) {
                throw new RetailerSaleError("Invalid {$key}.");
            }
        }
        $company = $input['company_id'];
        $branch = $input['branch_id'];
        $actor = $input['actor_id'];
        $requestKey = $input['idempotency_key'] ?? null;
        if (!is_string($requestKey) || !preg_match('/^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$/D', $requestKey)) {
            throw new RetailerSaleError('Retailer registration idempotency key is required.');
        }
        $name = self::limitedText($input['shop_name'] ?? null, 'Shop name', 160, true);
        $contact = self::limitedText($input['contact_name'] ?? null, 'Contact name', 120, false);
        $address = self::limitedText($input['address'] ?? null, 'Address', 500, false);
        $mobile = self::limitedText($input['mobile'] ?? null, 'Mobile', 16, false);
        if ($mobile !== null && !preg_match('/^\+?[0-9]{10,15}$/D', $mobile)) {
            throw new RetailerSaleError('Retailer mobile must have 10–15 digits, optional leading +.');
        }
        $gstin = self::limitedText($input['gstin'] ?? null, 'GSTIN', 15, false);
        if ($gstin !== null) {
            $gstin = strtoupper($gstin);
            if (!preg_match('/^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$/D', $gstin)) {
                throw new RetailerSaleError('Invalid GSTIN format; optional for retailer registration.');
            }
        }
        $canonical = [
            'company_id' => $company, 'branch_id' => $branch, 'type' => 'retailer',
            'shop_name' => $name, 'contact_name' => $contact,
            'mobile' => $mobile, 'address' => $address, 'gstin' => $gstin,
        ];
        $fingerprint = hash('sha256', json_encode($canonical, JSON_THROW_ON_ERROR));
        return $this->gateway->atomic(function () use ($company, $branch, $actor, $requestKey, $fingerprint, $canonical): array {
            if (!$this->gateway->canManage($actor, $company, $branch)) {
                throw new RetailerSaleError('Retailer master access denied.');
            }
            $prior = $this->gateway->findByKey($company, $branch, $requestKey);
            if ($prior !== null) {
                if (($prior['request_fingerprint'] ?? '') !== $fingerprint) {
                    throw new RetailerSaleError('Retailer registration key reused for a different shop.');
                }
                return $prior;
            }
            return $this->gateway->create($canonical + [
                'created_by' => $actor,
                'idempotency_key' => $requestKey,
                'request_fingerprint' => $fingerprint,
                'status' => 'active',
            ]);
        });
    }

    public function detail(int $company, int $branch, int $actor, int $retailerId): array
    {
        if (!$this->gateway->canManage($actor, $company, $branch)) {
            throw new RetailerSaleError('Retailer master access denied.');
        }
        $row = $this->gateway->get($company, $branch, $retailerId);
        if (!$row || ($row['type'] ?? '') !== 'retailer') {
            throw new RetailerSaleError('Retailer not found within authorized branch.');
        }
        return $row;
    }

    public function all(int $company, int $branch, int $actor): array
    {
        if (!$this->gateway->canManage($actor, $company, $branch)) {
            throw new RetailerSaleError('Retailer master access denied.');
        }
        return $this->gateway->list($company, $branch);
    }

    private static function limitedText(mixed $value, string $label, int $max, bool $required): ?string
    {
        if ($value === null || $value === '') {
            if ($required) throw new RetailerSaleError("{$label} is required.");
            return null;
        }
        if (!is_string($value)) throw new RetailerSaleError("{$label} must be text.");
        $value = trim($value);
        if ($value === '') {
            if ($required) throw new RetailerSaleError("{$label} is required.");
            return null;
        }
        if (strlen($value) > $max || preg_match('/[\x00-\x08\x0B\x0C\x0E-\x1F]/', $value)) {
            throw new RetailerSaleError("{$label} is too long or contains control characters.");
        }
        return $value;
    }
}