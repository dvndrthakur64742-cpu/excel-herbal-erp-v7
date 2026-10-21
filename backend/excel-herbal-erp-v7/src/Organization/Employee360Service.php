<?php
/**
 * Employee 360 — canonical READ-ONLY V7 register projection.
 * Does NOT alter the employee dashboard, grant new caps, infer missing cash postings,
 * or mix points with salary/financial ledger amounts.
 */
namespace ExcelHerbal\ERP7\Organization;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\HierarchyScope;

interface Employee360Reader {
    public function employee(int $company, int $id): ?array;
    public function sales(int $company, int $id, string $from, string $to, array $branches): array;
    public function performance(int $company, int $id, string $from, string $to, array $branches): array;
    public function attendance(int $company, int $id, string $from, string $to, array $branches): array;
    public function stock(int $company, int $id, array $branches): array;
    public function ledger(int $company, int $id, string $from, string $to, array $branches): array;
}

final class Employee360Service {
    /** Shared access gate for the profile and its detailed registers. */
    public static function authorizeTarget(Actor $a,int $employeeId,?Employee360Reader $reader=null):array {
        if ($employeeId<1)throw new DomainException('Valid employee ID required.','employee_id_invalid',422);
        $reader=$reader??new Employee360WpReader();
        $employee=$reader->employee($a->companyId,$employeeId);
        if (!$employee || (int)($employee['id']??0)!==$employeeId || (int)($employee['company_id']??0)!==$a->companyId)
            throw new DomainException('Employee not found.','employee_not_found',404);
        $self=$a->employeeId===$employeeId;
        if(!$self){
            if(!$a->can(Capabilities::EMP_VIEW))throw new DomainException('Permission denied.','permission_denied',403);
            HierarchyScope::assertCanViewEmployee($a,$employeeId);
            if(!$a->hasBranch((int)$employee['assigned_branch_id']))throw new DomainException('Branch is outside effective authority.','branch_forbidden',403);
        }
        $branches=$self?[]:array_values(array_unique(array_filter(array_map('intval',$a->branchIds),fn($id)=>$id>0)));
        if(!$self && !$branches)throw new DomainException('No authorized branch.','branch_forbidden',403);
        return ['employee'=>$employee,'branches'=>$branches,'self'=>$self];
    }

    public static function validatePeriod(string $from,string $to):void {
        foreach(['from'=>$from,'to'=>$to] as $name=>$date){
            $d=\DateTimeImmutable::createFromFormat('!Y-m-d',$date);
            if(!$d||$d->format('Y-m-d')!==$date)throw new DomainException('Invalid '.$name.' date.','date_invalid',422);
        }
        $start=new \DateTimeImmutable($from);$end=new \DateTimeImmutable($to);
        if($end<$start||$start->diff($end)->days>366)throw new DomainException('Invalid period (maximum 366 days).','period_invalid',422);
    }

    /** No silent overwrites or out-of-period monthly figures. */
    private static function validMonth(mixed $raw,string $from,string $to):string {
        if(!is_string($raw)||!preg_match('/^[0-9]{4}-(0[1-9]|1[0-2])$/D',$raw)
            ||$raw<substr($from,0,7)||$raw>substr($to,0,7))
            throw new DomainException('Invalid employee monthly reporting range.','projection_corrupt',500);
        return $raw;
    }
    /** Exact fixed-point monthly INR / incentive point values. */
    private static function decimal(mixed $raw,bool $signed=false):string {
        if(!is_int($raw)&&!is_string($raw))
            throw new DomainException('Employee metric numeric source invalid.','projection_corrupt',500);
        $v=(string)$raw;
        $pattern=$signed?'/^-?(0|[1-9][0-9]{0,15})(?:\.([0-9]{1,2}))?$/D'
                        :'/^(0|[1-9][0-9]{0,15})(?:\.([0-9]{1,2}))?$/D';
        if(!preg_match($pattern,$v,$m))
            throw new DomainException('Employee metric precision invalid.','projection_corrupt',500);
        return (str_starts_with($v,'-')?'-':'').$m[1].'.'.str_pad($m[2]??'',2,'0',STR_PAD_RIGHT);
    }

