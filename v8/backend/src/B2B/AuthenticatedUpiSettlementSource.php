<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP8\B2B;

/**
 * Provider-independent, server-side UPI settlement VERIFICATION read contract.
 *
 * Implementors MUST verify authenticity against an independently trusted bank/PSP
 * reconciliation source and return null unless settlement is final. A UTR,
 * screenshot, browser callback, or a status string is not authentication.
 * Return integer company/branch IDs and paise, with original merchant order,
 * merchant account, transaction reference, status and INR currency.
 *
 * Only the signed internal feed implements this today, on disposable v8_test.
 * Production requires an independently authenticated provider importer and
 * explicit owner/Accounts approval. Never expose this through the buyer API.
 */
interface AuthenticatedUpiSettlementSource
{
    public function verifySettlement(string $lookupKey): ?array;
}
