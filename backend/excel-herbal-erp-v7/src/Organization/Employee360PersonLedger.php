<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP7\Organization;

use ExcelHerbal\ERP7\Core\Input;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities};

/**
 * Employee 360 unified, read-only source-linked timeline.
 * Finance permission mandatory. No shadow inventory, shadow GL, new transactions,
 * bank proof or physical Cash handover is created by this report.
 */
interface EmployeePersonLedgerReader {
    public function events(int $company,int $employee,string $from,string $to,array $branches,int $limit,int $offset):array;
    public function financialBalances(int $company,int $employee,string $from,string $to,array $branches):array;
    public function stockBalances(int $company,int $employee,string $from,string $to,array $branches):array;
}

final class Employee360PersonLedger {
    /** Convert a canonical DECIMAL string to signed fixed-point units. */
    private static function scaled(mixed $raw,int $places):int {
        if(!is_int($raw)&&!is_string($raw))
            throw new DomainException('Person ledger invalid fixed-point source.','person_ledger_source_invalid',500);
        $v=(string)$raw;
        if(!preg_match('/^-?(0|[1-9][0-9]{0,11})(?:\.([0-9]{1,3}))?$/D',$v,$m)
            ||strlen($m[2]??'')>$places)
            throw new DomainException('Person ledger invalid fixed-point precision.','person_ledger_source_invalid',500);
        $minus=str_starts_with($v,'-');
        $major=(int)$m[1];$unit=10**$places;
        if($major>intdiv(PHP_INT_MAX,$unit))throw new DomainException('Person ledger fixed-point overflow.','person_ledger_source_invalid',500);
        $n=$major*$unit+(int)str_pad($m[2]??'',$places,'0',STR_PAD_RIGHT);
        return $minus?-$n:$n;
    }
    private static function fixed(int $n,int $places):string {
        $unit=10**$places;
        return ($n<0?'-':'').intdiv(abs($n),$unit).'.'
            .str_pad((string)(abs($n)%$unit),$places,'0',STR_PAD_LEFT);
    }
    public static function view(
        Actor $actor,int $employee,string $from,string $to,int $page=1,int $pageSize=50,
        ?EmployeePersonLedgerReader $reader=null,?Employee360Reader $profileReader=null
    ):array {
        if(!$actor->can(Capabilities::ACCOUNTING_VIEW))
            throw new DomainException('Finance permission required for Tally-style person ledger.','permission_denied',403);
        Employee360Service::validatePeriod($from,$to);
        if($page<1||$page>500||$pageSize<1||$pageSize>100)
            throw new DomainException('Invalid person ledger pagination.','register_pagination_invalid',422);
        $scope=Employee360Service::authorizeTarget($actor,$employee,$profileReader);
        $reader=$reader??new EmployeePersonLedgerWpReader();
        $branches=$scope['branches'];
        $events=$reader->events($actor->companyId,$employee,$from,$to,$branches,$pageSize+1,($page-1)*$pageSize);
        if(!is_array($events))throw new DomainException('Person ledger event reader failed.','person_ledger_source_invalid',500);
        $more=count($events)>$pageSize;
        $events=array_slice($events,0,$pageSize);
        foreach($events as $event){
            if(!is_array($event)||!in_array($event['event_type']??null,['gl','stock','sale','points'],true)
                ||(int)($event['event_id']??0)<1
                ||(int)($event['branch_id']??0)<1
                ||(!$scope['self']&&!in_array((int)$event['branch_id'],$branches,true)))
                throw new DomainException('Person ledger source or branch scope corrupt.','person_ledger_source_invalid',500);
        }
        $rawFinance=$reader->financialBalances($actor->companyId,$employee,$from,$to,$branches);
        $rawStock=$reader->stockBalances($actor->companyId,$employee,$from,$to,$branches);
        if(!is_array($rawFinance)||!is_array($rawStock)||count($rawFinance)>2000||count($rawStock)>2000)
            throw new DomainException('Full person ledger history exceeds safe reporting scope.','person_ledger_source_invalid',500);
        $accounts=[];$seen=[];
        foreach($rawFinance as $row){
            if(!is_array($row)||(int)($row['account_id']??0)<1||!is_string($row['account_code']??null))
                throw new DomainException('Invalid tagged GL account.','person_ledger_source_invalid',500);
            $id=(int)$row['account_id'];
            if(isset($seen[$id]))throw new DomainException('Duplicate tagged GL account.','person_ledger_source_invalid',500);
            $seen[$id]=true;
            $open=self::scaled($row['opening_delta']??null,2);
            $debit=self::scaled($row['period_debit']??null,2);
            $credit=self::scaled($row['period_credit']??null,2);
            $accounts[]=['account_id'=>$id,'account_code'=>$row['account_code'],
                'currency'=>'INR','opening_debit_minus_credit'=>self::fixed($open,2),
                'period_debit'=>self::fixed($debit,2),'period_credit'=>self::fixed($credit,2),
                'closing_debit_minus_credit'=>self::fixed($open+$debit-$credit,2)];
        }
        $stocks=[];$seen=[];
        foreach($rawStock as $row){
            if(!is_array($row)||(int)($row['branch_id']??0)<1||(int)($row['product_id']??0)<1)
                throw new DomainException('Invalid tagged stock source.','person_ledger_source_invalid',500);
            $branch=(int)$row['branch_id'];$product=(int)$row['product_id'];$batch=(int)($row['batch_key']??0);
            if(!$scope['self']&&!in_array($branch,$branches,true))
                throw new DomainException('Stock balance crossed branch authority.','person_ledger_source_invalid',500);
            $key=$branch.':'.$product.':'.$batch;
            if(isset($seen[$key]))throw new DomainException('Duplicate stock batch summary.','person_ledger_source_invalid',500);
            $seen[$key]=true;
            $open=self::scaled($row['opening_quantity']??null,3);
            $incoming=self::scaled($row['period_in']??null,3);
            $outgoing=self::scaled($row['period_out']??null,3);
            $closing=$open+$incoming-$outgoing;
            $stocks[]=['branch_id'=>$branch,'product_id'=>$product,'batch_key'=>$batch,'unit'=>'PCS',
                'opening_quantity'=>self::fixed($open,3),
                'period_in'=>self::fixed($incoming,3),'period_out'=>self::fixed($outgoing,3),
                'closing_quantity'=>self::fixed($closing,3),
                'negative_balance_warning'=>$closing<0];
        }
        return [
            'employee_id'=>$employee,'register'=>'person_ledger','period'=>['from'=>$from,'to'=>$to],
            'page'=>$page,'page_size'=>$pageSize,'has_more'=>$more,'rows'=>$events,
            'financial_accounts'=>$accounts,'stock_items'=>$stocks,'read_only'=>true,
            'scope'=>'posted_gl_employee_tagged_and_canonical_stock_sales_points',
            'currency_policy'=>'INR balances by account; PCS by product/batch; points never monetary',
            'balance_basis'=>'complete_tagged_movement_history_not_visible_page',
            'physical_stock_verified'=>false,'employee_cash_handover_verified'=>false,
            'upi_bank_settlement_verified'=>false,
            'note'=>'GL debit-minus-credit is employee-tagged accounting, not a full company account balance. Stock opening is ledger-movement-derived, not a counted physical opening. Sales and points are separate reference events.'
        ];
    }
}