    public static function view(Actor $a, int $employeeId, string $from, string $to, ?Employee360Reader $reader=null): array {
        self::validatePeriod($from,$to);
        $scope=self::authorizeTarget($a,$employeeId,$reader);
        $reader=$reader??new Employee360WpReader();
        $employee=$scope['employee'];
        $branches=$scope['branches'];
        $sales=$reader->sales($a->companyId,$employeeId,$from,$to,$branches);
        $points=$reader->performance($a->companyId,$employeeId,$from,$to,$branches);
        $attendance=$reader->attendance($a->companyId,$employeeId,$from,$to,$branches);
        $stock=$reader->stock($a->companyId,$employeeId,$branches);
        if(!is_array($sales)||!is_array($points)||!is_array($attendance)||!is_array($stock)
           ||count($sales)>14||count($points)>14||count($attendance)>367||count($stock)>1000)
            throw new DomainException('Employee profile source incomplete or excessive.','projection_corrupt',500);
        foreach($stock as $item){
            if(!is_array($item)||(int)($item['branch_id']??0)<1
                ||(int)($item['product_id']??0)<1
                ||(!$scope['self']&&!in_array((int)$item['branch_id'],$branches,true)))
                throw new DomainException('Employee stock row exceeded branch authority.','projection_corrupt',500);
        }
        $months=[];$seenSales=[];$seenPoints=[];$seenDays=[];
        foreach($sales as $r) {
            $month=self::validMonth(is_array($r)?($r['month']??null):null,$from,$to);
            if(isset($seenSales[$month]))throw new DomainException('Duplicate employee sales month.','projection_corrupt',500);
            $seenSales[$month]=true;
            $months[$month]=($months[$month]??['month'=>$month,'sales_amount'=>'0.00','points'=>'0.00','days_present'=>0]);
            $months[$month]['sales_amount']=self::decimal($r['sale_amount']??null);
        }
        foreach($points as $r) {
            $month=self::validMonth(is_array($r)?($r['month']??null):null,$from,$to);
            if(isset($seenPoints[$month]))throw new DomainException('Duplicate employee points month.','projection_corrupt',500);
            $seenPoints[$month]=true;
            $months[$month]=($months[$month]??['month'=>$month,'sales_amount'=>'0.00','points'=>'0.00','days_present'=>0]);
            $months[$month]['points']=self::decimal($r['points']??null,true);
        }
        foreach($attendance as $r) {
            $date=is_array($r)?($r['business_date']??null):null;
            $parsed=is_string($date)?\DateTimeImmutable::createFromFormat('!Y-m-d',$date):false;
            if(!$parsed||$parsed->format('Y-m-d')!==$date||$date<$from||$date>$to
                ||isset($seenDays[$date])||(int)($r['branch_id']??0)<1
                ||(!$scope['self']&&!in_array((int)$r['branch_id'],$branches,true)))
                throw new DomainException('Employee attendance date or branch invalid.','projection_corrupt',500);
            $seenDays[$date]=true;
            $month=substr($date,0,7);
            $months[$month]=($months[$month]??['month'=>$month,'sales_amount'=>'0.00','points'=>'0.00','days_present'=>0]);
            if(in_array(($r['status']??''),['present','late','half_day'],true))$months[$month]['days_present']++;
        }
        krsort($months);
        $canFinance=$a->can(Capabilities::ACCOUNTING_VIEW);
        $ledger=$canFinance?$reader->ledger($a->companyId,$employeeId,$from,$to,$branches):[];
        if(!is_array($ledger)||count($ledger)>1000)
            throw new DomainException('Tagged employee ledger source invalid.','projection_corrupt',500);
        foreach($ledger as $item){
            if(!is_array($item)||(int)($item['branch_id']??0)<1
                ||(!$scope['self']&&!in_array((int)$item['branch_id'],$branches,true)))
                throw new DomainException('Tagged employee GL outside branch authority.','projection_corrupt',500);
        }
        return [
            'employee'=>['id'=>$employeeId,'employee_code'=>(string)$employee['employee_code'],
                'full_name'=>(string)$employee['full_name'],'designation_code'=>(string)$employee['designation_code'],
                'assigned_branch_id'=>(int)$employee['assigned_branch_id'],'status'=>(string)$employee['status']],
            'period'=>['from'=>$from,'to'=>$to],
            'monthly_summary'=>array_values($months),
            'attendance_history'=>$attendance,
            'employee_stock'=>$stock,
            'person_ledger'=>['visible'=>$canFinance,'scope'=>'tagged_employee_journal_lines_only','entries'=>$ledger],
            'detailed_register_endpoint'=>'/organization/employees/'.$employeeId.'/360/register',
            'cash_reconciliation'=>'not_available_in_canonical_v7_employee_ledger',
            'gps_route'=>'use_existing_authorized_workforce_gps_route_endpoint',
            'dashboard_unchanged'=>true,
            'monthly_totals_basis'=>'canonical_posted_daily_sales_and_performance_entries',
            'snapshot_atomic'=>false,
            'read_only'=>true,
        ];
    }
}

