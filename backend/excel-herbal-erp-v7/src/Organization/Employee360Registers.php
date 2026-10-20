<?php
/**
 * Read-only employee operational registers sourced from canonical V7 posted records.
 * No cash liability assumptions, no invoice creation and no mutation.
 */
namespace ExcelHerbal\ERP7\Organization;

use ExcelHerbal\ERP7\Core\Input;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;

interface Employee360RegisterReader {
    /** A page of completed Daily Order settlements (one row per cycle). */
    public function sales(int $company,int $employee,string $from,string $to,array $branches,int $limit,int $offset):array;
    /** An independent page of movement entries tied to this employee as custodian. */
    public function stock(int $company,int $employee,string $from,string $to,array $branches,int $limit,int $offset):array;
    /** Original V7 Daily Order requests with issue quantities from canonical issue lines. */
    public function requests(int $company,int $employee,string $from,string $to,array $branches,int $limit,int $offset):array;
}

final class Employee360Registers {
    public static function view(
        Actor $actor,int $employeeId,string $type,string $from,string $to,int $page=1,int $pageSize=50,
        ?Employee360RegisterReader $registerReader=null,?Employee360Reader $employeeReader=null
    ):array {
        Employee360Service::validatePeriod($from,$to);
        if(!in_array($type,['sales','stock','requests'],true))
            throw new DomainException('Employee 360 register type must be sales, stock or requests.','register_type_invalid',422);
        if($page<1||$page>500||$pageSize<1||$pageSize>100)
            throw new DomainException('Invalid register pagination.','register_pagination_invalid',422);
        $scope=Employee360Service::authorizeTarget($actor,$employeeId,$employeeReader);
        $reader=$registerReader??new Employee360WpRegisterReader();
        $limit=$pageSize+1;$offset=($page-1)*$pageSize;
        $rows=match($type){
            'sales'=>$reader->sales($actor->companyId,$employeeId,$from,$to,$scope['branches'],$limit,$offset),
            'stock'=>$reader->stock($actor->companyId,$employeeId,$from,$to,$scope['branches'],$limit,$offset),
            'requests'=>$reader->requests($actor->companyId,$employeeId,$from,$to,$scope['branches'],$limit,$offset),
        };
        if(!is_array($rows))throw new DomainException('Employee register query failed.','employee_360_query_failed',500);
        $more=count($rows)>$pageSize;
        $rows=array_slice($rows,0,$pageSize);
        return [
            'employee_id'=>$employeeId,'register'=>$type,'period'=>['from'=>$from,'to'=>$to],
            'page'=>$page,'page_size'=>$pageSize,'has_more'=>$more,
            'rows'=>$rows,'read_only'=>true,
            'source'=>match($type){
                'sales'=>'posted_daily_order_settlements',
                'stock'=>'employee_custodied_stock_ledger',
                'requests'=>'canonical_v7_daily_requests_and_issue_lines',
            },
            'financial_custody_reconciliation'=>'not_inferred_from_stock_or_sales_history',
            'note'=>match($type){
                'sales'=>'Cash/UPI are posted settlement totals, not evidence that employee cash was remitted to branch.',
                'stock'=>'Movements are a stock audit trail, not proof of a matching financial journal or physical stock count.',
                'requests'=>'Approval does not mean stock was issued. Issued quantity is taken only from V7 Daily Order issue lines.',
            },
        ];
    }
}

