<?php
namespace ExcelHerbal\ERP7\DailyOrder;

use ExcelHerbal\ERP7\Core\Input;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;
use ExcelHerbal\ERP7\Security\HierarchyScope;

/**
 * Read-only paginated Daily Order history. Search never grants broader employee
 * visibility than the existing employee reporting hierarchy and branch grants.
 */
final class DailyOrderSearchService {
    private const STATUSES = [
        'morning_draft', 'stock_requested', 'approved', 'awaiting_receipt',
        'issued', 'evening_draft', 'evening_submitted', 'completed',
        'cancelled', 'rejected',
    ];

    /** @return array{items:array,total:int,page:int,page_size:int,has_more:bool} */
    public static function search(
        Actor $actor, ?int $branchId, int $page=1, int $pageSize=25,
        string $query='', string $status='', string $dateFrom='', string $dateTo=''
    ):array {
        Guard::any($actor,[Capabilities::DAILY_SELF,Capabilities::DAILY_OTHERS]);
        if($page<1||$page>1000||$pageSize<1||$pageSize>50) {
            throw new DomainException(
                'Page must be 1-1000 and page_size 1-50.','daily_search_pagination_invalid',422
            );
        }
        $query=trim($query);
        $status=trim($status);
        if(strlen($query)>80||preg_match('/[\x00-\x1F\x7F]/',$query)) {
            throw new DomainException('Search text is invalid.','daily_search_query_invalid',422);
        }
        if($status!==''&&!in_array($status,self::STATUSES,true)) {
            throw new DomainException('Unsupported daily order status.','daily_search_status_invalid',422);
        }
        $dateFrom=Input::optionalDate($dateFrom,'History start date');
        $dateTo=Input::optionalDate($dateTo,'History end date');
        if($dateFrom!==null&&$dateTo!==null&&$dateFrom>$dateTo) {
            throw new DomainException('Start date cannot be after end date.','date_range_invalid',422);
        }

        $branches=array_values(array_unique(array_filter(
            array_map('intval',$actor->branchIds),
            static fn(int $id):bool=>$id>0
        )));
        if($branchId!==null) {
            Guard::branchAny($actor,$branchId,[Capabilities::DAILY_SELF,Capabilities::DAILY_OTHERS]);
            $branches=[$branchId];
        }
        if(!$branches)return self::empty($page,$pageSize);

        $canOthers=$actor->can(Capabilities::DAILY_OTHERS);
        $employees=$canOthers
            ? HierarchyScope::visibleEmployeeIds($actor,$branchId)
            : [$actor->employeeId];
        $employees=array_values(array_unique(array_filter(
            array_map('intval',$employees),
            static fn(int $id):bool=>$id>0
        )));
        if(!$employees)return self::empty($page,$pageSize);

        $db=Db::wpdb();
        $joins=' FROM '.Db::table('daily_cycles').' c'.
            ' JOIN '.Db::table('employees').' e'.
            ' ON e.id=c.employee_id AND e.company_id=c.company_id';
        $where=' WHERE c.company_id=%d'.
            ' AND c.branch_id IN ('.implode(',',array_fill(0,count($branches),'%d')).')'.
            ' AND c.employee_id IN ('.implode(',',array_fill(0,count($employees),'%d')).')';
        $params=array_merge([$actor->companyId],$branches,$employees);
        if($status!==''){$where.=' AND c.status=%s';$params[]=$status;}
        if($dateFrom!==null){$where.=' AND c.business_date>=%s';$params[]=$dateFrom;}
        if($dateTo!==null){$where.=' AND c.business_date<=%s';$params[]=$dateTo;}
        if($query!==''){
            // Escape '%' and '_' before adding deliberate wildcards.
            $like='%'.$db->esc_like($query).'%';
            $numeric=ctype_digit($query) && strlen($query)<=18;
            $where.=' AND ('.($numeric?'c.id=%d OR ':'').
                'e.full_name LIKE %s OR e.employee_code LIKE %s)';
            if($numeric)$params[]=(int)$query;
            $params[]=$like;$params[]=$like;
        }
        $total=(int)$db->get_var($db->prepare(
            'SELECT COUNT(*)'.$joins.$where,...$params
        ));
        $rows=[];
        if($total>0){
            $rows=(array)$db->get_results($db->prepare(
                'SELECT c.id,c.company_id,c.branch_id,c.employee_id,c.business_date,'.
                'c.status,e.full_name employee_name,e.employee_code,'.
                'r.status initial_request_status,ar.status additional_request_status'.
                $joins.
                ' LEFT JOIN '.Db::table('daily_requests').' r'.
                " ON r.id=(SELECT MAX(r1.id) FROM ".Db::table('daily_requests').
                " r1 WHERE r1.daily_cycle_id=c.id AND r1.type='initial')".
                ' LEFT JOIN '.Db::table('daily_requests').' ar'.
                " ON ar.id=(SELECT MAX(r2.id) FROM ".Db::table('daily_requests').
                " r2 WHERE r2.daily_cycle_id=c.id AND r2.type='additional')".
                $where.' ORDER BY c.business_date DESC,c.id DESC LIMIT %d OFFSET %d',
                ...array_merge($params,[$pageSize,($page-1)*$pageSize])
            ),ARRAY_A);
        }
        return [
            'items'=>$rows,
            'total'=>$total,
            'page'=>$page,
            'page_size'=>$pageSize,
            'has_more'=>$page*$pageSize<$total,
        ];
    }

    private static function empty(int $page,int $pageSize):array {
        return ['items'=>[],'total'=>0,'page'=>$page,'page_size'=>$pageSize,'has_more'=>false];
    }
}
