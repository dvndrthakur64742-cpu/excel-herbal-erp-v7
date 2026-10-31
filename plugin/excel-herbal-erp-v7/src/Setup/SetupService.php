<?php
namespace ExcelHerbal\ERP7\Setup;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Schema;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;

final class SetupService {
    public static function status(): array {
        $db=Db::wpdb();
        $companies=(int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('companies'));
        return ['schema_version'=>Schema::VERSION,'schema_installed'=>(string)get_option('eh7_schema_version','')===Schema::VERSION,'initialized'=>$companies>0];
    }

    public static function initialize(array $data): array {
        if(!current_user_can('manage_options')) throw new DomainException('WordPress administrator permission required.','setup_admin_required',403);
        if((string)get_option('eh7_schema_version','')!==Schema::VERSION) throw new DomainException('Install or upgrade the EH7 schema before initialization.','setup_schema_required',409);
        $uid=(int)get_current_user_id();
        if($uid<1) throw new DomainException('Authenticated WordPress administrator required.','setup_auth_required',401);
        $company=trim((string)($data['company_name']??''));
        $branchCode=strtoupper(trim((string)($data['branch_code']??'')));
        $branchName=trim((string)($data['branch_name']??''));
        $employeeCode=strtoupper(trim((string)($data['employee_code']??'')));
        $employeeName=trim((string)($data['employee_name']??''));
        $mobile=preg_replace('/\D+/','',(string)($data['mobile']??''));
        if($company===''||$branchCode===''||$branchName===''||$employeeCode===''||$employeeName==='') throw new DomainException('Company, branch and first administrator identity are required.','setup_fields_required',422);

        $db=Db::wpdb();
        $lock=(int)$db->get_var("SELECT GET_LOCK('eh7_initial_setup',5)");
        if($lock!==1) throw new DomainException('ERP initialization is already in progress.','setup_in_progress',409);
        try{return Transaction::run(function()use($uid,$company,$branchCode,$branchName,$employeeCode,$employeeName,$mobile){
            $db=Db::wpdb();
            if((int)$db->get_var('SELECT COUNT(*) FROM '.Db::table('companies'))>0) throw new DomainException('ERP is already initialized.','setup_already_initialized',409);
            Db::mustInsert($db,Db::table('companies'),['name'=>$company,'status'=>'active','created_at'=>Db::now()]);
            $companyId=(int)$db->insert_id;if(!$companyId)throw new DomainException('Company initialization failed.','setup_company_failed',500);
            Db::mustInsert($db,Db::table('branches'),['company_id'=>$companyId,'code'=>$branchCode,'name'=>$branchName,'is_head_office'=>1,'status'=>'active','created_at'=>Db::now()]);
            $branchId=(int)$db->insert_id;if(!$branchId)throw new DomainException('Head office initialization failed.','setup_branch_failed',500);
            Db::mustInsert($db,Db::table('designations'),['company_id'=>$companyId,'code'=>'SYSADMIN','name'=>'System Administrator','sequence_no'=>1,'field_role'=>0,'status'=>'active']);
            if(!$db->insert_id)throw new DomainException('Administrator designation initialization failed.','setup_designation_failed',500);
            Db::mustInsert($db,Db::table('employees'),['company_id'=>$companyId,'employee_code'=>$employeeCode,'wp_user_id'=>$uid,'designation_code'=>'SYSADMIN','assigned_branch_id'=>$branchId,'full_name'=>$employeeName,'mobile'=>$mobile?:null,'monthly_salary'=>0,'joining_date'=>Db::today(),'status'=>'active','created_at'=>Db::now()]);
            $employeeId=(int)$db->insert_id;if(!$employeeId)throw new DomainException('Administrator employee initialization failed.','setup_employee_failed',500);
            Db::mustInsert($db,Db::table('employee_branch_history'),['company_id'=>$companyId,'employee_id'=>$employeeId,'branch_id'=>$branchId,'effective_from'=>Db::today(),'effective_to'=>null,'reason'=>'Initial ERP setup','changed_by'=>$employeeId,'created_at'=>Db::now()]);
            Db::mustInsert($db,Db::table('roles'),['company_id'=>$companyId,'code'=>'SYSTEM_ADMIN','name'=>'System Administrator','active'=>1]);
            $roleId=(int)$db->insert_id;if(!$roleId)throw new DomainException('Administrator role initialization failed.','setup_role_failed',500);
            $caps=array_values(array_unique(array_values((new \ReflectionClass(Capabilities::class))->getConstants())));
            foreach($caps as$cap)Db::mustInsert($db,Db::table('role_capabilities'),['role_id'=>$roleId,'capability'=>$cap,'active'=>1,'created_at'=>Db::now()]);
            Db::mustInsert($db,Db::table('employee_roles'),['company_id'=>$companyId,'employee_id'=>$employeeId,'role_id'=>$roleId,'active'=>1,'assigned_by'=>$employeeId,'assigned_at'=>Db::now()]);
            Db::mustInsert($db,Db::table('employee_branch_authorities'),['company_id'=>$companyId,'employee_id'=>$employeeId,'branch_id'=>$branchId,'active'=>1,'granted_by'=>$employeeId,'valid_from'=>Db::now(),'valid_until'=>null]);

            $accounts=[
                ['CASH','Cash','asset','cash'],['BANK_MAIN','Main Bank','asset','bank'],['UPI_MAIN','UPI','asset','upi'],
                ['INVENTORY','Inventory','asset','inventory'],['INTER_BRANCH_CLEARING','Inter-branch Transfer Clearing','asset','inter_branch_clearing'],['AR','Accounts Receivable','asset','receivable'],
                ['AP','Accounts Payable','liability','payable'],['PAYROLL_PAYABLE','Payroll Payable','liability','payroll_payable'],
                ['SALES','Sales','income','sales'],['COGS','Cost of Goods Sold','expense','cogs'],
                ['STOCK_VARIANCE','Stock Variance','expense','stock_variance'],['PAYROLL_EXPENSE','Payroll Expense','expense','payroll'],
                ['OFFICE_EXPENSE','Office Expense','expense','office'],
            ];
            $accountIds=[];
            foreach($accounts as[$code,$name,$type,$subtype]){Db::mustInsert($db,Db::table('accounts'),['company_id'=>$companyId,'code'=>$code,'name'=>$name,'type'=>$type,'subtype'=>$subtype,'active'=>1]);$accountIds[$code]=(int)$db->insert_id;if(!$accountIds[$code])throw new DomainException('Canonical account initialization failed: '.$code,'setup_account_failed',500);}
            Db::mustInsert($db,Db::table('expense_heads'),['company_id'=>$companyId,'code'=>'OFFICE_GENERAL','name'=>'Office General Expense','expense_account_id'=>$accountIds['OFFICE_EXPENSE'],'active'=>1]);

            $actor=new Actor($uid,$employeeId,$companyId,$branchId,[$branchId],$caps,'SYSADMIN');
            Audit::add($actor,'setup.initialize','company',$companyId,['branch_id'=>$branchId,'employee_id'=>$employeeId]);
            return ['initialized'=>true,'company_id'=>$companyId,'branch_id'=>$branchId,'employee_id'=>$employeeId,'role_id'=>$roleId];
        });}finally{$db->get_var("SELECT RELEASE_LOCK('eh7_initial_setup')");}
    }
}
