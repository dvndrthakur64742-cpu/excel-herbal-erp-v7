<?php
namespace ExcelHerbal\ERP7\Policy;

use ExcelHerbal\ERP7\Domain\DomainException;

/** Deterministic invariants shared by Daily Order, sales, and offline tests. */
final class FieldSalesRules
{
    public static function retailQuantity(float $issued, float $returned, float $wholesale): float
    {
        if (!is_finite($issued) || !is_finite($returned) || !is_finite($wholesale) ||
            $issued < 0 || $returned < 0 || $wholesale < 0 || $returned + $wholesale > $issued + .0001) {
            throw new DomainException('Issued quantity must equal returned + retail + wholesale.','evening_quantity_invalid',422);
        }
        return round(max(0.,$issued - $returned - $wholesale),3);
    }

    public static function requireFullPrepayment(float $invoice, float $confirmed): void
    {
        if (!is_finite($invoice) || !is_finite($confirmed) || $invoice < 0 || $confirmed < 0 ||
            abs(round($invoice,2) - round($confirmed,2)) > .005) {
            throw new DomainException('Full Cash/UPI payment required before invoice. Credit and partial payment are disabled.','full_prepayment_required',409);
        }
    }

    public static function requireExactCollection(float $expected, float $cash, float $upi): void
    {
        if (!is_finite($expected) || !is_finite($cash) || !is_finite($upi) ||
            $expected < 0 || $cash < 0 || $upi < 0 || abs(round($cash+$upi,2)-round($expected,2))>.005) {
            throw new DomainException('Cash + UPI must equal expected amount.','payment_mismatch',409);
        }
    }
}
