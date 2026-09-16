<?php
namespace ExcelHerbal\ERP7\Policy;
final class BusinessPolicy {
    public const BATCH_MODE = 'optional';
    public const OWNER_DECISION_REQUIRED = [
        'supplier_return', 'treasury_transfer', 'supplier_advance',
        'employee_advance_loan', 'bad_debt_writeoff',
        'half_day_late_overtime', 'direct_nonstock_supplier_invoice',
    ];
    public static function enabled(string $feature): bool {
        return !in_array($feature, self::OWNER_DECISION_REQUIRED, true);
    }
}
