<?php
namespace ExcelHerbal\ERP7\Payroll;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Finance\AccountingService;
use ExcelHerbal\ERP7\Finance\BranchDayGuard;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;

final class PayrollPerformanceService
{
    public static function runs(Actor $a, int $branch): array
    {
        self::guardPayrollBranch($a, $branch);
        $db = Db::wpdb();
        return (array) $db->get_results($db->prepare(
            "SELECT r.*,
                (SELECT COALESCE(SUM(i.net_salary),0) FROM ".Db::table('payroll_items')." i WHERE i.payroll_run_id=r.id) net_total,
                (SELECT COUNT(*) FROM ".Db::table('payroll_items')." i WHERE i.payroll_run_id=r.id) employee_count
             FROM ".Db::table('payroll_runs')." r
             WHERE r.company_id=%d AND r.branch_id=%d
             ORDER BY r.period_end DESC,r.id DESC LIMIT 100",
            $a->companyId,
            $branch
        ), ARRAY_A);
    }

    public static function detail(Actor $a, int $id): array
    {
        $db = Db::wpdb();
        $run = $db->get_row($db->prepare(
            "SELECT r.*,
                (SELECT COALESCE(SUM(i.net_salary),0) FROM ".Db::table('payroll_items')." i WHERE i.payroll_run_id=r.id) net_total
             FROM ".Db::table('payroll_runs')." r
             WHERE r.id=%d AND r.company_id=%d",
            $id,
            $a->companyId
        ), ARRAY_A);
        if (!$run) {
            throw new DomainException('Payroll not found.', 'payroll_not_found', 404);
        }
        self::guardPayrollBranch($a, (int) $run['branch_id']);
        $items = (array) $db->get_results($db->prepare(
            "SELECT i.*,e.employee_code,e.full_name,e.designation_code
             FROM ".Db::table('payroll_items')." i
             JOIN ".Db::table('employees')." e ON e.id=i.employee_id
             WHERE i.payroll_run_id=%d
             ORDER BY e.full_name,e.id",
            $id
        ), ARRAY_A);
        return ['run' => $run, 'items' => $items];
    }

    public static function targets(Actor $a, int $branch): array
    {
        Guard::branch($a, $branch, $a->can(Capabilities::PERFORMANCE_MANAGE) ? Capabilities::PERFORMANCE_MANAGE : Capabilities::PERFORMANCE_VIEW);
        $db = Db::wpdb();
        return (array) $db->get_results($db->prepare(
            "SELECT t.*,e.full_name employee_name FROM ".Db::table('performance_targets')." t
             JOIN ".Db::table('employees')." e ON e.id=t.employee_id
             WHERE t.company_id=%d AND t.branch_id=%d
             ORDER BY t.period_end DESC,t.id DESC LIMIT 200",
            $a->companyId,
            $branch
        ), ARRAY_A);
    }

