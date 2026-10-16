<?php
namespace ExcelHerbal\ERP7\Organization;

use ExcelHerbal\ERP7\Core\Input;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\DesignationDefaults;
use ExcelHerbal\ERP7\Security\Guard;
use ExcelHerbal\ERP7\Security\HierarchyScope;

final class HrLifecycleService {
    private const CANDIDATE_OPEN=['registered','selected'];
    private const CANDIDATE_STATUSES=['registered','selected','rejected','joined','no_show','cancelled'];
    private const SEPARATION_STATUSES=['submitted','approved','rejected','completed'];
    private const MAX_DOCUMENT_BYTES=10485760;
    private const DOCUMENT_EXTENSIONS=['pdf','jpg','jpeg','png','webp'];

    public static function employeeChoices(Actor $a,int $branch,string $purpose):array {
        $purpose=strtolower(trim($purpose));
        if($purpose==='reporting'){
            Guard::branch($a,$branch,Capabilities::HR_REVIEW);
            $ids=HierarchyScope::visibleEmployeeIds($a,$branch);
        }elseif($purpose==='separation'){
            Guard::branch($a,$branch,Capabilities::HR_MANAGE);
            $ids=array_values(array_filter(HierarchyScope::manageableEmployeeIds($a),fn($id)=>(int)$id!==$a->employeeId));
        }else{
            throw new DomainException('HR employee-choice purpose is invalid.','parameter_invalid',422);
        }
        $ids=array_values(array_unique(array_filter(array_map('intval',$ids),fn($id)=>$id>0)));
        if(!$ids)return[];
        $db=Db::wpdb();$sql="SELECT id,employee_code,full_name,designation_code FROM ".Db::table('employees')." WHERE company_id=%d AND assigned_branch_id=%d AND status='active' AND id IN (".implode(',',array_map('intval',$ids)).") ORDER BY full_name,id";
        return(array)$db->get_results($db->prepare($sql,$a->companyId,$branch),ARRAY_A);
    }

    public static function candidates(Actor $a,?int $branchId,string $status='open'):array {
        Guard::any($a,[Capabilities::HR_VIEW,Capabilities::HR_MANAGE,Capabilities::HR_REVIEW]);
        $db=Db::wpdb();$status=strtolower(trim($status))?:'open';
        if($status!=='open'&&$status!=='all'&&!in_array($status,self::CANDIDATE_STATUSES,true))throw new DomainException('Candidate status filter is invalid.','candidate_status_invalid',422);
        $branchIds=$branchId!==null?[$branchId]:array_values(array_unique(array_map('intval',$a->branchIds)));
        if($branchId!==null)Guard::branchAny($a,$branchId,[Capabilities::HR_VIEW,Capabilities::HR_MANAGE,Capabilities::HR_REVIEW]);
        if(!$branchIds)return[];
        $ids=implode(',',array_map('intval',$branchIds));
        $where=$status==='all'?'1=1':($status==='open'?"c.status IN ('registered','selected')":$db->prepare('c.status=%s',$status));
        $rows=(array)$db->get_results($db->prepare(
            "SELECT c.*,b.code branch_code,b.name branch_name,d.name designation_name,e.employee_code joined_employee_code FROM ".Db::table('hr_candidates')." c JOIN ".Db::table('branches')." b ON b.id=c.branch_id AND b.company_id=c.company_id LEFT JOIN ".Db::table('designations')." d ON d.company_id=c.company_id AND d.code=c.proposed_designation_code LEFT JOIN ".Db::table('employees')." e ON e.id=c.joined_employee_id AND e.company_id=c.company_id WHERE c.company_id=%d AND c.branch_id IN ({$ids}) AND {$where} ORDER BY CASE c.status WHEN 'registered' THEN 0 WHEN 'selected' THEN 1 ELSE 2 END,c.id DESC",
            $a->companyId
        ),ARRAY_A);
        if(!$a->can(Capabilities::SALARY_VIEW)&&!$a->can(Capabilities::SALARY_MANAGE)&&!$a->can(Capabilities::SALARY_APPROVE)){
            foreach($rows as&$row)unset($row['offered_monthly_salary']);unset($row);
        }
        return $rows;
    }

