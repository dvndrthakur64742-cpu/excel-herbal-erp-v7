<?php
namespace ExcelHerbal\ERP7\Payroll;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;
use ExcelHerbal\ERP7\Security\HierarchyScope;

/**
 * Read-only HR promotion evidence; never a machine approval or execution.
 * The eligible points window and definition of minimum service days are NOT
 * yet ratified. Raw evidence cannot be substituted for an HR determination.
 */
final class PromotionEligibilityEvidenceService {
    /** @return array<string,mixed> */
    public static function inspect(Actor $actor,int $requestId):array {
        Guard::cap($actor,Capabilities::PROMOTION_APPROVE);
        Guard::cap($actor,Capabilities::HR_REVIEW);
        if($requestId<1)throw new DomainException(
            'Promotion request not found.','promotion_not_found',404
        );
        $db=Db::wpdb();
        $promotion=$db->get_row($db->prepare(
            'SELECT * FROM '.Db::table('promotion_requests').
            ' WHERE company_id=%d AND id=%d',
            $actor->companyId,$requestId
        ),ARRAY_A);
        if(!$promotion)throw new DomainException(
            'Promotion request not found.','promotion_not_found',404
        );
        $branch=(int)$promotion['branch_id'];
        $employee=(int)$promotion['employee_id'];
        Guard::branch($actor,$branch,Capabilities::PROMOTION_APPROVE);
        HierarchyScope::assertCanViewEmployee($actor,$employee);
        if(in_array($actor->employeeId,[
            $employee,(int)$promotion['created_by'],
        ],true))throw new DomainException(
            'Independent HR checker is required.','maker_checker_required',409
        );
        $row=$db->get_row($db->prepare(
            'SELECT id,assigned_branch_id,status,designation_code,joining_date'.
            ' FROM '.Db::table('employees').
            ' WHERE company_id=%d AND id=%d',
            $actor->companyId,$employee
        ),ARRAY_A);
        if(!$row)throw new DomainException(
            'Employee not found.','employee_not_found',404
        );
        $today=Db::today();
        $joining=(string)($row['joining_date']??'');
        $tenureDays=null;
        if($joining!==''&&$joining<=$today){
            $tenureDays=(int)(new \DateTimeImmutable($joining))
                ->diff(new \DateTimeImmutable($today))->format('%a')+1;
        }
        $from=$joining!==''?$joining:'1900-01-01';
        $measure=$db->get_row($db->prepare(
            'SELECT COALESCE(SUM(points),0) AS observed_points,'.
            ' COUNT(DISTINCT business_date) AS recorded_days,'.
            ' MIN(business_date) AS first_event_date,'.
            ' MAX(business_date) AS last_event_date'.
            ' FROM '.Db::table('performance_entries').
            ' WHERE company_id=%d AND employee_id=%d'.
            ' AND business_date>=%s AND business_date<=%s',
            $actor->companyId,$employee,$from,$today
        ),ARRAY_A)?:[];
        $isCurrent=(int)$row['assigned_branch_id']===$branch&&
            (string)$row['status']==='active'&&
            strtoupper(trim((string)$row['designation_code']))===
                (string)$promotion['current_designation_code'];
        $designationActive=(int)$db->get_var($db->prepare(
            'SELECT COUNT(*) FROM '.Db::table('designations').
            " WHERE company_id=%d AND code=%s AND status='active'",
            $actor->companyId,(string)$promotion['next_designation_code']
        ))===1;
        $blockers=[];
        if($promotion['status']!=='approved_pending_execution')
            $blockers[]='promotion_independent_review_incomplete';
        if(!$isCurrent)$blockers[]='promotion_employee_scope_or_designation_changed';
        if(!$designationActive)$blockers[]='promotion_destination_inactive';
        if($promotion['effective_from']<$today)
            $blockers[]='promotion_effective_date_requires_new_review';
        if($tenureDays===null)
            $blockers[]='promotion_joining_date_evidence_missing';
        // These evidence gaps are ALWAYS blockers until the governing
        // eligibility policy and atomic HR execution are implemented.
        $blockers[]='promotion_points_qualifying_window_unapproved';
        $blockers[]='promotion_minimum_days_policy_unapproved';
        $blockers[]='promotion_atomic_hr_execution_unavailable';
        if(SalaryStructureService::paise(
            (string)$promotion['monthly_increment_amount'],
            'monthly_increment_amount'
        )>0){
            $blockers[]='promotion_salary_revision_execution_unavailable';
        }

        return [
            'id'=>$requestId,
            'employee_id'=>$employee,'branch_id'=>$branch,
            'review_status'=>(string)$promotion['status'],
            'execution_state'=>(string)$promotion['execution_state'],
            'as_of_date'=>$today,
            'minimum_points_snapshot'=>
                (string)$promotion['promotion_min_points_snapshot'],
            'minimum_days_snapshot'=>
                (int)$promotion['minimum_days_snapshot'],
            'calendar_tenure_days'=>$tenureDays,
            'calendar_days_are_qualifying_days'=>false,
            'observed_points_since_joining'=>
                (string)($measure['observed_points']??'0.00'),
            'recorded_performance_days'=>
                (int)($measure['recorded_days']??0),
            'performance_first_event'=>$measure['first_event_date']??null,
            'performance_last_event'=>$measure['last_event_date']??null,
            'observed_points_are_verified_qualifying_points'=>false,
            'eligibility_verified'=>false,
            'execution_ready'=>false,
            'employee_changes_applied'=>false,
            'blocking_reason_codes'=>array_values(array_unique($blockers)),
        ];
    }
}