    public static function generate(Actor $a, int $branch, string $from, string $to): array
    {
        Guard::branch($a, $branch, Capabilities::PAYROLL_GENERATE);
        if ($from === '' || $to === '' || $from > $to) {
            throw new DomainException('Invalid payroll period.', 'payroll_period_invalid', 422);
        }

        return Transaction::run(function () use ($a, $branch, $from, $to) {
            $db = Db::wpdb();
            $runs = Db::table('payroll_runs');
            if ((int) $db->get_var($db->prepare(
                "SELECT COUNT(*) FROM {$runs} WHERE company_id=%d AND branch_id=%d AND period_start=%s AND period_end=%s",
                $a->companyId,
                $branch,
                $from,
                $to
            ))) {
                throw new DomainException('Payroll already exists.', 'payroll_duplicate', 409);
            }

            Db::mustInsert($db,$runs, [
                'company_id' => $a->companyId,
                'branch_id' => $branch,
                'period_start' => $from,
                'period_end' => $to,
                'status' => 'draft',
                'created_by' => $a->employeeId,
                'created_at' => Db::now(),
            ]);
            $run = (int) $db->insert_id;
            if ($run < 1) {
                throw new DomainException('Unable to create payroll run.', 'payroll_create_failed', 500);
            }

            $employees = (array) $db->get_results($db->prepare(
                "SELECT DISTINCT e.*
                 FROM ".Db::table('employees')." e
                 WHERE e.company_id=%d
                   AND (e.joining_date IS NULL OR e.joining_date<=%s)
                   AND (e.separation_date IS NULL OR e.separation_date>=%s)
                   AND (
                       EXISTS (
                           SELECT 1 FROM ".Db::table('employee_branch_history')." h
                           WHERE h.company_id=e.company_id AND h.employee_id=e.id AND h.branch_id=%d
                             AND h.effective_from<=%s AND (h.effective_to IS NULL OR h.effective_to>=%s)
                       )
                       OR (
                           NOT EXISTS (SELECT 1 FROM ".Db::table('employee_branch_history')." hx WHERE hx.company_id=e.company_id AND hx.employee_id=e.id)
                           AND e.assigned_branch_id=%d
                       )
                   )
                 ORDER BY e.id",
                $a->companyId,
                $to,
                $from,
                $branch,
                $to,
                $from,
                $branch
            ), ARRAY_A);

            foreach ($employees as $e) {
                [$working, $paid] = self::dayCounts(
                    $a->companyId,
                    $branch,
                    (int) $e['id'],
                    $from,
                    $to,
                    $e['joining_date'] ?? null,
                    $e['separation_date'] ?? null
                );
                $fixed = max(0, (float) $e['monthly_salary']);
                $attendanceSalary = $working > 0 ? round($fixed * min($paid, $working) / $working, 2) : 0.0;
                $fund = round((float) $db->get_var($db->prepare(
                    "SELECT COALESCE(SUM(salary_fund),0) FROM ".Db::table('performance_entries')."
                     WHERE company_id=%d AND branch_id=%d AND employee_id=%d AND business_date BETWEEN %s AND %s",
                    $a->companyId,
                    $branch,
                    (int) $e['id'],
                    $from,
                    $to
                )), 2);
                $net = round($attendanceSalary + $fund, 2);
                Db::mustInsert($db,Db::table('payroll_items'), [
                    'payroll_run_id' => $run,
                    'employee_id' => (int) $e['id'],
                    'working_days' => $working,
                    'paid_days' => $paid,
                    'fixed_salary' => $fixed,
                    'attendance_salary' => $attendanceSalary,
                    'salary_fund_earning' => $fund,
                    'bonus' => 0,
                    'allowances' => 0,
                    'deductions' => 0,
                    'net_salary' => $net,
                ]);
            }

            Audit::add($a, 'payroll.generate', 'payroll_run', $run, [
                'branch_id' => $branch,
                'period_start' => $from,
                'period_end' => $to,
                'employee_count' => count($employees),
            ]);
            return ['id' => $run, 'status' => 'draft', 'employee_count' => count($employees)];
        });
    }

    public static function updateItem(Actor $a, int $runId, int $itemId, float $bonus, float $allowances, float $deductions): array
    {
        if ($bonus < 0 || $allowances < 0 || $deductions < 0) {
            throw new DomainException('Payroll adjustments cannot be negative.', 'payroll_adjustment_invalid', 422);
        }
        return Transaction::run(function () use ($a, $runId, $itemId, $bonus, $allowances, $deductions) {
            $db = Db::wpdb();
            $run = $db->get_row($db->prepare(
                "SELECT * FROM ".Db::table('payroll_runs')." WHERE id=%d AND company_id=%d FOR UPDATE",
                $runId,
                $a->companyId
            ), ARRAY_A);
            if (!$run) {
                throw new DomainException('Payroll not found.', 'payroll_not_found', 404);
            }
            Guard::branch($a, (int) $run['branch_id'], Capabilities::PAYROLL_GENERATE);
            if ($run['status'] !== 'draft') {
                throw new DomainException('Only draft payroll can be reviewed.', 'payroll_state_invalid', 409);
            }
            $item = $db->get_row($db->prepare(
                "SELECT * FROM ".Db::table('payroll_items')." WHERE id=%d AND payroll_run_id=%d FOR UPDATE",
                $itemId,
                $runId
            ), ARRAY_A);
            if (!$item) {
                throw new DomainException('Payroll item not found.', 'payroll_item_not_found', 404);
            }
            $net = round(max(0, (float) $item['attendance_salary'] + (float) $item['salary_fund_earning'] + $bonus + $allowances - $deductions), 2);
            $db->update(Db::table('payroll_items'), [
                'bonus' => round($bonus, 2),
                'allowances' => round($allowances, 2),
                'deductions' => round($deductions, 2),
                'net_salary' => $net,
            ], ['id' => $itemId]);
            Audit::add($a, 'payroll.item_review', 'payroll_item', $itemId, [
                'payroll_run_id' => $runId,
                'branch_id' => (int) $run['branch_id'],
                'bonus' => round($bonus, 2),
                'allowances' => round($allowances, 2),
                'deductions' => round($deductions, 2),
                'net_salary' => $net,
            ]);
            return ['id' => $itemId, 'payroll_run_id' => $runId, 'net_salary' => $net];
        });
    }

