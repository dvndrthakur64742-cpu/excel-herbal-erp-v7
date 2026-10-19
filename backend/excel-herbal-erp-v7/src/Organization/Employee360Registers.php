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
}

final class Employee360Registers {
    public static function view(
        Actor $actor,int $employeeId,string $type,string $from,string $to,int $page=1,int $pageSize=50,
        ?Employee360RegisterReader $registerReader=null,?Employee360Reader $employeeReader=null
    ):array {
        Employee360Service::validatePeriod($from,$to);
        if(!in_array($type,['sales','stock'],true))
            throw new DomainException('Employee 360 register type must be sales or stock.','register_type_invalid',422);
        if($page<1||$page>500||$pageSize<1||$pageSize>100)
            throw new DomainException('Invalid register pagination.','register_pagination_invalid',422);
        $scope=Employee360Service::authorizeTarget($actor,$employeeId,$employeeReader);
        $reader=$registerReader??new Employee360WpRegisterReader();
        $limit=$pageSize+1;$offset=($page-1)*$pageSize;
        $rows=$type==='sales'
            ?$reader->sales($actor->companyId,$employeeId,$from,$to,$scope['branches'],$limit,$offset)
            :$reader->stock($actor->companyId,$employeeId,$from,$to,$scope['branches'],$limit,$offset);
        if(!is_array($rows))throw new DomainException('Employee register query failed.','employee_360_query_failed',500);
        $more=count($rows)>$pageSize;
        $rows=array_slice($rows,0,$pageSize);
        return [
            'employee_id'=>$employeeId,'register'=>$type,'period'=>['from'=>$from,'to'=>$to],
            'page'=>$page,'page_size'=>$pageSize,'has_more'=>$more,
            'rows'=>$rows,'read_only'=>true,
            'source'=>$type==='sales'?'posted_daily_order_settlements':'employee_custodied_stock_ledger',
            'financial_custody_reconciliation'=>'not_inferred_from_stock_or_sales_history',
            'note'=>$type==='sales'
                ?'Cash/UPI are posted settlement totals, not evidence that employee cash was remitted to branch.'
                :'Movements are a stock audit trail, not proof of a matching financial journal or physical stock count.',
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