final class Employee360WpRegisterReader implements Employee360RegisterReader {
    private function scope(array $branches,string $alias):string {
        if(!$branches)return '';
        return ' AND '.$alias.'.branch_id IN ('.implode(',',array_fill(0,count($branches),'%d')).')';
    }
    private function rows(string $sql,array $args):array {
        $db=Db::wpdb();
        $prepared=$db->prepare($sql,...$args);
        if(!is_string($prepared)||$prepared==='')throw new DomainException('Employee register SQL preparation failed.','employee_360_query_failed',500);
        $result=$db->get_results($prepared,ARRAY_A);
        if(!is_array($result))throw new DomainException('Employee register SQL failed.','employee_360_query_failed',500);
        return $result;
    }
    public function sales(int $company,int $employee,string $from,string $to,array $branches,int $limit,int $offset):array {
        $sql='SELECT c.id daily_cycle_id,c.branch_id,c.business_date,es.expected_amount sale_amount,es.cash_amount,es.upi_amount,'
            .'COUNT(el.id) product_line_count,COALESCE(SUM(el.retail_quantity),0) retail_quantity,'
            .'COALESCE(SUM(el.wholesale_quantity),0) wholesale_quantity,'
            .'COALESCE(SUM(el.return_quantity),0) returned_quantity,'
            .'COALESCE(SUM(el.points),0) incentive_points '
            .'FROM '.Db::table('daily_cycles').' c '
            .'JOIN '.Db::table('evening_settlements').' es ON es.daily_cycle_id=c.id AND es.status=\'posted\' '
            .'LEFT JOIN '.Db::table('evening_lines').' el ON el.evening_settlement_id=es.id '
            .'WHERE c.company_id=%d AND c.employee_id=%d AND c.status=\'completed\' '
            .'AND c.business_date BETWEEN %s AND %s'.$this->scope($branches,'c')
            .' GROUP BY c.id,c.branch_id,c.business_date,es.expected_amount,es.cash_amount,es.upi_amount'
            .' ORDER BY c.business_date DESC,c.id DESC LIMIT %d OFFSET %d';
        return $this->rows($sql,array_merge([$company,$employee,$from,$to],$branches,[$limit,$offset]));
    }
    public function requests(int $company,int $employee,string $from,string $to,array $branches,int $limit,int $offset):array {
        // The original request and physical issuance are separate canonical V7
        // sources. Aggregate BEFORE joining to avoid multiplying multi-batch lines.
        // No prices, cost, margins or financial amounts leave this read projection.
        $requests=Db::table('daily_requests');
        $cycles=Db::table('daily_cycles');
        $requestLines=Db::table('daily_request_lines');
        $issuedLines=Db::table('daily_issue_lines');
        $sql='SELECT r.id request_id,c.id daily_cycle_id,c.branch_id,c.business_date,'
            .'r.type request_type,r.status request_status,r.requested_by,r.approved_by,r.issued_by,'
            .'r.created_at requested_at,r.approved_at,r.issued_at,'
            .'COALESCE(rl.requested_line_count,0) requested_line_count,'
            .'COALESCE(rl.requested_quantity,0) requested_quantity,'
            .'COALESCE(il.issued_line_count,0) issued_line_count,'
            .'COALESCE(il.issued_quantity,0) issued_quantity '
            .'FROM '.$cycles.' c '
            .'JOIN '.$requests.' r ON r.daily_cycle_id=c.id '
            .'LEFT JOIN (SELECT daily_request_id,COUNT(*) requested_line_count,'
            .'SUM(quantity) requested_quantity FROM '.$requestLines.' GROUP BY daily_request_id) rl '
            .'ON rl.daily_request_id=r.id '
            .'LEFT JOIN (SELECT daily_request_id,COUNT(*) issued_line_count,'
            .'SUM(quantity) issued_quantity FROM '.$issuedLines.' GROUP BY daily_request_id) il '
            .'ON il.daily_request_id=r.id '
            .'WHERE c.company_id=%d AND c.employee_id=%d '
            .'AND c.business_date BETWEEN %s AND %s'.$this->scope($branches,'c')
            .' ORDER BY c.business_date DESC,r.id DESC LIMIT %d OFFSET %d';
        return $this->rows($sql,array_merge([$company,$employee,$from,$to],$branches,[$limit,$offset]));
    }
    public function stock(int $company,int $employee,string $from,string $to,array $branches,int $limit,int $offset):array {
        // Stock ledger timestamps are stored by Db::now() in UTC, unlike daily business dates.
        // Use the canonical business timezone converter rather than comparing DATE(UTC time).
        [$startUtc,$endUtc]=Input::utcBoundsForBusinessRange($from,$to,'Employee stock movement period');
        $sql='SELECT sl.id stock_ledger_id,sl.branch_id,sl.product_id,p.sku,p.name product_name,'
            .'sl.batch_id,bt.batch_no,sl.direction,sl.quantity,sl.source_type,sl.source_id,sl.occurred_at '
            .'FROM '.Db::table('stock_ledger').' sl '
            .'JOIN '.Db::table('products').' p ON p.id=sl.product_id AND p.company_id=sl.company_id '
            .'LEFT JOIN '.Db::table('batches').' bt ON bt.id=sl.batch_id AND bt.company_id=sl.company_id AND bt.product_id=sl.product_id '
            .'WHERE sl.company_id=%d AND sl.custodian_employee_id=%d '
            .'AND sl.direction IN (\'IN\',\'OUT\') '
            .'AND sl.occurred_at>=%s AND sl.occurred_at<%s'.$this->scope($branches,'sl')
            .' ORDER BY sl.occurred_at DESC,sl.id DESC LIMIT %d OFFSET %d';
        return $this->rows($sql,array_merge([$company,$employee,$startUtc,$endUtc],$branches,[$limit,$offset]));
    }
}