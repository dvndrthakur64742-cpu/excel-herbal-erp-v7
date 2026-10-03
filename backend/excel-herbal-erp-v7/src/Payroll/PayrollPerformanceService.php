<?php
namespace ExcelHerbal\ERP7\Payroll;

use ExcelHerbal\ERP7\Core\Input;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Finance\AccountingService;
use ExcelHerbal\ERP7\Finance\BranchDayGuard;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;
use ExcelHerbal\ERP7\Security\HierarchyScope;

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
        Guard::branchAny($a, $branch, [Capabilities::PERFORMANCE_VIEW,Capabilities::PERFORMANCE_MANAGE]);
        $db = Db::wpdb();
        $peerView = self::canViewPeerPerformance($a);
        $args = [$a->companyId, $branch];
        if ($peerView) {
            $visible = HierarchyScope::visibleEmployeeIds($a, $branch);
            if (!$visible) return [];
            $where = ' AND t.employee_id IN ('.implode(',', array_fill(0, count($visible), '%d')).')';
            $args = array_merge($args, $visible);
        } else {
            $where = ' AND t.employee_id=%d';
            $args[] = $a->employeeId;
        }
        return (array) $db->get_results($db->prepare(
            "SELECT t.*,e.full_name employee_name FROM ".Db::table('performance_targets')." t
             JOIN ".Db::table('employees')." e ON e.id=t.employee_id
             WHERE t.company_id=%d AND t.branch_id=%d{$where}
             ORDER BY t.period_end DESC,t.id DESC LIMIT 200",
            ...$args
        ), ARRAY_A);
    }

    public static function targetEmployees(Actor $a, int $branch): array
    {
        Guard::branch($a, $branch, Capabilities::PERFORMANCE_MANAGE);
        $visible = HierarchyScope::visibleEmployeeIds($a, $branch);
        if (!$visible) return [];
        $placeholders = implode(',', array_fill(0, count($visible), '%d'));
        $args = array_merge([$a->companyId, $branch], $visible);
        return (array) Db::wpdb()->get_results(Db::wpdb()->prepare(
            "SELECT id,employee_code,full_name,designation_code
             FROM ".Db::table('employees')."
             WHERE company_id=%d AND assigned_branch_id=%d AND status='active'
               AND id IN ({$placeholders})
             ORDER BY full_name,id",
            ...$args
        ), ARRAY_A);
    }

    public static function generate(Actor $a, int $branch, string $from, string $to): array
    {
        Guard::branch($a, $branch, Capabilities::PAYROLL_GENERATE);
        [$from,$to] = Input::dateRange($from,$to,'Payroll period');

        return Transaction::run(function () use ($a, $branch, $from, $to) {
            $db = Db::wpdb();
            SalaryService::lockCompany($a->companyId);
            $runs = Db::table('payroll_runs');
            $items = Db::table('payroll_items');
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
                $a->companyId,$to,$from,$branch,$to,$from,$branch
            ), ARRAY_A);
            if (!$employees) {
                throw new DomainException('No employees are eligible for this payroll period.', 'payroll_no_employees', 422);
            }
            if(substr($from,0,7)!==substr($to,0,7))throw new DomainException('Payroll must stay within one calendar month.','payroll_period_invalid',422);
            $overlap=$db->get_var($db->prepare("SELECT id FROM {$runs} WHERE company_id=%d AND branch_id=%d AND period_start<=%s AND period_end>=%s AND NOT(period_start=%s AND period_end=%s) LIMIT 1 FOR UPDATE",$a->companyId,$branch,$to,$from,$from,$to));
            if($overlap)throw new DomainException('An overlapping payroll period already exists for this branch.','payroll_period_overlap',409);

            $existing=$db->get_row($db->prepare(
                "SELECT * FROM {$runs} WHERE company_id=%d AND branch_id=%d AND period_start=%s AND period_end=%s FOR UPDATE",
                $a->companyId,$branch,$from,$to
            ),ARRAY_A);
            $rebuilt=false;
            if($existing){
                if((string)$existing['status']!=='draft')throw new DomainException('Payroll already exists.','payroll_duplicate',409);
                $stats=$db->get_row($db->prepare(
                    "SELECT COUNT(*) item_count,COALESCE(SUM(fixed_salary),0) fixed_total,COALESCE(SUM(net_salary),0) net_total,COALESCE(SUM(bonus+allowances+deductions),0) adjustment_total FROM {$items} WHERE payroll_run_id=%d",
                    (int)$existing['id']
                ),ARRAY_A)?:[];
                $rebuildable=(int)($stats['item_count']??0)===0||(
                    abs((float)($stats['fixed_total']??0))<=0.005&&abs((float)($stats['net_total']??0))<=0.005&&abs((float)($stats['adjustment_total']??0))<=0.005
                );
                if(!$rebuildable)throw new DomainException('Payroll already exists.','payroll_duplicate',409);
                $existingItems=(array)$db->get_results($db->prepare("SELECT id,employee_id FROM {$items} WHERE payroll_run_id=%d ORDER BY id",(int)$existing['id']),ARRAY_A);
                $eligibleIds=array_fill_keys(array_map(static fn($e)=>(int)$e['id'],$employees),true);
                foreach($existingItems as$existingItem){if(!isset($eligibleIds[(int)$existingItem['employee_id']]))throw new DomainException('Legacy zero payroll draft employee scope has changed; manual review is required.','payroll_legacy_draft_scope_changed',409);}
                $run=(int)$existing['id'];$rebuilt=true;
            }else{
                Db::mustInsert($db,$runs, [
                    'company_id' => $a->companyId,'branch_id' => $branch,'period_start' => $from,'period_end' => $to,
                    'calculation_version'=>'7.3.5','status' => 'draft','created_by' => $a->employeeId,'created_at' => Db::now(),
                ]);
                $run = (int) $db->insert_id;
                if ($run < 1) throw new DomainException('Unable to create payroll run.', 'payroll_create_failed', 500);
            }

            $netTotal=0.0;
            foreach ($employees as $e) {
                $calculation = self::dayCounts($a->companyId,$branch,(int)$e['id'],$from,$to,$e['joining_date']??null,$e['separation_date']??null);
                $fixed = round((float)$calculation['fixed_salary'],2);
                $working=$calculation['working_days'];$paid=$calculation['paid_days'];$attendanceSalary=$calculation['attendance_salary'];
                $fund = round((float) $db->get_var($db->prepare(
                    "SELECT COALESCE(SUM(salary_fund),0) FROM ".Db::table('performance_entries')."
                     WHERE company_id=%d AND branch_id=%d AND employee_id=%d AND business_date BETWEEN %s AND %s",
                    $a->companyId,$branch,(int)$e['id'],$from,$to
                )), 2);
                $net = round($attendanceSalary + $fund, 2);$netTotal+=$net;
                $itemData=['calculation_json'=>wp_json_encode($calculation['snapshot']),'working_days'=>$working,'paid_days'=>$paid,'fixed_salary'=>$fixed,'attendance_salary'=>$attendanceSalary,'salary_fund_earning'=>$fund,'bonus'=>0,'allowances'=>0,'deductions'=>0,'net_salary'=>$net];
                if($rebuilt){
                    $existingItemId=(int)$db->get_var($db->prepare("SELECT id FROM {$items} WHERE payroll_run_id=%d AND employee_id=%d LIMIT 1",$run,(int)$e['id']));
                    if($existingItemId>0)Db::mustUpdate($db,$items,$itemData,['id'=>$existingItemId]);else Db::mustInsert($db,$items,['payroll_run_id'=>$run,'employee_id'=>(int)$e['id']]+$itemData);
                }else Db::mustInsert($db,$items,['payroll_run_id'=>$run,'employee_id'=>(int)$e['id']]+$itemData);
            }
            Db::mustUpdate($db,$runs,['calculation_version'=>'7.3.5'],['id'=>$run]);
            $netTotal=round($netTotal,2);
            if($netTotal<=0)throw new DomainException('Payroll net total must be greater than zero before a draft can be generated.','payroll_zero_total',422);

            Audit::add($a, $rebuilt?'payroll.regenerate_invalid_draft':'payroll.generate', 'payroll_run', $run, [
                'branch_id'=>$branch,'period_start'=>$from,'period_end'=>$to,'employee_count'=>count($employees),'net_total'=>$netTotal,'rebuilt_invalid_draft'=>$rebuilt,
            ]);
            return ['id'=>$run,'status'=>'draft','employee_count'=>count($employees),'net_total'=>$netTotal,'rebuilt_invalid_draft'=>$rebuilt];
        });
    }

    public static function updateItem(Actor $a, int $runId, int $itemId, float $bonus, float $allowances, float $deductions): array
    {
        if (!is_finite($bonus) || !is_finite($allowances) || !is_finite($deductions) || $bonus < 0 || $allowances < 0 || $deductions < 0) {
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
            $bonus=round($bonus,2);$allowances=round($allowances,2);$deductions=round($deductions,2);
            if($deductions>round((float)$item['attendance_salary']+(float)$item['salary_fund_earning']+$bonus+$allowances,2))throw new DomainException('Deductions exceed earnings; use a separate recovery balance.','payroll_excess_deduction',422);
            $net = round(max(0, (float) $item['attendance_salary'] + (float) $item['salary_fund_earning'] + $bonus + $allowances - $deductions), 2);
            Db::mustUpdate($db, Db::table('payroll_items'), [
                'bonus' => round($bonus, 2),
                'allowances' => round($allowances, 2),
                'deductions' => round($deductions, 2),
                'net_salary' => $net,
            ], ['id' => $itemId]);
            $editorTable=Db::table('payroll_editors');
            $editor=$db->get_var($db->prepare("SELECT id FROM {$editorTable} WHERE payroll_run_id=%d AND employee_id=%d",$runId,$a->employeeId));
            if(!$editor)Db::mustInsert($db,$editorTable,['payroll_run_id'=>$runId,'employee_id'=>$a->employeeId]);
            Audit::add($a, 'payroll.item_review', 'payroll_item', $itemId, [
                'payroll_run_id' => $runId,
                'branch_id' => (int) $run['branch_id'],
                'bonus' => round($bonus, 2),
                'allowances' => round($allowances, 2),
                'deductions' => round($deductions, 2),
                'net_salary' => $net,
                'old'=>array_intersect_key($item,array_flip(['bonus','allowances','deductions','net_salary'])),
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
            if(($run['calculation_version']??'')!=='7.3.5')throw new DomainException('Legacy payroll draft must be discarded and regenerated with corrected rules.','payroll_legacy_draft',409);
            $edited=$db->get_var($db->prepare('SELECT id FROM '.Db::table('payroll_editors').' WHERE payroll_run_id=%d AND employee_id=%d LIMIT 1',$id,$a->employeeId));
            if($edited)throw new DomainException('Payroll editor cannot approve this payroll.','maker_checker_required',409);
            if ((int) $run['created_by'] === $a->employeeId) {
                throw new DomainException('Maker cannot approve own payroll.', 'maker_checker_required', 409);
            }
            BranchDayGuard::assertOpen($a, (int) $run['branch_id'], (string) $run['period_end']);
            $stats = $db->get_row($db->prepare(
                "SELECT COUNT(*) item_count,COALESCE(SUM(net_salary),0) net_total,SUM(CASE WHEN fixed_salary<=0 THEN 1 ELSE 0 END) invalid_salary_items FROM ".Db::table('payroll_items')." WHERE payroll_run_id=%d",
                $id
            ), ARRAY_A) ?: [];
            if ((int)($stats['item_count']??0) < 1) throw new DomainException('Payroll has no items to approve.','payroll_items_missing',422);
            if ((int)($stats['invalid_salary_items']??0) > 0) throw new DomainException('Payroll contains employees without a valid fixed salary. Regenerate after salary setup.','payroll_salary_missing',422);
            $total = round((float)($stats['net_total']??0),2);
            if ($total <= 0) throw new DomainException('Payroll net total must be greater than zero before approval.','payroll_zero_total',422);
            $expense = AccountingService::accountByCode($a, 'PAYROLL_EXPENSE');
            $payable = AccountingService::accountByCode($a, 'PAYROLL_PAYABLE');
            $journal = AccountingService::post($a, (int) $run['branch_id'], 'payroll', $id, $run['period_end'].' 12:00:00', [
                ['account_id' => (int) $expense['id'], 'debit' => $total],
                ['account_id' => (int) $payable['id'], 'credit' => $total],
            ], 'Payroll approval');
            Db::mustUpdate($db, $table, [
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
        $paymentDate = Input::date($paymentDate,'Payroll payment date');
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
            if ($total <= 0) throw new DomainException('Payroll net total must be greater than zero before payment.','payroll_zero_total',422);
            $payable = AccountingService::accountByCode($a, 'PAYROLL_PAYABLE');
            $journal = AccountingService::post($a, (int) $run['branch_id'], 'payroll_payment', $id, $paymentDate.' 12:00:00', [
                ['account_id' => (int) $payable['id'], 'debit' => $total],
                ['account_id' => (int) $payment['id'], 'credit' => $total],
            ], 'Payroll payment');
            Db::mustUpdate($db, $table, [
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
        [$from,$to] = Input::dateRange($from,$to,'Performance period');
        $db = Db::wpdb();
        $peerView = self::canViewPeerPerformance($a);
        if (!$peerView) {
            if ($employee !== null && $employee !== $a->employeeId) {
                throw new DomainException('You may view only your own performance.', 'performance_self_only', 403);
            }
            $employee = $a->employeeId;
        }
        $where = '';
        $args = [$a->companyId, $branch, $from, $to];
        if ($peerView) {
            $visible = HierarchyScope::visibleEmployeeIds($a, $branch);
            if ($employee !== null) {
                HierarchyScope::assertCanViewEmployee($a, $employee);
                if (!in_array($employee, $visible, true)) throw new DomainException('Employee is outside selected reporting scope.', 'employee_scope_forbidden', 403);
                $visible = [$employee];
            }
            if (!$visible) return [];
            $where = ' AND pe.employee_id IN ('.implode(',', array_fill(0, count($visible), '%d')).')';
            $args = array_merge($args, $visible);
        } else {
            $where = ' AND pe.employee_id=%d';
            $args[] = $a->employeeId;
        }
        $rows = (array) $db->get_results($db->prepare(
            "SELECT pe.employee_id,e.full_name,e.designation_code,e.reporting_designation_code,COALESCE(SUM(pe.points),0) points,COALESCE(SUM(pe.salary_fund),0) salary_fund
             FROM ".Db::table('performance_entries')." pe
             JOIN ".Db::table('employees')." e ON e.id=pe.employee_id
             WHERE pe.company_id=%d AND pe.branch_id=%d AND pe.business_date BETWEEN %s AND %s{$where}
             GROUP BY pe.employee_id,e.full_name,e.designation_code,e.reporting_designation_code ORDER BY points DESC",
            ...$args
        ), ARRAY_A);
        foreach($rows as &$row)$row['reporting_category']=HierarchyScope::reportingCategoryForCode((string)$row['designation_code'],(string)($row['reporting_designation_code']??''));unset($row);return $rows;
    }

    private static function canViewPeerPerformance(Actor $a): bool
    {
        return $a->can(Capabilities::PERFORMANCE_MANAGE) || $a->can(Capabilities::EMP_VIEW);
    }

    public static function target(Actor $a, int $branch, int $employee, string $from, string $to, float $points): array
    {
        Guard::branch($a, $branch, Capabilities::PERFORMANCE_MANAGE);
        [$from,$to] = Input::dateRange($from,$to,'Target period');
        if ($points < 0) {
            throw new DomainException('Target points cannot be negative.','target_points_invalid',422);
        }
        if (!is_finite($points)) {
            throw new DomainException('Target points must be finite.','target_points_invalid',422);
        }
        return Transaction::run(function() use ($a,$branch,$employee,$from,$to,$points) {
            $db = Db::wpdb();
            HierarchyScope::assertCanViewEmployee($a,$employee);
            $employeeTable=Db::table('employees');
            $valid = (int) $db->get_var($db->prepare(
                "SELECT COUNT(*) FROM {$employeeTable} WHERE id=%d AND company_id=%d AND assigned_branch_id=%d AND status='active' FOR UPDATE",
                $employee,
                $a->companyId,
                $branch
            ));
            if (!$valid) {
                throw new DomainException('Active employee not found in selected branch.', 'employee_branch_mismatch', 422);
            }
            $targetTable=Db::table('performance_targets');
            $overlap=(int)$db->get_var($db->prepare(
                "SELECT COUNT(*) FROM {$targetTable} WHERE company_id=%d AND employee_id=%d AND status IN ('draft','approved') AND NOT(period_end<%s OR period_start>%s)",
                $a->companyId,$employee,$from,$to
            ));
            if($overlap)throw new DomainException('An overlapping performance target already exists for this employee.','performance_target_overlap',409);
            Db::mustInsert($db,$targetTable, [
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
        });
    }

    public static function approveTarget(Actor $a, int $id): array
    {
        Guard::cap($a, Capabilities::PERFORMANCE_MANAGE);
        return Transaction::run(function () use ($a, $id) {
            $db = Db::wpdb();
            $table = Db::table('performance_targets');
            $row = $db->get_row($db->prepare(
                "SELECT * FROM {$table} WHERE id=%d AND company_id=%d FOR UPDATE",
                $id,
                $a->companyId
            ), ARRAY_A);
            if (!$row) {
                throw new DomainException('Target not found.', 'target_not_found', 404);
            }
            Guard::branch($a, (int) $row['branch_id'], Capabilities::PERFORMANCE_MANAGE);
            HierarchyScope::assertCanViewEmployee($a, (int) $row['employee_id']);
            if ($row['status'] !== 'draft') {
                throw new DomainException('Only draft target can be approved.', 'target_state_invalid', 409);
            }
            if ((int) $row['created_by'] === $a->employeeId) {
                throw new DomainException('Maker cannot approve own target.', 'maker_checker_required', 409);
            }
            Db::mustUpdate($db, $table, ['status' => 'approved', 'approved_by' => $a->employeeId], ['id' => $id]);
            Audit::add($a, 'performance_target.approve', 'performance_target', $id, ['branch_id' => (int) $row['branch_id']]);
            return ['id' => $id, 'status' => 'approved'];
        });
    }

    /** Query data separately from the deterministic monthly calculator. */
    private static function dayCounts(int $company,int $branch,int $employee,string $from,string $to,?string $joining,?string $separation):array {
        $db=Db::wpdb();$monthStart=substr($from,0,7).'-01';$monthEnd=(new \DateTimeImmutable($monthStart))->modify('last day of this month')->format('Y-m-d');
        $raw=self::readPayroll($db,'get_var',$db->prepare("SELECT setting_value FROM ".Db::table('settings')." WHERE company_id=%d AND setting_key='weekly_off_iso_days'",$company));
        $off=$raw===null?[7]:json_decode((string)$raw,true);
        if(!is_array($off)||array_filter($off,fn($v)=>!is_int($v)||$v<1||$v>7))throw new DomainException('Invalid weekly-off policy.','payroll_calendar_invalid',422);
        $raw=self::readPayroll($db,'get_var',$db->prepare("SELECT setting_value FROM ".Db::table('settings')." WHERE company_id=%d AND setting_key='payroll_leave_types'",$company));
        $leaveTypes=json_decode((string)$raw,true)?:[];
        $holidays=(array)self::readPayroll($db,'get_results',$db->prepare("SELECT holiday_date,branch_id FROM ".Db::table('holidays')." WHERE company_id=%d AND active=1 AND holiday_date BETWEEN %s AND %s AND (branch_id IS NULL OR branch_id=%d)",$company,$monthStart,$monthEnd,$branch),ARRAY_A);
        $common=[];$local=[];foreach($holidays as$h){if($h['branch_id']===null)$common[]=$h['holiday_date'];else$local[]=$h['holiday_date'];}
        $present=(array)self::readPayroll($db,'get_col',$db->prepare("SELECT business_date FROM ".Db::table('attendance')." WHERE company_id=%d AND branch_id=%d AND employee_id=%d AND business_date BETWEEN %s AND %s AND status='present'",$company,$branch,$employee,$from,$to));
        $leaves=(array)self::readPayroll($db,'get_results',$db->prepare("SELECT date_from,date_to,leave_type FROM ".Db::table('leave_requests')." WHERE company_id=%d AND employee_id=%d AND status='approved' AND date_from<=%s AND date_to>=%s",$company,$employee,$to,$from),ARRAY_A);
        $history=(array)self::readPayroll($db,'get_results',$db->prepare("SELECT branch_id,effective_from,effective_to FROM ".Db::table('employee_branch_history')." WHERE company_id=%d AND employee_id=%d AND effective_from<=%s AND (effective_to IS NULL OR effective_to>=%s)",$company,$employee,$to,$from),ARRAY_A);
        $salaryHistory=(array)self::readPayroll($db,'get_results',$db->prepare("SELECT id,effective_from,monthly_salary FROM ".Db::table('salary_revisions')." WHERE company_id=%d AND employee_id=%d AND status IN ('approved','baseline') AND effective_from<=%s ORDER BY effective_from,id",$company,$employee,$to),ARRAY_A);
        if(!empty($db->last_error))throw new DomainException('Unable to load payroll calculation data.','payroll_read_failed',500);
        $input=['from'=>$from,'to'=>$to,'joining'=>$joining,'separation'=>$separation,'branch'=>$branch,'weekly_off'=>array_values(array_unique($off)),'company_holidays'=>$common,'branch_holidays'=>$local,'present'=>$present,'leaves'=>$leaves,'leave_types'=>$leaveTypes,'branch_history'=>$history,'salary_history'=>$salaryHistory];
        $result=PayrollCalculator::calculate($input);$result['snapshot']=$input;return $result;
    }

    private static function readPayroll(object $db,string $method,mixed ...$args):mixed {
        $result=$db->{$method}(...$args);
        if(!empty($db->last_error))throw new DomainException('Unable to read payroll inputs.','payroll_read_failed',500);
        return $result;
    }

    public static function discardDraft(Actor $a,int $id,string $reason):array {
        if(strlen(trim($reason))<5)throw new DomainException('Discard reason is required.','reason_required',422);
        return Transaction::run(function()use($a,$id,$reason){
            SalaryService::lockCompany($a->companyId);$db=Db::wpdb();$t=Db::table('payroll_runs');$run=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE company_id=%d AND id=%d FOR UPDATE",$a->companyId,$id),ARRAY_A);
            if(!$run)throw new DomainException('Payroll not found.','payroll_not_found',404);
            Guard::branch($a,(int)$run['branch_id'],Capabilities::PAYROLL_GENERATE);
            if($run['status']!=='draft'||!empty($run['journal_entry_id'])||!empty($run['payment_journal_entry_id']))throw new DomainException('Only unposted drafts can be discarded.','payroll_state_invalid',409);
            $items=(array)$db->get_results($db->prepare('SELECT * FROM '.Db::table('payroll_items').' WHERE payroll_run_id=%d',$id),ARRAY_A);
            Audit::add($a,'payroll.discard','payroll_run',$id,['branch_id'=>(int)$run['branch_id'],'reason'=>$reason,'run'=>$run,'items'=>$items]);
            Db::mustQuery($db,$db->prepare('DELETE FROM '.Db::table('payroll_editors').' WHERE payroll_run_id=%d',$id));
            Db::mustQuery($db,$db->prepare('DELETE FROM '.Db::table('payroll_items').' WHERE payroll_run_id=%d',$id));
            Db::mustQuery($db,$db->prepare("DELETE FROM {$t} WHERE id=%d",$id));return ['id'=>$id,'status'=>'discarded'];
        });
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
