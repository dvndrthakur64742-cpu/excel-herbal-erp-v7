<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP8\B2B;

use Closure;
use DateTimeImmutable;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities,Guard};

/**
 * UAT-only GET adapter for the EXISTING read-only cross-source employee audit.
 * Not registered in WordPress, not invoked from Office, no financial writer.
 *
 * A future AUTHENTICATED UAT router resolves Actor on the SERVER. HTTP clients
 * cannot set company, user identity or permissions. Missing RBAC is fatal.
 */
final class V7FinanceReviewReadEndpointUat
{
    private static function positive(mixed $v,string $field):int
    {
        if((!is_string($v)&&!is_int($v))
           ||!preg_match('/^[1-9][0-9]{0,14}$/D',(string)$v))
            throw new RetailerSaleError('Invalid Finance evidence '.$field.'.');
        return (int)$v;
    }

    private static function day(mixed $v,string $field):string
    {
        if(!is_string($v)||!preg_match('/^\d{4}-\d{2}-\d{2}$/D',$v))
            throw new RetailerSaleError('Invalid Finance evidence '.$field.'.');
        $date=DateTimeImmutable::createFromFormat('!Y-m-d',$v);
        if(!$date||$date->format('Y-m-d')!==$v)
            throw new RetailerSaleError('Invalid Finance evidence '.$field.'.');
        return $v;
    }

    /**
     * Validates transport and role BEFORE any scoped SQL. Authority callback
     * must be independently resolved from server policy/employee hierarchy.
     * The result matches CashierEvidenceUatPage.fromResponse in Flutter.
     *
     * @param array<string,mixed> $query Only exactly documented GET fields.
     * @return array<string,mixed> original immutable-source page
     */
    public static function get(
        Actor $authenticatedActor,
        string $method,
        array $query,
        Closure $serverAuthority
    ):array {
        // This is a disposable V8 feature. Never enable through an Office
        // environment flag, user-request parameter, WordPress option or JWT.
        V7CanonicalPostingSinkUat::assertNonProductionEnvironment(Db::wpdb());
        if($method!=='GET' || array_diff(array_keys($query),
            ['branch_id','employee_id','from','to','page','page_size'])!==[])
            throw new RetailerSaleError('Read-only Finance evidence GET contract required.');
        $branch=self::positive($query['branch_id']??null,'branch');
        $employee=self::positive($query['employee_id']??null,'employee');
        $from=self::day($query['from']??null,'from');
        $to=self::day($query['to']??null,'to');
        $page=self::positive($query['page']??null,'page');
        $size=self::positive($query['page_size']??null,'page size');
        if($from>$to||$page!==1||$size!==25)
            throw new RetailerSaleError('Only bounded first-page Finance evidence is supported.');
        if($authenticatedActor->userId<1||$authenticatedActor->employeeId<1
           ||$authenticatedActor->companyId<1)
            throw new RetailerSaleError('Authenticated reviewer context missing.');
        Guard::branch($authenticatedActor,$branch,Capabilities::ACCOUNTING_VIEW);
        Guard::cap($authenticatedActor,Capabilities::EMP_VIEW);
        if($serverAuthority(
            'employee.cash.cross_source.view',
            $authenticatedActor->userId,
            $authenticatedActor->companyId,
            $branch,$employee
        )!==true) {
            throw new RetailerSaleError('Finance review target is outside reporting authority.');
        }
        $result=V7EmployeeCrossSourceCashAuditUat::inspect(
            $authenticatedActor,$branch,$employee,$from,$to,
            $serverAuthority,$size,0
        );
        // Preserve the original no-global-liability and no-bank-proof rules.
        if(($result['read_only']??false)!==true
           ||($result['source_keys_independent']??false)!==true
           ||!array_key_exists('combined_sale_total_paise',$result)
           ||$result['combined_sale_total_paise']!==null
           ||!array_key_exists('combined_employee_cash_outstanding_paise',$result)
           ||$result['combined_employee_cash_outstanding_paise']!==null
           ||($result['external_bank_deposit_verified']??true)!==false)
            throw new RetailerSaleError('Finance evidence response safety contract invalid.');
        return $result;
    }
}
