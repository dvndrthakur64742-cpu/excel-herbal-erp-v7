<?php
namespace ExcelHerbal\ERP7\Http;

use ExcelHerbal\ERP7\Core\Input;
use ExcelHerbal\ERP7\Domain\DomainException;

/**
 * Stable, machine-readable API contract metadata plus conservative request validation.
 * Service-layer validation remains authoritative for business rules.
 */
final class ApiContract
{
    public const VERSION='7.3.5-contract-1';

    /** @return array<string,bool> */
    public static function featureFlags():array
    {
        return [
            'gps_points'=>true,
            'gps_route'=>true,
            'gps_auto_duty_window'=>true,
            'gps_hierarchy_scope'=>true,
            'gps_team_map'=>true,
            'holidays'=>true,
            'employee_documents'=>true,
            'employee_offboarding'=>true,
            'employee_reactivation'=>true,
            'reporting_hierarchy_manage'=>true,
            'reporting_designation'=>true,
            'multiple_designations'=>true,
            'price_distribution_report'=>true,
            'notification_read_state'=>true,
            'announcement_acknowledgement'=>true,
            'push_device_registry'=>true,
            'task_management'=>true,
            'app_version_policy'=>true,
            'session_management'=>true,
            'employee_login_management'=>true,
            'holiday_management'=>true,
            'employee_document_upload'=>true,
            'communication_management'=>true,
            'master_data_maintenance'=>true,
            'system_diagnostics'=>true,
            'automatic_cleanup'=>true,
            'whole_pcs_validation'=>true,
            'payload_bound_idempotency'=>true,
            'stable_device_identity'=>true,
            'transfer_accounting_repair'=>true,
            'acting_duty_delegation'=>true,
            'acting_duty_fallback'=>true,
            'acting_duty_inbox'=>true,
            'acting_unavailability'=>true,
            'hr_candidate_lifecycle'=>true,
            'hr_candidate_documents'=>true,
            'hr_separation_workflow'=>true,
            'salary_revision_approval'=>true,
            'payroll_working_day_proration'=>true,
            'private_document_download'=>true,
            'stock_quarantine_workflow'=>true,
        ];
    }

