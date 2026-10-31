<?php
namespace ExcelHerbal\ERP7\Security;

/**
 * Recommended least-privilege capability defaults by designation.
 *
 * These defaults are additive to explicit roles and remain subject to
 * employee capability overrides plus effective branch authority.
 */
final class DesignationDefaults {
    /** @return string[] */
    private static function baseEmployee(): array {
        return [
            Capabilities::ACCESS,
            Capabilities::ATT_SELF,
            Capabilities::FIELD_SELF,
            Capabilities::LEAVE_SELF,
            Capabilities::DAILY_SELF,
            Capabilities::PERFORMANCE_VIEW,
            Capabilities::COMM_VIEW,
        ];
    }

    /** @return string[] */
    public static function forCode(string $code): array {
        $code = self::normalise($code);
        $base = self::baseEmployee();
        $extra = match ($code) {
            'SYSADMIN', 'SYSTEM_ADMIN', 'ADMIN', 'ADMINISTRATOR' => self::all(),

            // Front-line team supervision: own work + assigned team operations.
            'ASM', 'ASSISTANT_SALES_MANAGER' => [
                Capabilities::EMP_VIEW,
                Capabilities::DELEGATION_MANAGE,
                Capabilities::ATT_MANAGE,
                Capabilities::LEAVE_MANAGE,
                Capabilities::DAILY_OTHERS,
                Capabilities::DAILY_APPROVE,
                Capabilities::SALES_VIEW,
                Capabilities::INVENTORY_VIEW,
                Capabilities::PERFORMANCE_VIEW,
                Capabilities::REPORTS_VIEW,
                Capabilities::COMM_VIEW,
            ],
            'SM', 'SALES_MANAGER' => [
                Capabilities::EMP_VIEW,
                Capabilities::DELEGATION_MANAGE,
                Capabilities::ATT_MANAGE,
                Capabilities::LEAVE_MANAGE,
                Capabilities::DAILY_OTHERS,
                Capabilities::DAILY_APPROVE,
                Capabilities::DAILY_REVIEW,
                Capabilities::SALES_VIEW,
                Capabilities::INVENTORY_VIEW,
                Capabilities::PURCHASE_VIEW,
                Capabilities::PERFORMANCE_VIEW,
                Capabilities::REPORTS_VIEW,
                Capabilities::COMM_VIEW,
            ],

            // Branch Manager: branch operations, approvals and branch closing.
            'BM', 'BRANCH_MANAGER' => [
                Capabilities::EMP_VIEW,
                Capabilities::HR_VIEW,
                Capabilities::HR_MANAGE,
                Capabilities::DELEGATION_MANAGE,
                Capabilities::ATT_MANAGE,
                Capabilities::LEAVE_MANAGE,
                Capabilities::DAILY_OTHERS,
                Capabilities::DAILY_APPROVE,
                Capabilities::DAILY_ISSUE,
                Capabilities::DAILY_REVIEW,
                Capabilities::PRODUCT_VIEW,
                Capabilities::SALES_VIEW,
                Capabilities::SALES_CREATE,
                Capabilities::RECEIPT_CREATE,
                Capabilities::INVENTORY_VIEW,
                Capabilities::TRANSFER_CREATE,
                Capabilities::TRANSFER_RECEIVE,
                Capabilities::TRANSFER_CANCEL,
                Capabilities::PURCHASE_VIEW,
                Capabilities::PURCHASE_CREATE,
                Capabilities::FINANCE_VIEW,
                Capabilities::EXPENSE_CREATE,
                Capabilities::EXPENSE_APPROVE,
                Capabilities::BRANCH_CLOSE,
                Capabilities::PERFORMANCE_VIEW,
                Capabilities::REPORTS_VIEW,
                Capabilities::COMM_VIEW,
                Capabilities::COMM_MANAGE,
            ],

            // Executive management: broad oversight, but no automatic system-admin power.
            'MD', 'MANAGING_DIRECTOR',
            'CM', 'CHAIRMAN', 'CHAIRMAN_MANAGING_DIRECTOR' => [
                Capabilities::EMP_VIEW,
                Capabilities::HR_VIEW,
                Capabilities::HR_MANAGE,
                Capabilities::HR_REVIEW,
                Capabilities::DELEGATION_MANAGE,
                Capabilities::BRANCH_VIEW,
                Capabilities::PRODUCT_VIEW,
                Capabilities::ATT_MANAGE,
                Capabilities::LEAVE_MANAGE,
                Capabilities::DAILY_OTHERS,
                Capabilities::DAILY_APPROVE,
                Capabilities::DAILY_REVIEW,
                Capabilities::SALES_VIEW,
                Capabilities::INVENTORY_VIEW,
                Capabilities::PURCHASE_VIEW,
                Capabilities::FINANCE_VIEW,
                Capabilities::ACCOUNTING_VIEW,
                Capabilities::PERFORMANCE_VIEW,
                Capabilities::REPORTS_VIEW,
                Capabilities::COMM_VIEW,
                Capabilities::AUDIT_VIEW,
            ],

            // Regional/inspection roles are intentionally monitoring-heavy.
            'RM', 'REGIONAL_MANAGER',
            'RC', 'REGIONAL_COORDINATOR',
            'AGM', 'ASSISTANT_GENERAL_MANAGER',
            'ZI', 'ZONAL_INSPECTOR' => [
                Capabilities::EMP_VIEW,
                Capabilities::HR_VIEW,
                Capabilities::HR_MANAGE,
                Capabilities::HR_REVIEW,
                Capabilities::DELEGATION_MANAGE,
                Capabilities::ATT_MANAGE,
                Capabilities::LEAVE_MANAGE,
                Capabilities::DAILY_OTHERS,
                Capabilities::DAILY_APPROVE,
                Capabilities::DAILY_REVIEW,
                Capabilities::PRODUCT_VIEW,
                Capabilities::SALES_VIEW,
                Capabilities::INVENTORY_VIEW,
                Capabilities::PURCHASE_VIEW,
                Capabilities::FINANCE_VIEW,
                Capabilities::ACCOUNTING_VIEW,
                Capabilities::PERFORMANCE_VIEW,
                Capabilities::REPORTS_VIEW,
                Capabilities::COMM_VIEW,
            ],

            default => [],
        };
        return array_values(array_unique(array_merge($base, $extra)));
    }

    /** @return array<string,string[]> */
    public static function profiles(): array {
        $codes = ['EMPLOYEE','ASM','SM','BM','RM','RC','AGM','ZI','CM','MD','SYSADMIN'];
        $out = [];
        foreach ($codes as $code) $out[$code] = self::forCode($code);
        return $out;
    }

    public static function requiresAccessManagement(string $code): bool {
        return in_array(self::normalise($code), [
            'SYSADMIN','SYSTEM_ADMIN','ADMIN','ADMINISTRATOR',
            'ZI','ZONAL_INSPECTOR',
            'CM','CHAIRMAN','CHAIRMAN_MANAGING_DIRECTOR',
            'MD','MANAGING_DIRECTOR',
        ], true);
    }

    /** @return string[] */
    public static function all(): array {
        return array_values(array_unique(array_values((new \ReflectionClass(Capabilities::class))->getConstants())));
    }

    private static function normalise(string $code): string {
        $code = strtoupper(trim($code));
        $code = preg_replace('/[^A-Z0-9]+/', '_', $code) ?: '';
        return trim($code, '_');
    }
}