    public static function approvePayroll(Actor $a, int $id): array
    {
        return Transaction::run(function () use ($a, $id) {
            $db = Db::wpdb();
            $table = Db::table('payroll_runs');
            $run = $db->get_row($db->prepare(
                "SELECT * FROM {$table} WHERE id=%d AND company_id=%d FOR UPDATE",
                $id,
                $a->companyId
            ), ARRAY_A);
            if (!$run) {
                throw new DomainException('Payroll not found.', 'payroll_not_found', 404);
            }
            Guard::branch($a, (int) $run['branch_id'], Capabilities::PAYROLL_APPROVE);
            if ($run['status'] !== 'draft') {
                throw new DomainException('Payroll not draft.', 'payroll_state_invalid', 409);
            }
            if ((int) $run['created_by'] === $a->employeeId) {
                throw new DomainException('Maker cannot approve own payroll.', 'maker_checker_required', 409);
            }
            BranchDayGuard::assertOpen($a, (int) $run['branch_id'], (string) $run['period_end']);
            $total = round((float) $db->get_var($db->prepare(
                "SELECT COALESCE(SUM(net_salary),0) FROM ".Db::table('payroll_items')." WHERE payroll_run_id=%d",
                $id
            )), 2);
            $journal = null;
            if ($total > 0) {
                $expense = AccountingService::accountByCode($a, 'PAYROLL_EXPENSE');
                $payable = AccountingService::accountByCode($a, 'PAYROLL_PAYABLE');
                $journal = AccountingService::post($a, (int) $run['branch_id'], 'payroll', $id, $run['period_end'].' 12:00:00', [
                    ['account_id' => (int) $expense['id'], 'debit' => $total],
                    ['account_id' => (int) $payable['id'], 'credit' => $total],
                ], 'Payroll approval');
            }
            $db->update($table, [
                'status' => 'approved',
                'approved_by' => $a->employeeId,
                'journal_entry_id' => $journal,
                'approved_at' => Db::now(),
            ], ['id' => $id]);
            Audit::add($a, 'payroll.approve', 'payroll_run', $id, [
                'branch_id' => (int) $run['branch_id'],
                'net_total' => $total,
            ]);
            return ['id' => $id, 'status' => 'approved', 'net_total' => $total, 'journal_entry_id' => $journal];
        });
    }

    public static function payPayroll(Actor $a, int $id, int $paymentAccountId, string $paymentDate): array
    {
        $paymentDate = trim($paymentDate);
        if (!preg_match('/^\\d{4}-\\d{2}-\\d{2}$/', $paymentDate)) {
            throw new DomainException('Valid payment date is required.', 'payment_date_invalid', 422);
        }
        return Transaction::run(function () use ($a, $id, $paymentAccountId, $paymentDate) {
            $db = Db::wpdb();
            $table = Db::table('payroll_runs');
            $run = $db->get_row($db->prepare(
                "SELECT * FROM {$table} WHERE id=%d AND company_id=%d FOR UPDATE",
                $id,
                $a->companyId
            ), ARRAY_A);
            if (!$run) {
                throw new DomainException('Payroll not found.', 'payroll_not_found', 404);
            }
            Guard::branch($a, (int) $run['branch_id'], Capabilities::PAYROLL_PAY);
            if ($run['status'] !== 'approved') {
                throw new DomainException('Only approved payroll can be paid.', 'payroll_state_invalid', 409);
            }
            BranchDayGuard::assertOpen($a, (int) $run['branch_id'], $paymentDate);
            $payment = AccountingService::paymentAccount($a, $paymentAccountId);
            $total = round((float) $db->get_var($db->prepare(
                "SELECT COALESCE(SUM(net_salary),0) FROM ".Db::table('payroll_items')." WHERE payroll_run_id=%d",
                $id
            )), 2);
            $journal = null;
            if ($total > 0) {
                $payable = AccountingService::accountByCode($a, 'PAYROLL_PAYABLE');
                $journal = AccountingService::post($a, (int) $run['branch_id'], 'payroll_payment', $id, $paymentDate.' 12:00:00', [
                    ['account_id' => (int) $payable['id'], 'debit' => $total],
                    ['account_id' => (int) $payment['id'], 'credit' => $total],
                ], 'Payroll payment');
            }
            $db->update($table, [
                'status' => 'paid',
                'payment_account_id' => $paymentAccountId,
                'payment_journal_entry_id' => $journal,
                'paid_by' => $a->employeeId,
                'paid_at' => Db::now(),
                'payment_date' => $paymentDate,
            ], ['id' => $id]);
            Audit::add($a, 'payroll.pay', 'payroll_run', $id, [
                'branch_id' => (int) $run['branch_id'],
                'net_total' => $total,
                'payment_account_id' => $paymentAccountId,
                'payment_date' => $paymentDate,
            ]);
            return ['id' => $id, 'status' => 'paid', 'net_total' => $total, 'payment_journal_entry_id' => $journal];
        });
    }

