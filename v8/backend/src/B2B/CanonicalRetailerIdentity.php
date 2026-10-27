<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP8\B2B;

/**
 * Canonical shopkeeper identity is a classification of V7 eh7_parties.type=customer.
 * It is NOT a second customer master. All lookups are company/branch scoped.
 * A trusted caller supplies the actor and scope after V7 authentication.
 */
interface CanonicalRetailerIdentityReader
{
    public function canInspectRetailer(int $actorId, int $companyId, int $branchId): bool;
    /** A single joined eh8 retailer link + canonical eh7 customer party. */
    public function retailerParty(int $companyId, int $branchId, int $retailerId): ?array;
    /** Sum of still-open canonical V7 counter-sale receivables; must be exact decimal. */
    public function openCustomerReceivables(int $companyId, int $branchId, int $partyId): string;
}

/**
 * Read-only identity gate. Never enables posting, updates parties or creates a B2B invoice.
 * This gate rejects an existing V7 customer's unpaid invoices until resolved by an
 * authorized accountant. It must be re-evaluated FOR UPDATE by a future posting gateway.
 */
final class CanonicalRetailerIdentity
{
    public function __construct(private CanonicalRetailerIdentityReader $source) {}

    public function resolve(array $trusted): array
    {
        foreach (['company_id','branch_id','actor_id','retailer_id'] as $key) {
            if (!isset($trusted[$key]) || !is_int($trusted[$key]) || $trusted[$key] < 1) {
                throw new RetailerSaleError('Trusted retailer identity requires valid ' . $key . '.');
            }
        }
        $company = $trusted['company_id'];
        $branch = $trusted['branch_id'];
        $actor = $trusted['actor_id'];
        $retailer = $trusted['retailer_id'];
        if (!$this->source->canInspectRetailer($actor, $company, $branch)) {
            throw new RetailerSaleError('Retailer identity access denied for company or branch.');
        }
        $row = $this->source->retailerParty($company, $branch, $retailer);
        if ($row === null) throw new RetailerSaleError('Retailer is not linked to a canonical customer.');
        foreach (['retailer_id','party_id','company_id','branch_id'] as $key) {
            if (!isset($row[$key]) || !ctype_digit((string)$row[$key]) || (int)$row[$key] < 1) {
                throw new RetailerSaleError('Retailer mapping has an invalid canonical identifier.');
            }
        }
        if ((int)$row['retailer_id'] !== $retailer || (int)$row['company_id'] !== $company
            || (int)$row['branch_id'] !== $branch) {
            throw new RetailerSaleError('Retailer mapping crosses company or branch boundary.');
        }
        if (($row['link_status'] ?? '') !== 'active' || ($row['party_status'] ?? '') !== 'active'
            || ($row['party_type'] ?? '') !== 'customer') {
            throw new RetailerSaleError('Retailer link and canonical customer must both be active.');
        }
        if (!is_string($row['shop_name'] ?? null) || trim($row['shop_name']) === '') {
            throw new RetailerSaleError('Canonical shop name is missing.');
        }
        $party = (int)$row['party_id'];
        $open = $this->source->openCustomerReceivables($company, $branch, $party);
        if (Paise::parse($open) !== 0) {
            throw new RetailerSaleError('Existing customer credit must be settled before Cash/UPI-only retailer sale.');
        }
        return [
            'retailer_id'=>$retailer, 'canonical_party_id'=>$party,
            'company_id'=>$company, 'branch_id'=>$branch,
            'shop_name'=>trim($row['shop_name']), 'retailer_type'=>'retailer',
            'credit_allowed'=>false, 'outstanding_paise'=>0,
            'identity_validated'=>true, 'posting_allowed'=>false,
        ];
    }
}
