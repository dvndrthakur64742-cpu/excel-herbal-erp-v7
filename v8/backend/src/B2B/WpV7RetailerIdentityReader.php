<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP8\B2B;

/**
 * READ ONLY WordPress lookup. eh7_parties remains customer source of truth.
 * The eh8_retailer_party_links sidecar is merely a customer-type classification.
 * No REST route, write, migration, or financial posting is registered here.
 */
final class WpV7RetailerIdentityReader implements CanonicalRetailerIdentityReader
{
    private string $prefix;
    /** @param callable $authorize a trusted V7 Guard callback for actor/company/branch */
    public function __construct(private object $wpdb, private $authorize)
    {
        if (!is_callable($authorize)) {
            throw new RetailerSaleError('Retailer identity authorization callback required.');
        }
        $prefix = $wpdb->prefix ?? null;
        if (!is_string($prefix) || !preg_match('/^[A-Za-z0-9_]{1,60}$/D', $prefix)) {
            throw new RetailerSaleError('Unsafe WordPress prefix for retailer reader.');
        }
        $this->prefix = $prefix;
    }

    public function canInspectRetailer(int $actorId, int $companyId, int $branchId): bool
    {
        return ($this->authorize)($actorId, $companyId, $branchId) === true;
    }

    private function sql(string $template, array $params): string
    {
        $sql=$this->wpdb->prepare($template,...$params);
        if (!is_string($sql) || $sql === '') throw new RetailerSaleError('Retailer canonical query preparation failed.');
        return $sql;
    }

    private function assertReadSucceeded(): void
    {
        if (trim((string)($this->wpdb->last_error ?? '')) !== '') {
            throw new RetailerSaleError('Canonical retailer data unavailable; fail closed.');
        }
    }

    public function retailerParty(int $companyId, int $branchId, int $retailerId): ?array
    {
        $links=$this->prefix.'eh8_retailer_party_links';
        $parties=$this->prefix.'eh7_parties';
        $sql=$this->sql(
            "SELECT l.id AS retailer_id, l.company_id, l.branch_id, l.party_id, " .
            "l.status AS link_status, p.type AS party_type, p.status AS party_status, " .
            "p.name AS shop_name FROM {$links} l " .
            "INNER JOIN {$parties} p ON p.id=l.party_id AND p.company_id=l.company_id " .
            "AND p.branch_id=l.branch_id " .
            "WHERE l.company_id=%d AND l.branch_id=%d AND l.id=%d LIMIT 1",
            [$companyId,$branchId,$retailerId]
        );
        $row=$this->wpdb->get_row($sql,defined('ARRAY_A')?constant('ARRAY_A'):'ARRAY_A');
        $this->assertReadSucceeded();
        if ($row !== null && !is_array($row)) throw new RetailerSaleError('Malformed retailer identity database response.');
        return $row;
    }

    public function openCustomerReceivables(int $companyId, int $branchId, int $partyId): string
    {
        $sales=$this->prefix.'eh7_counter_sales';
        $sql=$this->sql(
            "SELECT COALESCE(SUM(outstanding_amount),0) FROM {$sales} " .
            "WHERE company_id=%d AND branch_id=%d AND customer_id=%d " .
            "AND status='posted' AND outstanding_amount>0",
            [$companyId,$branchId,$partyId]
        );
        $amount=$this->wpdb->get_var($sql);
        $this->assertReadSucceeded();
        if (!is_string($amount) && !is_int($amount)) {
            throw new RetailerSaleError('Customer receivable balance could not be validated.');
        }
        return (string)$amount;
    }
}
