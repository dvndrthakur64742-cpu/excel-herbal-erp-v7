<?php
namespace ExcelHerbal\ERP7\Payroll;

use ExcelHerbal\ERP7\Domain\DomainException;

/** Pure working-day policy. Each month has one company calendar across all branches. */
final class PayrollCalculator {
    public static function calculate(array $p): array {
        $from = new \DateTimeImmutable($p['from']);
        $to = new \DateTimeImmutable($p['to']);
        if ($from > $to || $from->format('Y-m') !== $to->format('Y-m')) {
            throw new DomainException('Generate one calendar month or a sub-period within it at a time.', 'payroll_period_invalid', 422);
        }
        $off = $p['weekly_off'];
        $common = array_fill_keys($p['company_holidays'], true);
        $local = array_fill_keys($p['branch_holidays'], true);
        $present = array_fill_keys($p['present'], true);
        $days = [];
        for ($d=$from->modify('first day of this month'); $d <= $from->modify('last day of this month'); $d=$d->modify('+1 day')) {
            $date=$d->format('Y-m-d');
            if (!in_array((int)$d->format('N'),$off,true) && !isset($common[$date])) $days[]=$date;
        }
        $denominator=count($days);$paid=0;$cents=0;
        $history=$p['branch_history'];$salaries=$p['salary_history'];
        usort($salaries,fn($a,$b)=>strcmp($a['effective_from'],$b['effective_from']) ?: ((int)$a['id'] <=> (int)$b['id']));
        foreach ($days as $index=>$date) {
            if ($date<$p['from'] || $date>$p['to'] || (!empty($p['joining']) && $date<$p['joining']) || (!empty($p['separation']) && $date>$p['separation'])) continue;
            $matches=[];
            foreach ($history as $h) if ($date >= $h['effective_from'] && (empty($h['effective_to']) || $date <= $h['effective_to'])) $matches[]=(int)$h['branch_id'];
            if (count($matches)!==1) throw new DomainException('Employee branch history has a gap or overlap on '.$date.'.', 'payroll_branch_history_invalid', 409);
            if ($matches[0] !== (int)$p['branch']) continue;
            $salary=null;
            foreach ($salaries as $s) if ($s['effective_from'] <= $date) $salary=(float)$s['monthly_salary'];
            if ($salary===null || !is_finite($salary) || $salary<=0) throw new DomainException('Approved salary history is required for '.$date.'.', 'payroll_salary_history_required', 422);
            $leavePaid=null;
            foreach ($p['leaves'] as $leave) {
                if ($date<$leave['date_from'] || $date>$leave['date_to']) continue;
                if ($leavePaid!==null) throw new DomainException('Overlapping approved leave must be corrected.', 'payroll_leave_overlap', 409);
                $key=strtoupper(trim($leave['leave_type']));
                if (!array_key_exists($key,$p['leave_types']) || !is_bool($p['leave_types'][$key])) throw new DomainException('Configure paid/unpaid treatment for leave type '.$key.'.', 'payroll_leave_policy_required', 422);
                $leavePaid=$p['leave_types'][$key];
                if (isset($present[$date])) throw new DomainException('Attendance conflicts with approved leave on '.$date.'.', 'payroll_attendance_leave_conflict', 409);
            }
            if ($leavePaid===false || ($leavePaid!==true && !isset($present[$date]) && !isset($local[$date]))) continue;
            $paid++;
            // Cumulative rounding allocates all cents exactly across a full month and branch transfers.
            $salaryCents=(int)round($salary*100);
            $cents+=(int)round($salaryCents*($index+1)/$denominator)-(int)round($salaryCents*$index/$denominator);
        }
        $snapshot=0.0;foreach($salaries as$s)if($s['effective_from']<=$p['to'])$snapshot=(float)$s['monthly_salary'];
        return ['fixed_salary'=>$snapshot,'working_days'=>$denominator,'paid_days'=>$paid,'attendance_salary'=>$cents/100];
    }
}