    public static function summary(Actor $a, int $branch, string $from, string $to, ?int $employee): array
    {
        Guard::branch($a, $branch, Capabilities::PERFORMANCE_VIEW);
        $db = Db::wpdb();
        $where = '';
        $args = [$a->companyId, $branch, $from, $to];
        if ($employee !== null) {
            $valid = (int) $db->get_var($db->prepare(
                "SELECT COUNT(*) FROM ".Db::table('employees')." WHERE id=%d AND company_id=%d",
                $employee,
                $a->companyId
            ));
            if (!$valid) {
                throw new DomainException('Employee not found in company.', 'employee_invalid', 422);
            }
            $where = ' AND pe.employee_id=%d';
            $args[] = $employee;
        }
        return (array) $db->get_results($db->prepare(
            "SELECT pe.employee_id,e.full_name,COALESCE(SUM(pe.points),0) points,COALESCE(SUM(pe.salary_fund),0) salary_fund
             FROM ".Db::table('performance_entries')." pe
             JOIN ".Db::table('employees')." e ON e.id=pe.employee_id
             WHERE pe.company_id=%d AND pe.branch_id=%d AND pe.business_date BETWEEN %s AND %s{$where}
             GROUP BY pe.employee_id,e.full_name ORDER BY points DESC",
            ...$args
        ), ARRAY_A);
    }

    public static function target(Actor $a, int $branch, int $employee, string $from, string $to, float $points): array
    {
        Guard::branch($a, $branch, Capabilities::PERFORMANCE_MANAGE);
        if ($from > $to || $points < 0) {
            throw new DomainException('Invalid target.');
        }
        $db = Db::wpdb();
        $valid = (int) $db->get_var($db->prepare(
            "SELECT COUNT(*) FROM ".Db::table('employees')." WHERE id=%d AND company_id=%d AND assigned_branch_id=%d AND status='active'",
            $employee,
            $a->companyId,
            $branch
        ));
        if (!$valid) {
            throw new DomainException('Active employee not found in selected branch.', 'employee_branch_mismatch', 422);
        }
        Db::mustInsert($db,Db::table('performance_targets'), [
            'company_id' => $a->companyId,
            'branch_id' => $branch,
            'employee_id' => $employee,
            'period_start' => $from,
            'period_end' => $to,
            'target_points' => $points,
            'status' => 'draft',
            'created_by' => $a->employeeId,
            'created_at' => Db::now(),
        ]);
        $id = (int) $db->insert_id;
        Audit::add($a, 'performance_target.create', 'performance_target', $id, ['branch_id' => $branch, 'employee_id' => $employee]);
        return ['id' => $id, 'status' => 'draft'];
    }

    public static function approveTarget(Actor $a, int $id): array
    {
        Guard::cap($a, Capabilities::PERFORMANCE_MANAGE);
        $db = Db::wpdb();
        $table = Db::table('performance_targets');
        $row = $db->get_row($db->prepare(
            "SELECT * FROM {$table} WHERE id=%d AND company_id=%d",
            $id,
            $a->companyId
        ), ARRAY_A);
        if (!$row) {
            throw new DomainException('Target not found.', 'target_not_found', 404);
        }
        Guard::branch($a, (int) $row['branch_id'], Capabilities::PERFORMANCE_MANAGE);
        if ($row['status'] !== 'draft') {
            throw new DomainException('Only draft target can be approved.', 'target_state_invalid', 409);
        }
        if ((int) $row['created_by'] === $a->employeeId) {
            throw new DomainException('Maker cannot approve own target.', 'maker_checker_required', 409);
        }
        $db->update($table, ['status' => 'approved', 'approved_by' => $a->employeeId], ['id' => $id]);
        Audit::add($a, 'performance_target.approve', 'performance_target', $id, ['branch_id' => (int) $row['branch_id']]);
        return ['id' => $id, 'status' => 'approved'];
    }