/** Parameterized, company/employee/branch-scoped V7 canonical SQL only. */
final class EmployeePersonLedgerWpReader implements EmployeePersonLedgerReader {
    private function scope(array $branches,string $alias):string {
        return !$branches?'':' AND '.$alias.'.branch_id IN ('.implode(',',array_fill(0,count($branches),'%d')).')';
    }
    private function rows(string $sql,array $args):array {
        $db=Db::wpdb();$prepared=$db->prepare($sql,...$args);
        if(!is_string($prepared)||$prepared==='')throw new DomainException('Person ledger SQL prepare failed.','person_ledger_query_failed',500);
        $result=$db->get_results($prepared,ARRAY_A);
        if(!is_array($result))throw new DomainException('Person ledger SQL failed.','person_ledger_query_failed',500);
        return $result;
    }
    public function events(int $company,int $employee,string $from,string $to,array $branches,int $limit,int $offset):array {
        [$utcStart,$utcEnd]=Input::utcBoundsForBusinessRange($from,$to,'Person Ledger stock UTC bounds');
        $end=(new \DateTimeImmutable($to))->modify('+1 day')->format('Y-m-d').' 00:00:00';
        $j="SELECT j.entry_date event_at,'gl' event_type,j.branch_id,j.source_type,j.source_id,"
          ."l.id event_id,a.code account_code,NULL product_id,NULL batch_id,"
          ."COALESCE(l.description,'') description,l.debit,l.credit,"
          ."0 qty_in,0 qty_out,0 sale_amount,0 points "
          .'FROM '.Db::table('journal_lines').' l JOIN '.Db::table('journal_entries').' j ON j.id=l.journal_entry_id '
          .'JOIN '.Db::table('accounts').' a ON a.id=l.account_id AND a.company_id=j.company_id '
          ."WHERE j.company_id=%d AND l.party_type='employee' AND l.party_id=%d "
          ."AND j.status='posted' AND j.entry_date>=%s AND j.entry_date<%s".$this->scope($branches,'j');
        $s="SELECT sl.occurred_at event_at,'stock' event_type,sl.branch_id,sl.source_type,sl.source_id,"
          ."sl.id event_id,NULL account_code,sl.product_id,COALESCE(sl.batch_id,0) batch_id,"
          ."'Custody movement' description,0 debit,0 credit,"
          ."CASE WHEN sl.direction='IN' THEN sl.quantity ELSE 0 END qty_in,"
          ."CASE WHEN sl.direction='OUT' THEN sl.quantity ELSE 0 END qty_out,0 sale_amount,0 points "
          .'FROM '.Db::table('stock_ledger').' sl '
          .'WHERE sl.company_id=%d AND sl.custodian_employee_id=%d '
          ."AND sl.direction IN ('IN','OUT') AND sl.occurred_at>=%s AND sl.occurred_at<%s".$this->scope($branches,'sl');
        $sales="SELECT CONCAT(c.business_date,' 12:00:00') event_at,'sale' event_type,c.branch_id,"
          ."'daily_cycle' source_type,c.id source_id,c.id event_id,NULL account_code,NULL product_id,NULL batch_id,"
          ."'Posted daily order' description,0 debit,0 credit,0 qty_in,0 qty_out,"
          ."es.expected_amount sale_amount,0 points "
          .'FROM '.Db::table('daily_cycles').' c JOIN '.Db::table('evening_settlements').' es '
          ."ON es.daily_cycle_id=c.id AND es.status='posted' "
          ."WHERE c.company_id=%d AND c.employee_id=%d AND c.status='completed' "
          .'AND c.business_date BETWEEN %s AND %s'.$this->scope($branches,'c');
        $p="SELECT CONCAT(p.business_date,' 12:00:00') event_at,'points' event_type,p.branch_id,"
          ."p.source_type,p.source_id,p.id event_id,NULL account_code,NULL product_id,NULL batch_id,"
          ."'Performance points' description,0 debit,0 credit,0 qty_in,0 qty_out,"
          ."0 sale_amount,p.points "
          .'FROM '.Db::table('performance_entries').' p '
          .'WHERE p.company_id=%d AND p.employee_id=%d '
          .'AND p.business_date BETWEEN %s AND %s'.$this->scope($branches,'p');
        $args=array_merge(
          [$company,$employee,$from.' 00:00:00',$end],$branches,
          [$company,$employee,$utcStart,$utcEnd],$branches,
          [$company,$employee,$from,$to],$branches,
          [$company,$employee,$from,$to],$branches,
          [$limit,$offset]);
        return $this->rows('SELECT * FROM ('.$j.' UNION ALL '.$s.' UNION ALL '.$sales.' UNION ALL '.$p.') timeline '
            .'ORDER BY event_at DESC,event_type DESC,event_id DESC LIMIT %d OFFSET %d',$args);
    }
    public function financialBalances(int $company,int $employee,string $from,string $to,array $branches):array {
        $start=$from.' 00:00:00';$end=(new \DateTimeImmutable($to))->modify('+1 day')->format('Y-m-d').' 00:00:00';
        $sql='SELECT a.id account_id,a.code account_code,'
          .'COALESCE(SUM(CASE WHEN j.entry_date<%s THEN l.debit-l.credit ELSE 0 END),0) opening_delta,'
          .'COALESCE(SUM(CASE WHEN j.entry_date>=%s THEN l.debit ELSE 0 END),0) period_debit,'
          .'COALESCE(SUM(CASE WHEN j.entry_date>=%s THEN l.credit ELSE 0 END),0) period_credit '
          .'FROM '.Db::table('journal_lines').' l JOIN '.Db::table('journal_entries').' j ON j.id=l.journal_entry_id '
          .'JOIN '.Db::table('accounts').' a ON a.id=l.account_id AND a.company_id=j.company_id '
          ."WHERE j.company_id=%d AND l.party_type='employee' AND l.party_id=%d "
          ."AND j.status='posted' AND j.entry_date<%s".$this->scope($branches,'j')
          .' GROUP BY a.id,a.code ORDER BY a.code,a.id';
        return $this->rows($sql,array_merge([$start,$start,$start,$company,$employee,$end],$branches));
    }
    public function stockBalances(int $company,int $employee,string $from,string $to,array $branches):array {
        [$start,$end]=Input::utcBoundsForBusinessRange($from,$to,'Person ledger stock opening/closing');
        $sql='SELECT sl.branch_id,sl.product_id,COALESCE(sl.batch_id,0) batch_key,'
          ."COALESCE(SUM(CASE WHEN sl.occurred_at<%s AND sl.direction='IN' THEN sl.quantity "
          ."WHEN sl.occurred_at<%s AND sl.direction='OUT' THEN -sl.quantity ELSE 0 END),0) opening_quantity,"
          ."COALESCE(SUM(CASE WHEN sl.occurred_at>=%s AND sl.direction='IN' THEN sl.quantity ELSE 0 END),0) period_in,"
          ."COALESCE(SUM(CASE WHEN sl.occurred_at>=%s AND sl.direction='OUT' THEN sl.quantity ELSE 0 END),0) period_out "
          .'FROM '.Db::table('stock_ledger').' sl '
          .'WHERE sl.company_id=%d AND sl.custodian_employee_id=%d '
          ."AND sl.direction IN ('IN','OUT') AND sl.occurred_at<%s".$this->scope($branches,'sl')
          .' GROUP BY sl.branch_id,sl.product_id,COALESCE(sl.batch_id,0) ORDER BY sl.branch_id,sl.product_id,batch_key';
        return $this->rows($sql,array_merge([$start,$start,$start,$start,$company,$employee,$end],$branches));
    }
}
