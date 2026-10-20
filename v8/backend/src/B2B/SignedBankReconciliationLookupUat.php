<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP8\B2B;

require_once __DIR__.'/AuthenticatedUpiSettlementSource.php';

use Closure;
use DateTimeImmutable;
use DateTimeZone;
use PDO;

/**
 * UAT ONLY: read a backend-authenticated, HMAC-sealed bank-reconciliation feed.
 * This is NOT a bank webhook verifier, bank API client, or a signing endpoint.
 * Only the independently trusted reconciliation importer can have signing keys.
 * Keep bank/importer credentials out of the ERP and out of browser/HTTP input.
 */
final class SignedBankReconciliationLookupUat implements AuthenticatedUpiSettlementSource
{
    private const FIELDS = [
        'company_id','branch_id','lookup_key','status','currency','amount_paise',
        'merchant_account','merchant_order_id','transaction_id','observed_at','key_id'
    ];

    /** @param Closure(string):(?string) $secretForKeyId A server-owned key resolver. */
    public function __construct(private PDO $db, private Closure $secretForKeyId)
    {
        if ($db->getAttribute(PDO::ATTR_DRIVER_NAME) !== 'mysql'
            || $db->query('SELECT DATABASE()')->fetchColumn() !== 'v8_test') {
            throw new RetailerSaleError('Signed bank-reconciliation UAT only runs on isolated v8_test MariaDB.');
        }
        $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    }

    /** Canonical serialization is fixed and testable; NEVER serialize arbitrary fields. */
    public static function digest(array $row, string $secret): string
    {
        if (strlen($secret) < 32) throw new RetailerSaleError('A server-owned 256-bit settlement signing key is required.');
        $canonical = [];
        foreach (self::FIELDS as $name) {
            if (!array_key_exists($name, $row)) throw new RetailerSaleError('Incomplete signed settlement field: '.$name);
            $canonical[$name] = (string)$row[$name];
        }
        return hash_hmac('sha256', json_encode($canonical, JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR), $secret);
    }

    /** Only returns a settled payment if the backend-origin proof is intact and current. */
    public function __invoke(string $lookupKey): ?array
    {
        return $this->verifySettlement($lookupKey);
    }

    public function verifySettlement(string $lookupKey): ?array
    {
        if (!preg_match('/^[A-Za-z0-9][A-Za-z0-9._:\/-]{7,127}$/D', $lookupKey)) return null;
        if ($this->db->inTransaction() === false
            || $this->db->query('SELECT DATABASE()')->fetchColumn() !== 'v8_test') return null;
        // Caller must lock its issued intent first; never verify in a switched schema.
        $q = $this->db->prepare('SELECT * FROM v8_b2b_signed_bank_reconciliation_uat WHERE lookup_key=? FOR UPDATE');
        $q->execute([$lookupKey]);
        $row = $q->fetch(PDO::FETCH_ASSOC);
        if ($row === false) return null;
        if (($row['status'] ?? '') !== 'settled' || ($row['currency'] ?? '') !== 'INR') return null;
        foreach (['company_id','branch_id','amount_paise'] as $number) {
            $v = (string)($row[$number] ?? '');
            if (!ctype_digit($v) || strlen($v) > 15 || (int)$v < 1) return null;
        }
        foreach (['merchant_account','merchant_order_id','transaction_id'] as $key) {
            if (!is_string($row[$key] ?? null) || trim($row[$key]) === '' || strlen($row[$key]) > 128) return null;
        }
        if (!preg_match('/^[A-Za-z0-9][A-Za-z0-9._:\/-]{7,127}$/D', (string)$row['transaction_id'])) return null;
        $at = $row['observed_at'] ?? '';
        if (!is_string($at) || !preg_match('/^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$/D', $at)) return null;
        $instant = DateTimeImmutable::createFromFormat('!Y-m-d H:i:s', $at, new DateTimeZone('UTC'));
        if ($instant === false || $instant->format('Y-m-d H:i:s') !== $at) return null;
        $age = time() - $instant->getTimestamp();
        if ($age < -300 || $age > 48 * 3600) return null; // fail closed on future or stale evidence
        $keyId = $row['key_id'] ?? null;
        if (!is_string($keyId) || !preg_match('/^[a-zA-Z0-9_-]{3,64}$/D', $keyId)) return null;
        $secret = ($this->secretForKeyId)($keyId);
        if (!is_string($secret) || strlen($secret) < 32) return null;
        $signature = $row['signature'] ?? null;
        if (!is_string($signature) || !preg_match('/^[0-9a-f]{64}$/D', $signature)) return null;
        if (!hash_equals(self::digest($row, $secret), $signature)) return null;
        return [
            'company_id'=>(int)$row['company_id'],'branch_id'=>(int)$row['branch_id'],
            'status' => 'settled','currency' => 'INR','amount_paise' => (int)$row['amount_paise'],
            'merchant_account' => $row['merchant_account'],
            'merchant_order_id' => $row['merchant_order_id'],
            'transaction_id' => $row['transaction_id'],
        ];
    }
}