    /** @return array{0:int,1:int} */
    private static function dayCounts(int $company, int $branch, int $employee, string $from, string $to, ?string $joining, ?string $separation): array
    {
        $start = max(strtotime($from), $joining ? strtotime($joining) : strtotime($from));
        $end = min(strtotime($to), $separation ? strtotime($separation) : strtotime($to));
        if ($end < $start) {
            return [0, 0];
        }
        $db = Db::wpdb();
        $settings = $db->get_var($db->prepare(
            "SELECT setting_value FROM ".Db::table('settings')." WHERE company_id=%d AND setting_key='weekly_off_iso_days'",
            $company
        ));
        $weeklyOff = [7];
        if (is_string($settings) && trim($settings) !== '') {
            $decoded = json_decode($settings, true);
            if (is_array($decoded)) {
                $candidate = array_values(array_unique(array_filter(array_map('intval', $decoded), fn($n) => $n >= 1 && $n <= 7)));
                if ($candidate) {
                    $weeklyOff = $candidate;
                }
            }
        }

        $holidays = array_flip(array_map('strval', (array) $db->get_col($db->prepare(
            "SELECT holiday_date FROM ".Db::table('holidays')."
             WHERE company_id=%d AND active=1 AND holiday_date BETWEEN %s AND %s AND (branch_id IS NULL OR branch_id=%d)",
            $company,
            date('Y-m-d', $start),
            date('Y-m-d', $end),
            $branch
        ))));
        $present = array_flip(array_map('strval', (array) $db->get_col($db->prepare(
            "SELECT business_date FROM ".Db::table('attendance')."
             WHERE company_id=%d AND branch_id=%d AND employee_id=%d AND business_date BETWEEN %s AND %s AND status='present'",
            $company,
            $branch,
            $employee,
            date('Y-m-d', $start),
            date('Y-m-d', $end)
        ))));
        $leaveRows = (array) $db->get_results($db->prepare(
            "SELECT date_from,date_to FROM ".Db::table('leave_requests')."
             WHERE company_id=%d AND employee_id=%d AND status='approved' AND NOT(date_to<%s OR date_from>%s)",
            $company,
            $employee,
            date('Y-m-d', $start),
            date('Y-m-d', $end)
        ), ARRAY_A);
        $history = (array) $db->get_results($db->prepare(
            "SELECT branch_id,effective_from,effective_to FROM ".Db::table('employee_branch_history')."
             WHERE company_id=%d AND employee_id=%d AND effective_from<=%s AND (effective_to IS NULL OR effective_to>=%s)
             ORDER BY effective_from,id",
            $company,
            $employee,
            date('Y-m-d', $end),
            date('Y-m-d', $start)
        ), ARRAY_A);
        $currentBranch = (int) $db->get_var($db->prepare(
            "SELECT assigned_branch_id FROM ".Db::table('employees')." WHERE company_id=%d AND id=%d",
            $company,
            $employee
        ));

        $working = 0;
        $paid = 0;
        for ($ts = $start; $ts <= $end; $ts += 86400) {
            $date = date('Y-m-d', $ts);
            $onBranch = !$history ? $currentBranch === $branch : false;
            foreach ($history as $h) {
                if ((int) $h['branch_id'] === $branch && $date >= $h['effective_from'] && ($h['effective_to'] === null || $date <= $h['effective_to'])) {
                    $onBranch = true;
                    break;
                }
            }
            if (!$onBranch) {
                continue;
            }
            $iso = (int) date('N', $ts);
            if (in_array($iso, $weeklyOff, true) || isset($holidays[$date])) {
                continue;
            }
            $working++;
            $onLeave = false;
            foreach ($leaveRows as $leave) {
                if ($date >= $leave['date_from'] && $date <= $leave['date_to']) {
                    $onLeave = true;
                    break;
                }
            }
            if (isset($present[$date]) || $onLeave) {
                $paid++;
            }
        }
        return [$working, $paid];
    }

    private static function guardPayrollBranch(Actor $a, int $branch): void
    {
        if ($a->can(Capabilities::PAYROLL_PAY)) {
            Guard::branch($a, $branch, Capabilities::PAYROLL_PAY);
            return;
        }
        if ($a->can(Capabilities::PAYROLL_APPROVE)) {
            Guard::branch($a, $branch, Capabilities::PAYROLL_APPROVE);
            return;
        }
        Guard::branch($a, $branch, Capabilities::PAYROLL_GENERATE);
    }
}