    /** @return array<string,array<int,string>> */
    private static function required():array
    {
        return [
            'payroll.salary_request'=>['monthly_salary','effective_from','reason'],
            'payroll.salary_review'=>['approve'],
            'payroll.discard'=>['reason'],
            'payroll.policy_update'=>['leave_types','reason'],
            'setup.initialize'=>['company_name','branch_code','branch_name','employee_code','employee_name'],
            'auth.login'=>['mobile','password'],
            'auth.refresh'=>['refresh_token'],
            'org.branch_create'=>['code','name'],
            'org.branch_status'=>['active'],
            'org.employee_create'=>['assigned_branch_id','employee_code','full_name','designation_code'],
            'org.employee_credentials'=>['password'],
            'org.employee_document_upload'=>['document_type','title'],
            'work.holiday_create'=>['holiday_date','name'],
            'comm.announcement_create'=>['title','body'],
            'comm.notification_create'=>['employee_id','title'],
            'org.employee_transfer'=>['branch_id','reason'],
            'org.employee_offboard'=>['separation_date','reason'],
            'org.employee_reactivate'=>['reactivation_date','reason'],
            'org.employee_reporting_manager'=>['reason'],
            'org.employee_designation_assign'=>['designation_code','assignment_type','effective_from'],
            'org.branch_authority'=>['employee_id','branch_id','active'],
            'org.employee_document_add'=>['attachment_id','document_type','title'],
            'hr.candidate_create'=>['branch_id','full_name','proposed_designation_code'],
            'hr.candidate_review'=>['decision','reason'],
            'hr.candidate_joining'=>['joining_date'],
            'hr.candidate_credentials'=>['password'],
            'hr.candidate_no_show'=>['reason'],
            'hr.candidate_document_upload'=>['document_type','title'],
            'hr.separation_initiate'=>['separation_date','reason'],
            'hr.separation_review'=>['approve','reason'],
            'work.check_in'=>['branch_id'],
            'work.visit_start'=>['branch_id','purpose'],
            'work.leave'=>['leave_type','date_from','date_to'],
            'work.leave_decision'=>['approve'],
            'catalog.product_create'=>['sku','name'],
            'catalog.product_status'=>['active'],
            'catalog.product_revision'=>['mrp','sale_price','ho_amount','bm_profit','salary_fund','office_expense','points','purchase_cost'],
            'daily.create'=>['branch_id','employee_id','business_date','lines'],
            'daily.additional'=>['lines'],
            'daily.issue'=>['allocations'],
            'daily.evening_save'=>['lines'],
            'inventory.transfer_create'=>['source_branch_id','destination_branch_id','lines'],
            'inventory.transfer_receive'=>['lines'],
            'inventory.transfer_correct'=>['note'],
            'inventory.transfer_cancel'=>['reason'],
            'inventory.adjustment'=>['branch_id','reason','lines'],
            'inventory.adjustment_decision'=>['approve'],
            'inventory.quarantine_hold'=>['branch_id','product_id','quantity','reason'],
            'inventory.quarantine_resolve'=>['action','reason'],
            'sales.customer_create'=>['branch_id','name'],
            'sales.customer_status'=>['active'],
            'sales.counter'=>['branch_id','lines'],
            'sales.receipt'=>['branch_id','sale_id','amount','payment_account_id'],
            'purchase.supplier_create'=>['name'],
            'purchase.supplier_status'=>['active'],
            'purchase.bill'=>['branch_id','supplier_id','bill_no','bill_date','lines'],
            'purchase.payment'=>['purchase_bill_id','amount','payment_account_id'],
            'finance.account_create'=>['code','name','type'],
            'finance.expense_head_create'=>['code','name','expense_account_id'],
            'finance.expense'=>['branch_id','expense_head_id','amount','payment_account_id','expense_date'],
            'finance.expense_decision'=>['approve'],
            'finance.closing_draft'=>['branch_id','business_date'],
            'finance.closing_reopen'=>['reason'],
            'finance.reversal_request'=>['source_type','source_id','reason'],
            'finance.reversal_decision'=>['approve'],
            'finance.period_close'=>['date_from','date_to'],
            'finance.period_reopen'=>['reason'],
            'finance.bank_create'=>['branch_id','account_id','statement_from','statement_to','opening_balance','closing_balance'],
            'finance.bank_import'=>['lines'],
            'finance.bank_match'=>['journal_line_id'],
            'finance.bank_exclude'=>['reason'],
            'payroll.generate'=>['branch_id','period_start','period_end'],
            'payroll.item_update'=>['bonus','allowances','deductions'],
            'payroll.pay'=>['payment_account_id','payment_date'],
            'performance.target'=>['branch_id','employee_id','period_start','period_end','target_points'],
            'comm.push_register'=>['token','platform'],
            'comm.task_create'=>['assigned_employee_id','title'],
            'comm.task_assign'=>['employee_id'],
            'comm.task_reassign'=>['employee_id'],
            'access.role_create'=>['code','name'],
            'access.role_caps'=>['capabilities','reason'],
            'access.employee_update'=>['reason'],
            'access.employee_roles'=>['role_ids','reason'],
            'access.employee_overrides'=>['grants','denies','reason'],
            'admin.delegation_create'=>['delegate_employee_id','branch_id','action_code','starts_at','ends_at','reason'],
            'admin.delegation_revoke'=>['reason'],
            'admin.authority_status'=>['branch_id','action_code'],
            'admin.unavailability_create'=>['branch_id','starts_at','ends_at','reason'],
            'admin.unavailability_revoke'=>['reason'],
            'admin.transfer_accounting_repair'=>['confirmation'],
        ];
    }

    /** @return array<string,mixed> */
    public static function describe():array
    {
        $routes=[];
        foreach(RouteRegistry::routes() as[$method,$path,$handler,$auth]){
            $routes[]=[
                'method'=>$method,
                'path'=>$path,
                'auth'=>$auth,
                'idempotency_required'=>$auth&&$method!=='GET'&&!str_starts_with($handler,'auth.'),
                'required_params'=>self::required()[$handler]??[],
            ];
        }
        return [
            'contract_version'=>self::VERSION,
            'namespace'=>'excel-herbal-erp/v7',
            'authentication'=>'Bearer access token for authenticated routes',
            'idempotency_header'=>'X-Idempotency-Key',
            'features'=>self::featureFlags(),
            'routes'=>$routes,
        ];
    }