    public static function candidate(Actor $a,int $candidateId):array {
        $c=self::candidateRowAny($a,$candidateId,[Capabilities::HR_VIEW,Capabilities::HR_MANAGE,Capabilities::HR_REVIEW]);
        if(!$a->can(Capabilities::SALARY_VIEW)&&!$a->can(Capabilities::SALARY_MANAGE)&&!$a->can(Capabilities::SALARY_APPROVE))unset($c['offered_monthly_salary']);
        $c['documents']=($a->can(Capabilities::HR_DOCUMENT_VIEW)||$a->can(Capabilities::HR_DOCUMENT_MANAGE))?self::candidateDocuments($a,$candidateId):[];
        return$c;
    }

    public static function createCandidate(Actor $a,array $data):array {
        $branch=(int)($data['branch_id']??0);Guard::branch($a,$branch,Capabilities::HR_MANAGE);
        $name=trim((string)($data['full_name']??''));$mobile=self::normaliseMobile((string)($data['mobile']??''));$email=trim((string)($data['email']??''));$designation=strtoupper(trim((string)($data['proposed_designation_code']??'')));
        if($name===''||strlen($name)>190)throw new DomainException('Candidate full name is required.','candidate_fields_invalid',422);
        if($mobile===''&&$email==='')throw new DomainException('Candidate mobile or email is required.','candidate_contact_required',422);
        if($mobile!==''&&(strlen($mobile)<8||strlen($mobile)>15))throw new DomainException('Candidate mobile must contain 8 to 15 digits.','mobile_invalid',422);
        if($email!==''&&!is_email($email))throw new DomainException('Valid candidate email is required.','email_invalid',422);
        if($designation==='')throw new DomainException('Proposed designation is required.','designation_invalid',422);
        $db=Db::wpdb();$valid=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('designations')." WHERE company_id=%d AND code=%s AND status='active'",$a->companyId,$designation));if(!$valid)throw new DomainException('Active proposed designation not found.','designation_invalid',422);if(DesignationDefaults::requiresAccessManagement($designation))Guard::cap($a,Capabilities::ACCESS_MANAGE);
        if($mobile!==''){$dup=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('hr_candidates')." WHERE company_id=%d AND mobile=%s AND status IN ('registered','selected')",$a->companyId,$mobile));if($dup)throw new DomainException('An open candidate already uses this mobile number.','candidate_duplicate',409);}
        if($email!==''){$dup=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('hr_candidates')." WHERE company_id=%d AND email=%s AND status IN ('registered','selected')",$a->companyId,$email));if($dup)throw new DomainException('An open candidate already uses this email address.','candidate_duplicate',409);}
        $salaryRaw=$data['offered_monthly_salary']??0;if(array_key_exists('offered_monthly_salary',$data)){Guard::cap($a,Capabilities::SALARY_MANAGE);if(!is_numeric($salaryRaw)||!is_finite((float)$salaryRaw)||(float)$salaryRaw<0)throw new DomainException('Offered salary must be a valid non-negative amount.','candidate_fields_invalid',422);}$salary=round((float)$salaryRaw,2);$source=trim((string)($data['source']??''));$notes=trim((string)($data['notes']??''));
        return Transaction::run(function()use($a,$branch,$name,$mobile,$email,$designation,$salary,$source,$notes){
            $db=Db::wpdb();$t=Db::table('hr_candidates');$now=Db::now();
            Db::mustInsert($db,$t,['company_id'=>$a->companyId,'candidate_code'=>null,'branch_id'=>$branch,'full_name'=>$name,'mobile'=>$mobile?:null,'email'=>$email?:null,'proposed_employee_code'=>null,'proposed_designation_code'=>$designation,'offered_monthly_salary'=>$salary,'expected_joining_date'=>null,'status'=>'registered','source'=>$source?:null,'notes'=>$notes?:null,'created_by'=>$a->employeeId,'created_at'=>$now,'updated_at'=>$now]);
            $id=(int)$db->insert_id;$code='CAND-'.substr(Db::today(),0,4).'-'.str_pad((string)$id,5,'0',STR_PAD_LEFT);Db::mustUpdate($db,$t,['candidate_code'=>$code],['id'=>$id]);
            Audit::add($a,'hr.candidate.create','hr_candidate',$id,['branch_id'=>$branch,'candidate_code'=>$code,'designation_code'=>$designation]);
            return['id'=>$id,'candidate_code'=>$code,'branch_id'=>$branch,'full_name'=>$name,'status'=>'registered'];
        });
    }

    public static function reviewCandidate(Actor $a,int $candidateId,array $data):array {
        $decision=strtolower(trim((string)($data['decision']??'')));$reason=trim((string)($data['reason']??''));if(!in_array($decision,['selected','rejected'],true))throw new DomainException('Candidate review decision must be selected or rejected.','candidate_decision_invalid',422);if(strlen($reason)<5)throw new DomainException('Candidate review reason must be at least 5 characters.','candidate_review_reason_required',422);
        return Transaction::run(function()use($a,$candidateId,$data,$decision,$reason){
            $db=Db::wpdb();$t=Db::table('hr_candidates');$c=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d FOR UPDATE",$candidateId,$a->companyId),ARRAY_A);if(!$c)throw new DomainException('Candidate not found.','candidate_not_found',404);Guard::branch($a,(int)$c['branch_id'],Capabilities::HR_REVIEW);if($c['status']!=='registered')throw new DomainException('Only registered candidates can be reviewed.','candidate_state_invalid',409);if((int)$c['created_by']===$a->employeeId)throw new DomainException('Maker-checker: candidate creator cannot review the same candidate.','maker_checker_violation',409);
            $chg=['status'=>$decision,'reviewed_by'=>$a->employeeId,'reviewed_at'=>Db::now(),'review_reason'=>$reason,'updated_at'=>Db::now()];
            if($decision==='selected'){
                $employeeCode=strtoupper(trim((string)($data['employee_code']??'')));if($employeeCode===''||strlen($employeeCode)>50)throw new DomainException('Employee code is required when selecting a candidate.','employee_code_required',422);
                $join=Input::date((string)($data['expected_joining_date']??''),'Expected joining date');
                $designation=strtoupper(trim((string)($data['proposed_designation_code']??$c['proposed_designation_code'])));$valid=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('designations')." WHERE company_id=%d AND code=%s AND status='active'",$a->companyId,$designation));if(!$valid)throw new DomainException('Active proposed designation not found.','designation_invalid',422);if(DesignationDefaults::requiresAccessManagement($designation))Guard::cap($a,Capabilities::ACCESS_MANAGE);
                $employeeDup=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('employees')." WHERE company_id=%d AND employee_code=%s",$a->companyId,$employeeCode));if($employeeDup)throw new DomainException('Employee code already exists.','employee_duplicate',409);
                $candidateDup=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$t} WHERE company_id=%d AND proposed_employee_code=%s AND id<>%d AND status='selected'",$a->companyId,$employeeCode,$candidateId));if($candidateDup)throw new DomainException('Employee code is reserved by another selected candidate.','employee_duplicate',409);
                $chg['proposed_employee_code']=$employeeCode;$chg['expected_joining_date']=$join;$chg['proposed_designation_code']=$designation;
                if(array_key_exists('offered_monthly_salary',$data)){Guard::cap($a,Capabilities::SALARY_MANAGE);$salaryRaw=$data['offered_monthly_salary'];if(!is_numeric($salaryRaw)||!is_finite((float)$salaryRaw)||(float)$salaryRaw<0)throw new DomainException('Offered salary must be a valid non-negative amount.','candidate_fields_invalid',422);$chg['offered_monthly_salary']=round((float)$salaryRaw,2);}
            }
            Db::mustUpdate($db,$t,$chg,['id'=>$candidateId,'company_id'=>$a->companyId]);Audit::add($a,'hr.candidate.review','hr_candidate',$candidateId,['branch_id'=>(int)$c['branch_id'],'decision'=>$decision,'reason'=>$reason]);return['id'=>$candidateId,'status'=>$decision,'employee_code'=>$chg['proposed_employee_code']??null,'expected_joining_date'=>$chg['expected_joining_date']??null];
        });
    }

    public static function confirmJoining(Actor $a,int $candidateId,array $data):array {
        return Transaction::run(function()use($a,$candidateId,$data){
            $db=Db::wpdb();$t=Db::table('hr_candidates');$c=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d FOR UPDATE",$candidateId,$a->companyId),ARRAY_A);if(!$c)throw new DomainException('Candidate not found.','candidate_not_found',404);Guard::branch($a,(int)$c['branch_id'],Capabilities::HR_REVIEW);if($c['status']!=='selected')throw new DomainException('Only selected candidates can be joined.','candidate_state_invalid',409);if((int)($c['joined_employee_id']??0)>0)throw new DomainException('Candidate is already linked to an employee.','candidate_already_joined',409);
            $joining=Input::date((string)($data['joining_date']??''),'Joining date');if($joining>Db::today())throw new DomainException('Joining confirmation cannot use a future date.','joining_date_invalid',422);
            $branch=(int)($data['branch_id']??$c['branch_id']);Guard::branch($a,$branch,Capabilities::HR_REVIEW);
            $employeeCode=strtoupper(trim((string)($data['employee_code']??$c['proposed_employee_code'])));if($employeeCode==='')throw new DomainException('Employee code is required.','employee_code_required',422);
            $designation=strtoupper(trim((string)($data['designation_code']??$c['proposed_designation_code'])));if(DesignationDefaults::requiresAccessManagement($designation))Guard::cap($a,Capabilities::ACCESS_MANAGE);$reserved=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$t} WHERE company_id=%d AND proposed_employee_code=%s AND id<>%d AND status='selected'",$a->companyId,$employeeCode,$candidateId));if($reserved)throw new DomainException('Employee code is reserved by another selected candidate.','employee_duplicate',409);$salaryRaw=array_key_exists('monthly_salary',$data)?$data['monthly_salary']:$c['offered_monthly_salary'];if(array_key_exists('monthly_salary',$data))Guard::cap($a,Capabilities::SALARY_MANAGE);if(!is_numeric($salaryRaw)||!is_finite((float)$salaryRaw)||(float)$salaryRaw<0)throw new DomainException('Monthly salary must be a valid non-negative amount.','employee_fields_invalid',422);$salary=(float)$salaryRaw;
            $roleIds=(array)($data['role_ids']??[]);if($roleIds)throw new DomainException('Joining confirmation cannot assign security roles. Use Access Management after joining.','role_assignment_forbidden',403);
            $employeeData=['assigned_branch_id'=>$branch,'employee_code'=>$employeeCode,'full_name'=>(string)$c['full_name'],'designation_code'=>$designation,'mobile'=>(string)($c['mobile']??''),'email'=>(string)($c['email']??''),'monthly_salary'=>round($salary,2),'joining_date'=>$joining,'reporting_employee_id'=>$data['reporting_employee_id']??null,'role_ids'=>[],'provision_login'=>false];
            $employee=OrganizationService::createEmployee($a,$employeeData,Capabilities::HR_REVIEW);$employeeId=(int)$employee['id'];
            Db::mustUpdate($db,$t,['branch_id'=>$branch,'proposed_employee_code'=>$employeeCode,'proposed_designation_code'=>$designation,'status'=>'joined','joined_employee_id'=>$employeeId,'joined_at'=>Db::now(),'updated_at'=>Db::now()],['id'=>$candidateId,'company_id'=>$a->companyId]);Audit::add($a,'hr.candidate.joining_confirmed','hr_candidate',$candidateId,['employee_id'=>$employeeId,'branch_id'=>$branch,'joining_date'=>$joining]);return['id'=>$candidateId,'status'=>'joined','employee_id'=>$employeeId,'employee_code'=>$employeeCode,'login_enabled'=>false,'credentials_pending'=>true];
        });
    }

    public static function issueCandidateCredentials(Actor $a,int $candidateId,array $data):array {
        $password=(string)($data['password']??'');if(trim($password)==='')throw new DomainException('Password is required.','password_required',422);
        return Transaction::run(function()use($a,$candidateId,$password){
            $db=Db::wpdb();$t=Db::table('hr_candidates');$c=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d FOR UPDATE",$candidateId,$a->companyId),ARRAY_A);if(!$c)throw new DomainException('Candidate not found.','candidate_not_found',404);Guard::branch($a,(int)$c['branch_id'],Capabilities::HR_REVIEW);if($c['status']!=='joined'||(int)($c['joined_employee_id']??0)<1)throw new DomainException('Candidate must be joined before credentials can be issued.','candidate_state_invalid',409);if(!empty($c['credentials_issued_at']))throw new DomainException('Candidate credentials were already issued. Use employee credential reset if needed.','candidate_credentials_already_issued',409);
            $result=OrganizationService::setEmployeeCredentials($a,(int)$c['joined_employee_id'],['password'=>$password],Capabilities::HR_REVIEW);Db::mustUpdate($db,$t,['credentials_issued_by'=>$a->employeeId,'credentials_issued_at'=>Db::now(),'updated_at'=>Db::now()],['id'=>$candidateId,'company_id'=>$a->companyId]);Audit::add($a,'hr.candidate.credentials_issued','hr_candidate',$candidateId,['employee_id'=>(int)$c['joined_employee_id']]);return['id'=>$candidateId,'employee_id'=>(int)$c['joined_employee_id'],'credentials_issued'=>true]+$result;
        });
    }

    public static function markNoShow(Actor $a,int $candidateId,string $reason):array {
        $reason=trim($reason);if(strlen($reason)<5)throw new DomainException('No-show reason must be at least 5 characters.','candidate_no_show_reason_required',422);
        return Transaction::run(function()use($a,$candidateId,$reason){$db=Db::wpdb();$t=Db::table('hr_candidates');$c=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d FOR UPDATE",$candidateId,$a->companyId),ARRAY_A);if(!$c)throw new DomainException('Candidate not found.','candidate_not_found',404);Guard::branch($a,(int)$c['branch_id'],Capabilities::HR_MANAGE);if($c['status']!=='selected')throw new DomainException('Only selected candidates can be marked no-show.','candidate_state_invalid',409);$expected=(string)($c['expected_joining_date']??'');if($expected===''||$expected>Db::today())throw new DomainException('No-show can be marked only on or after the expected joining date.','candidate_no_show_early',409);Db::mustUpdate($db,$t,['status'=>'no_show','no_show_reason'=>$reason,'no_show_at'=>Db::now(),'updated_at'=>Db::now()],['id'=>$candidateId,'company_id'=>$a->companyId]);Audit::add($a,'hr.candidate.no_show','hr_candidate',$candidateId,['branch_id'=>(int)$c['branch_id'],'reason'=>$reason]);return['id'=>$candidateId,'status'=>'no_show'];});
    }

    public static function candidateDocuments(Actor $a,int $candidateId):array {
        $readCap=$a->can(Capabilities::HR_DOCUMENT_VIEW)?Capabilities::HR_DOCUMENT_VIEW:Capabilities::HR_DOCUMENT_MANAGE;
        $c=self::candidateRow($a,$candidateId,$readCap);$db=Db::wpdb();$rows=(array)$db->get_results($db->prepare("SELECT id,attachment_id,private_file_id,document_type,title,status,uploaded_by,created_at,updated_at FROM ".Db::table('hr_candidate_documents')." WHERE company_id=%d AND candidate_id=%d AND status='active' ORDER BY id DESC",$a->companyId,$candidateId),ARRAY_A);foreach($rows as&$row){$row['url']=!empty($row['private_file_id'])?DocumentVault::url('candidate',$candidateId,(int)$row['id']):null;$row['requires_auth']=true;$row['migration_required']=empty($row['private_file_id']);}unset($row);return$rows;
    }

    public static function uploadCandidateDocument(Actor $a,int $candidateId,array $data):array {
        $c=self::candidateRow($a,$candidateId,Capabilities::HR_DOCUMENT_MANAGE);$type=trim((string)($data['document_type']??''));$title=trim((string)($data['title']??''));
        if($type===''||$title===''||strlen($type)>60||strlen($title)>190)throw new DomainException('Valid document type and title are required.','candidate_document_invalid',422);
        return Transaction::run(function()use($a,$candidateId,$c,$type,$title){$file=DocumentVault::storeUpload();$db=Db::wpdb();Db::mustInsert($db,Db::table('hr_candidate_documents'),['company_id'=>$a->companyId,'candidate_id'=>$candidateId,'attachment_id'=>0,'private_file_id'=>$file,'document_type'=>$type,'title'=>$title,'status'=>'active','uploaded_by'=>$a->employeeId,'created_at'=>Db::now()]);$id=(int)$db->insert_id;Audit::add($a,'hr.candidate.document_upload','hr_candidate_document',$id,['candidate_id'=>$candidateId,'branch_id'=>(int)$c['branch_id']]);return ['id'=>$id,'candidate_id'=>$candidateId,'attachment_id'=>0,'status'=>'active','url'=>DocumentVault::url('candidate',$candidateId,$id),'requires_auth'=>true];});
    }

    public static function deactivateCandidateDocument(Actor $a,int $candidateId,int $documentId):array {
        self::candidateRow($a,$candidateId,Capabilities::HR_DOCUMENT_MANAGE);return Transaction::run(function()use($a,$candidateId,$documentId){$db=Db::wpdb();$t=Db::table('hr_candidate_documents');$r=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND candidate_id=%d AND company_id=%d FOR UPDATE",$documentId,$candidateId,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Candidate document not found.','candidate_document_not_found',404);if($r['status']==='inactive')return['id'=>$documentId,'status'=>'inactive','unchanged'=>true];Db::mustUpdate($db,$t,['status'=>'inactive','updated_at'=>Db::now()],['id'=>$documentId]);Audit::add($a,'hr.candidate.document_deactivate','hr_candidate_document',$documentId,['candidate_id'=>$candidateId]);return['id'=>$documentId,'status'=>'inactive','unchanged'=>false];});
    }

    public static function separations(Actor $a,?int $branchId,string $status='open'):array {
        Guard::any($a,[Capabilities::HR_VIEW,Capabilities::HR_MANAGE,Capabilities::HR_REVIEW]);$db=Db::wpdb();$status=strtolower(trim($status))?:'open';if($status!=='open'&&$status!=='all'&&!in_array($status,self::SEPARATION_STATUSES,true))throw new DomainException('Separation status filter is invalid.','separation_status_invalid',422);$branchIds=$branchId!==null?[$branchId]:array_values(array_unique(array_map('intval',$a->branchIds)));if($branchId!==null)Guard::branchAny($a,$branchId,[Capabilities::HR_VIEW,Capabilities::HR_MANAGE,Capabilities::HR_REVIEW]);if(!$branchIds)return[];$ids=implode(',',array_map('intval',$branchIds));$where=$status==='all'?'1=1':($status==='open'?"s.status IN ('submitted','approved')":$db->prepare('s.status=%s',$status));return(array)$db->get_results($db->prepare("SELECT s.*,e.employee_code,e.full_name,e.designation_code FROM ".Db::table('hr_separations')." s JOIN ".Db::table('employees')." e ON e.id=s.employee_id AND e.company_id=s.company_id WHERE s.company_id=%d AND s.branch_id IN ({$ids}) AND {$where} ORDER BY s.id DESC",$a->companyId),ARRAY_A);
    }

    public static function initiateSeparation(Actor $a,int $employeeId,array $data):array {
        $date=Input::date((string)($data['separation_date']??''),'Separation date');$reason=trim((string)($data['reason']??''));if(strlen($reason)<5)throw new DomainException('Separation reason must be at least 5 characters.','separation_reason_required',422);if($employeeId===$a->employeeId)throw new DomainException('You cannot initiate your own ERP separation through management workflow.','self_offboarding_not_allowed',409);
        return Transaction::run(function()use($a,$employeeId,$date,$reason){$db=Db::wpdb();$e=$db->get_row($db->prepare("SELECT id,assigned_branch_id,joining_date,status FROM ".Db::table('employees')." WHERE id=%d AND company_id=%d FOR UPDATE",$employeeId,$a->companyId),ARRAY_A);if(!$e||$e['status']!=='active')throw new DomainException('Active employee not found.','employee_not_found',404);Guard::branch($a,(int)$e['assigned_branch_id'],Capabilities::HR_MANAGE);HierarchyScope::assertCanManageEmployeeAccess($a,$employeeId);if(!empty($e['joining_date'])&&$date<(string)$e['joining_date'])throw new DomainException('Separation date cannot be before joining date.','separation_date_invalid',422);$open=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('hr_separations')." WHERE company_id=%d AND employee_id=%d AND status IN ('submitted','approved')",$a->companyId,$employeeId));if($open)throw new DomainException('Employee already has an open separation request.','separation_duplicate',409);Db::mustInsert($db,Db::table('hr_separations'),['company_id'=>$a->companyId,'employee_id'=>$employeeId,'branch_id'=>(int)$e['assigned_branch_id'],'separation_date'=>$date,'reason'=>$reason,'status'=>'submitted','initiated_by'=>$a->employeeId,'initiated_at'=>Db::now()]);$id=(int)$db->insert_id;$preflight=OrganizationService::offboardingPreflight($a,$employeeId,min($date,Db::today()),Capabilities::HR_MANAGE);Audit::add($a,'hr.separation.initiate','hr_separation',$id,['employee_id'=>$employeeId,'branch_id'=>(int)$e['assigned_branch_id'],'separation_date'=>$date,'reason'=>$reason]);return['id'=>$id,'employee_id'=>$employeeId,'status'=>'submitted','separation_date'=>$date,'current_blockers'=>$preflight['blockers']??[]];});
    }

    public static function reviewSeparation(Actor $a,int $separationId,array $data):array {
        $approve=self::boolValue($data['approve']??null,'approve');$reason=trim((string)($data['reason']??''));if(strlen($reason)<5)throw new DomainException('Separation review reason must be at least 5 characters.','separation_review_reason_required',422);return Transaction::run(function()use($a,$separationId,$approve,$reason){$db=Db::wpdb();$t=Db::table('hr_separations');$s=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d FOR UPDATE",$separationId,$a->companyId),ARRAY_A);if(!$s)throw new DomainException('Separation request not found.','separation_not_found',404);Guard::branch($a,(int)$s['branch_id'],Capabilities::HR_REVIEW);if($s['status']!=='submitted')throw new DomainException('Only submitted separation requests can be reviewed.','separation_state_invalid',409);if((int)$s['initiated_by']===$a->employeeId)throw new DomainException('Maker-checker: separation initiator cannot review the same request.','maker_checker_violation',409);$status=$approve?'approved':'rejected';Db::mustUpdate($db,$t,['status'=>$status,'reviewed_by'=>$a->employeeId,'reviewed_at'=>Db::now(),'review_reason'=>$reason],['id'=>$separationId,'company_id'=>$a->companyId]);Audit::add($a,'hr.separation.review','hr_separation',$separationId,['employee_id'=>(int)$s['employee_id'],'decision'=>$status,'reason'=>$reason]);$blockers=[];if($approve&&(string)$s['separation_date']<=Db::today()){$preflight=OrganizationService::offboardingPreflight($a,(int)$s['employee_id'],(string)$s['separation_date'],Capabilities::HR_REVIEW);$blockers=$preflight['blockers']??[];}return['id'=>$separationId,'status'=>$status,'separation_date'=>(string)$s['separation_date'],'completion_due'=>$approve&&(string)$s['separation_date']<=Db::today(),'current_blockers'=>$blockers];});
    }

    public static function completeSeparation(Actor $a,int $separationId):array {
        return Transaction::run(function()use($a,$separationId){$db=Db::wpdb();$t=Db::table('hr_separations');$s=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d FOR UPDATE",$separationId,$a->companyId),ARRAY_A);if(!$s)throw new DomainException('Separation request not found.','separation_not_found',404);Guard::branch($a,(int)$s['branch_id'],Capabilities::HR_REVIEW);if($s['status']!=='approved')throw new DomainException('Only approved separation requests can be completed.','separation_state_invalid',409);if((string)$s['separation_date']>Db::today())throw new DomainException('Separation cannot complete before the approved separation date.','separation_date_not_due',409);$preflight=OrganizationService::offboardingPreflight($a,(int)$s['employee_id'],(string)$s['separation_date'],Capabilities::HR_REVIEW);if(!empty($preflight['blockers']))throw new DomainException('Separation still has unresolved offboarding blockers.','employee_offboarding_blocked',409);$result=OrganizationService::offboardEmployee($a,(int)$s['employee_id'],(string)$s['separation_date'],(string)$s['reason'],Capabilities::HR_REVIEW);Db::mustUpdate($db,$t,['status'=>'completed','completed_by'=>$a->employeeId,'completed_at'=>Db::now()],['id'=>$separationId,'company_id'=>$a->companyId]);Audit::add($a,'hr.separation.complete','hr_separation',$separationId,['employee_id'=>(int)$s['employee_id'],'separation_date'=>(string)$s['separation_date']]);return['id'=>$separationId,'status'=>'completed','employee'=>$result];});
    }

    private static function candidateRowAny(Actor $a,int $candidateId,array $capabilities):array {$db=Db::wpdb();$c=$db->get_row($db->prepare("SELECT * FROM ".Db::table('hr_candidates')." WHERE id=%d AND company_id=%d",$candidateId,$a->companyId),ARRAY_A);if(!$c)throw new DomainException('Candidate not found.','candidate_not_found',404);Guard::branchAny($a,(int)$c['branch_id'],$capabilities);return$c;}
    private static function candidateRow(Actor $a,int $candidateId,string $capability):array {$db=Db::wpdb();$c=$db->get_row($db->prepare("SELECT * FROM ".Db::table('hr_candidates')." WHERE id=%d AND company_id=%d",$candidateId,$a->companyId),ARRAY_A);if(!$c)throw new DomainException('Candidate not found.','candidate_not_found',404);Guard::branch($a,(int)$c['branch_id'],$capability);return$c;}
    private static function normaliseMobile(string $mobile):string{return preg_replace('/\D+/','',$mobile)?:'';}
    private static function boolValue(mixed $v,string $field):bool{if(is_bool($v))return$v;if(is_int($v)&&($v===0||$v===1))return$v===1;if(is_string($v)){if(in_array(strtolower(trim($v)),['true','1'],true))return true;if(in_array(strtolower(trim($v)),['false','0'],true))return false;}throw new DomainException($field.' must be a boolean.','parameter_invalid',422);}
}