final class Employee360WpReader implements Employee360Reader {
    private function scope(array $branches,string $alias=''): string {
        if (!$branches)return '';
        $prefix=$alias!==''?$alias.'.':'';
        return ' AND '.$prefix.'branch_id IN ('.implode(',',array_fill(0,count($branches),'%d')).')';
    }
    private function args(array $base,array $branches):array {return array_merge($base,$branches);}
    private function rows(string $sql,array $args):array {
        $db=Db::wpdb();$prepared=$db->prepare($sql,...$args);
        $rows=$db->get_results($prepared,ARRAY_A);
        if($rows===null)throw new DomainException('Employee projection query failed.','employee_360_query_failed',500);
        return (array)$rows;
    }
    public function employee(int $company,int $id):?array {
        $rows=$this->rows('SELECT id,company_id,employee_code,full_name,designation_code,assigned_branch_id,status FROM '.Db::table('employees').' WHERE company_id=%d AND id=%d LIMIT 1',[$company,$id]);
        return $rows[0]??null;
    }
    public function sales(int $company,int $id,string $from,string $to,array $branches):array {
        $sql="SELECT DATE_FORMAT(c.business_date,'%Y-%m') month, ROUND(SUM(es.expected_amount),2) sale_amount FROM ".Db::table('daily_cycles')." c JOIN ".Db::table('evening_settlements')." es ON es.daily_cycle_id=c.id AND es.status='posted' WHERE c.company_id=%d AND c.employee_id=%d AND c.business_date BETWEEN %s AND %s AND c.status='completed'".$this->scope($branches,'c').' GROUP BY DATE_FORMAT(c.business_date,\'%Y-%m\') ORDER BY month DESC';
        return $this->rows($sql,$this->args([$company,$id,$from,$to],$branches));
    }
    public function performance(int $company,int $id,string $from,string $to,array $branches):array {
        $sql="SELECT DATE_FORMAT(business_date,'%Y-%m') month, ROUND(SUM(points),2) points FROM ".Db::table('performance_entries').' WHERE company_id=%d AND employee_id=%d AND business_date BETWEEN %s AND %s'.$this->scope($branches).' GROUP BY DATE_FORMAT(business_date,\'%Y-%m\') ORDER BY month DESC';
        return $this->rows($sql,$this->args([$company,$id,$from,$to],$branches));
    }
    public function attendance(int $company,int $id,string $from,string $to,array $branches):array {
        $sql='SELECT branch_id,business_date,status,check_in_at,check_out_at,checkout_exception FROM '.Db::table('attendance').' WHERE company_id=%d AND employee_id=%d AND business_date BETWEEN %s AND %s'.$this->scope($branches).' ORDER BY business_date DESC';
        return $this->rows($sql,$this->args([$company,$id,$from,$to],$branches));
    }
    public function stock(int $company,int $id,array $branches):array {
        $sql='SELECT s.branch_id,s.product_id,p.sku,p.name product_name,s.batch_key,s.quantity FROM '.Db::table('stock_balances').' s JOIN '.Db::table('products').' p ON p.id=s.product_id AND p.company_id=s.company_id WHERE s.company_id=%d AND s.custodian_key=%d AND s.quantity>0'.$this->scope($branches,'s').' ORDER BY s.branch_id,p.name,s.batch_key LIMIT 1000';
        return $this->rows($sql,$this->args([$company,$id],$branches));
    }
    public function ledger(int $company,int $id,string $from,string $to,array $branches):array {
        $sql="SELECT j.id journal_entry_id,j.branch_id,j.entry_no,j.entry_date,j.source_type,j.source_id,a.code account_code,a.name account_name,l.debit,l.credit,l.description FROM ".Db::table('journal_lines')." l JOIN ".Db::table('journal_entries')." j ON j.id=l.journal_entry_id JOIN ".Db::table('accounts')." a ON a.id=l.account_id AND a.company_id=j.company_id WHERE j.company_id=%d AND l.party_type='employee' AND l.party_id=%d AND DATE(j.entry_date) BETWEEN %s AND %s AND j.status='posted'".$this->scope($branches,'j').' ORDER BY j.entry_date DESC,j.id DESC,l.id DESC LIMIT 1000';
        return $this->rows($sql,$this->args([$company,$id,$from,$to],$branches));
    }
}