    public static function validate(string $handler,$request,string $method):void
    {
        $required=self::required()[$handler]??[];
        foreach($required as$key){
            $v=$request->get_param($key);
            if($v===null||(is_string($v)&&trim($v)==='')){
                throw new DomainException($key.' is required.','parameter_required',422);
            }
        }

        if($handler==='access.employee_update') {
            $roles=$request->get_param('role_ids');
            $grants=$request->get_param('grants');
            $denies=$request->get_param('denies');
            if($roles===null&&$grants===null&&$denies===null)throw new DomainException('Select a role or permission change.','access_change_required',422);
            if(($grants===null)!==($denies===null))throw new DomainException('Grant and deny overrides must be supplied together.','capability_override_invalid',422);
        }

        // Recovery GPS accepts either lat/lng or latitude/longitude aliases.
        if($handler==='work.gps_point'){
            $lat=$request->get_param('lat')??$request->get_param('latitude');
            $lng=$request->get_param('lng')??$request->get_param('longitude');
            if($lat===null||$lng===null||$lat===''||$lng==='')throw new DomainException('GPS latitude and longitude are required.','parameter_required',422);
        }
        if($handler==='comm.push_deactivate'){
            $id=$request->get_param('id');$token=$request->get_param('token');
            if(($id===null||$id===''||(int)$id<1)&&($token===null||trim((string)$token)===''))throw new DomainException('Push device id or token is required.','parameter_required',422);
        }
        if($handler==='app.version_policy_update'){
            $body=$request->get_json_params();if(!is_array($body))$body=(array)$request->get_params();
            if(!array_intersect(array_keys($body),['minimum_build','latest_build','minimum_version','latest_version','update_url','message']))throw new DomainException('At least one app version policy field is required.','parameter_required',422);
        }

        if(in_array($handler,['org.branch_update','org.employee_update','catalog.product_update','sales.customer_update','purchase.supplier_update'],true)){
            $body=$request->get_json_params();if(!is_array($body))$body=(array)$request->get_params();
            $allowed=match($handler){'org.branch_update'=>['code','name'],'org.employee_update'=>['full_name','mobile','email','monthly_salary','designation_code','reporting_designation_code','joining_date'],'catalog.product_update'=>['sku','name','uom','batch_tracking','expiry_tracking'],'sales.customer_update'=>['name','mobile','email','address'],'purchase.supplier_update'=>['name','mobile','gstin'],default=>[]};
            if(!array_intersect(array_keys($body),$allowed))throw new DomainException('At least one editable field is required.','parameter_required',422);
        }

        // Direct scalar IDs: reject floats, text and zero rather than silently casting to 0.
        foreach(['branch_id','employee_id','delegator_employee_id','delegate_employee_id','primary_employee_id','maker_employee_id','reporting_employee_id','assigned_employee_id','source_branch_id','destination_branch_id','supplier_id','sale_id','purchase_bill_id','payment_account_id','expense_head_id','expense_account_id','account_id','source_id','journal_line_id','attachment_id','field_visit_id','party_id','customer_id','product_id','batch_id','client_build','limit','offset'] as$key){
            $v=$request->get_param($key);if($v===null||$v==='')continue;
            if(!is_int($v)&&!(is_string($v)&&ctype_digit($v)))throw new DomainException($key.' must be an integer.','parameter_invalid',422);
            $n=(int)$v;
            $isRequired=in_array($key,$required,true);
            if(in_array($key,['client_build','limit','offset'],true)){if($n<0)throw new DomainException($key.' cannot be negative.','parameter_invalid',422);}
            elseif($isRequired&&$n<1)throw new DomainException($key.' must be a positive integer.','parameter_invalid',422);
            elseif(!$isRequired&&$n<0)throw new DomainException($key.' cannot be negative.','parameter_invalid',422);
        }

        foreach(['approve','active','is_head_office','expiry_tracking','provision_login'] as$key){
            $v=$request->get_param($key);if($v===null)continue;
            if(is_bool($v))continue;
            if(is_int($v)&&($v===0||$v===1))continue;
            if(is_string($v)&&in_array(strtolower(trim($v)),['0','1','true','false'],true))continue;
            throw new DomainException($key.' must be a boolean.','parameter_invalid',422);
        }

        foreach(['business_date','date_from','date_to','bill_date','expense_date','statement_from','statement_to','period_start','period_end','payment_date','effective_date','effective_from','effective_to','joining_date','reactivation_date','manufactured_on','expires_on','holiday_date','separation_date','expected_joining_date'] as$key){
            $v=$request->get_param($key);if($v===null||trim((string)$v)==='')continue;
            Input::date((string)$v,str_replace('_',' ',$key));
        }

        foreach(['amount','quantity','cash','upi','opening_balance','closing_balance','bonus','allowances','deductions','target_points','monthly_salary','mrp','sale_price','ho_amount','bm_profit','salary_fund','office_expense','points','purchase_cost','offered_monthly_salary'] as$key){
            $v=$request->get_param($key);if($v===null||$v==='')continue;
            if(!is_numeric($v)||!is_finite((float)$v))throw new DomainException($key.' must be a finite number.','parameter_invalid',422);
        }

        foreach(['lines','allocations','capabilities','role_ids','grants','denies'] as$key){
            $v=$request->get_param($key);if($v===null)continue;
            if(!is_array($v))throw new DomainException($key.' must be an array.','parameter_invalid',422);
        }
    }
}
