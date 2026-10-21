<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP7\DailyOrder;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities,Guard};

/**
 * Read-only canonical V7 Daily Order employee-stock integrity audit.
 * No posting endpoint, financial mutation, cashier/bank proof or V8 shadow ledger.
 * The source interface permits isolated MariaDB and pure contract regressions.
 */
interface DailyFieldStockAuditReader {
    public function cycle(int $company,int $id):?array;
    public function issues(int $company,int $id):array;
    public function closing(int $company,int $id):array;
    public function closingLines(int $company,int $id):array;
    public function movements(int $company,int $branch,int $cycle,array $requestIds):array;
    public function journalHeaders(int $company,int $id):array;
    public function journalLines(int $company,int $cycle,int $journalId):array;
    public function performance(int $company,int $id):array;
}

final class DailyFieldStockAudit
{
    private const MAX_LINES=250;
    private const MAX_MOVES=3000;

    public static function inspect(Actor $actor,int $cycleId,?DailyFieldStockAuditReader $reader=null):array
    {
        if(!$actor->can(Capabilities::ACCOUNTING_VIEW))
            throw new DomainException('Independent finance permission is required.','permission_denied',403);
        if($cycleId<1)throw new DomainException('Cycle ID required.','daily_cycle_invalid',422);
        $reader=$reader??new DailyFieldStockAuditWpReader();
        $cycle=$reader->cycle($actor->companyId,$cycleId);
        if(!is_array($cycle)||self::id($cycle['id']??null)!==$cycleId
            ||self::id($cycle['company_id']??null)!==$actor->companyId)
            throw new DomainException('Daily Order cycle not found.','daily_not_found',404);
        $branch=self::id($cycle['branch_id']??null);
        $employee=self::id($cycle['employee_id']??null);
        Guard::branch($actor,$branch,Capabilities::ACCOUNTING_VIEW);
        if($employee<1)throw new DomainException('Cycle employee identity invalid.','field_audit_source_invalid',500);
        $status=(string)($cycle['status']??'');
        $allowed=['morning_draft','stock_requested','approved','issued','evening_draft','evening_submitted','completed','cancelled','rejected'];
        if(!in_array($status,$allowed,true))
            throw new DomainException('Unexpected Daily Order source state.','field_audit_source_invalid',500);

        $issueRows=$reader->issues($actor->companyId,$cycleId);
        $closingRows=$reader->closing($actor->companyId,$cycleId);
        $lineRows=$reader->closingLines($actor->companyId,$cycleId);
        foreach([[$issueRows,self::MAX_LINES],[$closingRows,1],[$lineRows,self::MAX_LINES]] as [$rows,$max])
            if(!is_array($rows)||count($rows)>$max)
                throw new DomainException('Incomplete or duplicate source in field stock audit.','field_audit_incomplete',409);

        $issues=[];$requests=[];$expected=[];$actual=[];
        $exceptions=[];
        $expect=static function(array &$map,string $key,int $n):void {
            if(!isset($map[$key]))$map[$key]=0;
            if($n>0&&$map[$key]>PHP_INT_MAX-$n)
                throw new DomainException('Stock audit quantity overflow.','field_audit_source_invalid',500);
            $map[$key]+=$n;
        };
        foreach($issueRows as $r){
            $id=self::id($r['id']??null);
            $request=self::id($r['request_id']??null);
            $product=self::id($r['product_id']??null);
            $batch=self::nullableId($r['batch_id']??null);
            if($id<1||$request<1||$product<1||isset($issues[$id])
                ||($r['request_status']??null)!=='issued')
                throw new DomainException('Canonical issued stock line invalid.','field_audit_source_invalid',500);
            $qty=self::milli($r['quantity']??null);
            if($qty<1)throw new DomainException('Issued quantity must be positive.','field_audit_source_invalid',500);
            $issues[$id]=['request'=>$request,'product'=>$product,'batch'=>$batch,'qty'=>$qty];
            $requests[$request]=true;
            $suffix=$product.':'.$batch;
            $expect($expected,'daily_issue:'.$request.':'.$suffix.':warehouse:OUT',$qty);
            $expect($expected,'daily_issue:'.$request.':'.$suffix.':employee:IN',$qty);
        }
        $closing=$closingRows[0]??null;
        $completed=$status==='completed';
        $hasClosing=in_array($status,['evening_draft','evening_submitted','completed'],true);
        if($hasClosing){
            if(!is_array($closing)||self::id($closing['daily_cycle_id']??null)!==$cycleId)
                $exceptions[]='closing_missing_or_wrong_cycle';
            elseif(($closing['status']??null)!==($completed?'posted':($status==='evening_submitted'?'submitted':'draft')))
                $exceptions[]='closing_state_mismatch';
        }elseif($closing!==null)$exceptions[]='unexpected_closing_before_evening';
        if(!$issues&&!in_array($status,['morning_draft','stock_requested','approved','cancelled','rejected'],true))
            $exceptions[]='issued_stock_missing';
        if(!$hasClosing&&count($lineRows)>0)$exceptions[]='unexpected_closing_lines';
        if($closing!==null&&count($lineRows)===0)$exceptions[]='closing_lines_missing';

        $seenClosing=[];$sold=0;$returned=0;$issued=0;
        // Points and salary allocation are distinct from recorded sales INR.
        $lineSalePaise=0;$linePointHundredths=0;$lineSalaryPaise=0;
        foreach($issues as $row)$issued+=$row['qty'];
        foreach($lineRows as $l){
            $il=self::id($l['issue_line_id']??null);
            if($il<1||isset($seenClosing[$il])||!isset($issues[$il]))
                throw new DomainException('Duplicate or foreign evening issue-line reference.','field_audit_source_invalid',500);
            $seenClosing[$il]=true;$original=$issues[$il];
            if(self::id($l['product_id']??null)!==$original['product']
                ||self::nullableId($l['batch_id']??null)!==$original['batch'])
                $exceptions[]='closing_product_batch_mismatch';
            $qty=self::milli($l['issued_quantity']??null);
            $ret=self::milli($l['return_quantity']??null);
            $retail=self::milli($l['retail_quantity']??null);
            $wh=self::milli($l['wholesale_quantity']??null);
            if($qty!==$original['qty']||$ret+$retail+$wh!==$qty)
                $exceptions[]='closing_quantity_mismatch';
            $sale=$retail+$wh;$sold+=$sale;$returned+=$ret;
            $saleAmount=self::money($l['total_amount']??null);
            $linePoints=self::money($l['points']??null);
            $lineSalary=self::money($l['salary_fund']??null);
            foreach([[$lineSalePaise,$saleAmount],[$linePointHundredths,$linePoints],
                [$lineSalaryPaise,$lineSalary]] as [$running,$additional]){
                if($running>PHP_INT_MAX-$additional)
                    throw new DomainException('Closing amount overflow.','field_audit_source_invalid',500);
            }
            $lineSalePaise+=$saleAmount;
            $linePointHundredths+=$linePoints;
            $lineSalaryPaise+=$lineSalary;
            $suffix=$original['product'].':'.$original['batch'];
            if($completed){
                $expect($expected,'daily_sale:'.$cycleId.':'.$suffix.':employee:OUT',$sale);
                $expect($expected,'daily_return:'.$cycleId.':'.$suffix.':employee:OUT',$ret);
                $expect($expected,'daily_return:'.$cycleId.':'.$suffix.':warehouse:IN',$ret);
            }
        }
        if($hasClosing&&count($issues)!==count($seenClosing))
            $exceptions[]='not_every_issued_line_closed';
        $requestIds=array_keys($requests);
        $moves=$reader->movements($actor->companyId,$branch,$cycleId,$requestIds);
        if(!is_array($moves)||count($moves)>self::MAX_MOVES)
            throw new DomainException('Ledger rows exceed complete audit limit.','field_audit_incomplete',409);
        $moveIds=[];
        foreach($moves as $m){
            $id=self::id($m['id']??null);
            $mCompany=self::id($m['company_id']??null);
            $mBranch=self::id($m['branch_id']??null);
            $source=(string)($m['source_type']??'');
            $sid=self::id($m['source_id']??null);
            $pid=self::id($m['product_id']??null);
            $batch=self::nullableId($m['batch_id']??null);
            $direction=(string)($m['direction']??'');
            $custodian=self::nullableId($m['custodian_employee_id']??null);
            $qty=self::milli($m['quantity']??null);
            if($id<1||isset($moveIds[$id])||$mCompany!==$actor->companyId||$mBranch!==$branch
                ||$pid<1||$sid<1||$qty<1||!in_array($direction,['IN','OUT'],true)
                ||!in_array($source,['daily_issue','daily_sale','daily_return'],true))
                throw new DomainException('Invalid or cross-branch stock movement.','field_audit_source_invalid',500);
            $moveIds[$id]=true;
            if(($source==='daily_issue'&&!isset($requests[$sid]))
                ||($source!=='daily_issue'&&$sid!==$cycleId))
                throw new DomainException('Foreign cycle stock movement.','field_audit_source_invalid',500);
            $owner=$custodian===null?'warehouse':($custodian===$employee?'employee':'other_employee');
            $key=$source.':'.$sid.':'.$pid.':'.$batch.':'.$owner.':'.$direction;
            $expect($actual,$key,$qty);
        }
        $diff=[];
        foreach(array_unique(array_merge(array_keys($expected),array_keys($actual))) as $key){
            if(($expected[$key]??0)!==($actual[$key]??0))
                $diff[]=['movement'=>$key,'expected_milli'=>$expected[$key]??0,'observed_milli'=>$actual[$key]??0];
        }
        if($diff)$exceptions[]='stock_ledger_quantity_mismatch';

        $journals=$reader->journalHeaders($actor->companyId,$cycleId);
        $perf=$reader->performance($actor->companyId,$cycleId);
        if(!is_array($journals)||count($journals)>2||!is_array($perf)||count($perf)>2)
            throw new DomainException('Duplicate financial source limit exceeded.','field_audit_incomplete',409);
        if($completed){
            if(count($journals)!==1||($journals[0]['status']??null)!=='posted'
                ||self::id($journals[0]['branch_id']??null)!==$branch)$exceptions[]='canonical_journal_header_missing_or_duplicate';
            if(count($perf)!==1||self::id($perf[0]['branch_id']??null)!==$branch
                ||self::id($perf[0]['employee_id']??null)!==$employee)
                $exceptions[]='employee_performance_record_missing_or_duplicate';
            if($closing!==null){
                $expectedSale=self::money($closing['expected_amount']??null);
                $reportedCash=self::money($closing['cash_amount']??null);
                $reportedUpi=self::money($closing['upi_amount']??null);
                if($reportedCash>PHP_INT_MAX-$reportedUpi
                    ||$reportedCash+$reportedUpi!==$expectedSale)
                    $exceptions[]='cash_upi_reported_totals_mismatch';
                if($lineSalePaise!==$expectedSale)
                    $exceptions[]='evening_line_sales_total_mismatch';
            }
            if(count($perf)===1&&self::id($perf[0]['branch_id']??null)===$branch
                &&self::id($perf[0]['employee_id']??null)===$employee){
                if(self::money($perf[0]['points']??null)!==$linePointHundredths)
                    $exceptions[]='employee_performance_points_mismatch';
                if(self::money($perf[0]['salary_fund']??null)!==$lineSalaryPaise)
                    $exceptions[]='employee_salary_fund_mismatch';
            }
        }elseif(count($journals)!==0||count($perf)!==0)
            $exceptions[]='financial_post_before_cycle_completion';

        // Phase 2: reconcile the exact V7 GL debit/credit lines as amounts,
        // not only the existence of a posted journal entry.
        // This still does not assert an externally verified bank or cashier.
        $gl=[];
        $glLineCount=0;
        $glIssues=[];
        if($completed&&count($journals)===1
            &&($journals[0]['status']??null)==='posted'
            &&self::id($journals[0]['branch_id']??null)===$branch){
            $header=self::id($journals[0]['id']??null);
            if($header<1)
                throw new DomainException('Invalid canonical GL header ID.','field_audit_source_invalid',500);
            $lines=$reader->journalLines($actor->companyId,$cycleId,$header);
            if(!is_array($lines)||count($lines)>20)
                throw new DomainException('Incomplete canonical GL journal lines.','field_audit_incomplete',409);
            $glLineCount=count($lines);
            $sumDr=0;$sumCr=0;$roles=[];$lineIds=[];
            foreach($lines as $l){
                $lineId=self::id($l['id']??null);
                $account=self::id($l['account_id']??null);
                $j=self::id($l['journal_entry_id']??null);
                $ac=self::id($l['account_company_id']??null);
                if($lineId<1||isset($lineIds[$lineId])||$account<1||$j!==$header||$ac!==$actor->companyId){
                    $glIssues[]='gl_foreign_or_duplicate_line';
                    continue;
                }
                $lineIds[$lineId]=true;
                $dr=self::money($l['debit']??null);$cr=self::money($l['credit']??null);
                if(($dr>0&&$cr>0)||($dr===0&&$cr===0&&strtoupper((string)($l['account_code']??''))!=='SALES')){
                    $glIssues[]='gl_invalid_debit_credit_direction';continue;
                }
                if($sumDr>PHP_INT_MAX-$dr||$sumCr>PHP_INT_MAX-$cr)
                    throw new DomainException('GL amount overflow.','field_audit_source_invalid',500);
                $sumDr+=$dr;$sumCr+=$cr;
                $code=strtoupper((string)($l['account_code']??''));
                $type=strtolower((string)($l['account_type']??''));
                $subtype=strtolower((string)($l['account_subtype']??''));
                $role=match(true){
                    $code==='SALES'=>'sales',
                    $code==='COGS'=>'cogs',
                    $code==='INVENTORY'=>'inventory',
                    $type==='asset'&&$subtype==='cash'=>'cash',
                    $type==='asset'&&$subtype==='upi'=>'upi',
                    default=>'unknown'
                };
                if($role==='unknown'||isset($roles[$role])){
                    $glIssues[]='gl_unknown_or_duplicate_account_role';
                    continue;
                }
                $roles[$role]=[$dr,$cr];
            }
            $amount=$closing!==null?self::money($closing['expected_amount']??null):0;
            $cash=$closing!==null?self::money($closing['cash_amount']??null):0;
            $upi=$closing!==null?self::money($closing['upi_amount']??null):0;
            if(($roles['cash']??[0,0])!==[$cash,0]
                ||($cash>0&&!isset($roles['cash'])))
                $glIssues[]='gl_cash_debit_mismatch';
            if(($roles['upi']??[0,0])!==[$upi,0]
                ||($upi>0&&!isset($roles['upi'])))
                $glIssues[]='gl_upi_debit_mismatch';
            if(($roles['sales']??null)!==[0,$amount])
                $glIssues[]='gl_sales_credit_mismatch';
            $costDr=$roles['cogs']??[0,0];
            $invCr=$roles['inventory']??[0,0];
            if(($costDr[1]??0)!==0||($invCr[0]??0)!==0
                ||$costDr[0]!==$invCr[1]||($costDr[0]>0&&
                (!isset($roles['cogs'])||!isset($roles['inventory']))))
                $glIssues[]='gl_cogs_inventory_mismatch';
            if($sumDr!==$sumCr)$glIssues[]='gl_unbalanced';
            if(!$lines)$glIssues[]='gl_lines_missing';
            $gl=['cash_debit_paise'=>$roles['cash'][0]??0,
                'upi_debit_paise'=>$roles['upi'][0]??0,
                'sales_credit_paise'=>$roles['sales'][1]??0,
                'cogs_debit_paise'=>$costDr[0],'inventory_credit_paise'=>$invCr[1],
                'total_debit_paise'=>$sumDr,'total_credit_paise'=>$sumCr];
            array_push($exceptions,...$glIssues);
        }elseif($completed){
            $exceptions[]='gl_lines_unavailable_without_valid_posted_header';
        }
        $exceptions=array_values(array_unique($exceptions));
        return [
            'read_only'=>true,'company_id'=>$actor->companyId,'branch_id'=>$branch,
            'employee_id'=>$employee,'daily_cycle_id'=>$cycleId,'cycle_status'=>$status,
            'state'=>$exceptions?'blocked_integrity_exception':($completed?'posted_stock_reconciled_financial_proof_pending':'open_cycle_not_finalized'),
            'stock_ledger_reconciled'=>!$exceptions&&count($issues)>0,
            'ready_for_production_financial_signoff'=>false,
            'issue_line_count'=>count($issues),'closing_line_count'=>count($seenClosing),
            'stock_movement_count'=>count($moves),
            'issued_milli'=>$issued,'sold_milli'=>$sold,'returned_milli'=>$returned,
            'journal_header_count'=>count($journals),'performance_entry_count'=>count($perf),
            'closing_sales_total_paise'=>$lineSalePaise,
            'closing_points_hundredths'=>$linePointHundredths,
            'closing_salary_fund_paise'=>$lineSalaryPaise,
            'closing_line_amounts_reconcile'=>$completed&&$closing!==null
                &&$lineSalePaise===self::money($closing['expected_amount']??null),
            'posted_performance_totals_reconcile'=>$completed&&count($perf)===1
                &&self::id($perf[0]['branch_id']??null)===$branch
                &&self::id($perf[0]['employee_id']??null)===$employee
                &&!in_array('employee_performance_points_mismatch',$exceptions,true)
                &&!in_array('employee_salary_fund_mismatch',$exceptions,true),
            'journal_line_count'=>$glLineCount,'canonical_gl_line_totals_match'=>$completed&&$glLineCount>0&&!$glIssues,
            'canonical_gl_totals_paise'=>$gl,
            'exceptions'=>$exceptions,'movement_differences'=>$diff,
            'snapshot_isolation_guaranteed'=>false,
            'journal_amounts_independently_verified'=>false,
            'physical_employee_cash_handover_verified'=>false,
            'upi_bank_settlement_verified'=>false,
            'warning'=>'This read-only audit compares canonical stock and GL line amounts only. It does not prove physical cashier remittance, independently verified bank settlement, or transaction-time MVCC consistency.',
        ];
    }

    private static function id(mixed $v):int {
        if(!is_scalar($v)||!preg_match('/^[1-9][0-9]*$/D',(string)$v)||strlen((string)$v)>18)
            return 0;
        return (int)$v;
    }
    private static function nullableId(mixed $v):?int {
        if($v===null)return null;
        $id=self::id($v);
        if($id<1)throw new DomainException('Invalid batch or custodian ID.','field_audit_source_invalid',500);
        return $id;
    }
    private static function milli(mixed $v):int {
        if(!is_string($v)&&!is_int($v))
            throw new DomainException('Invalid stock quantity.','field_audit_source_invalid',500);
        if(!preg_match('/^(0|[1-9][0-9]{0,11})(?:\.([0-9]{1,3}))?$/D',(string)$v,$m))
            throw new DomainException('Invalid stock precision or sign.','field_audit_source_invalid',500);
        return (int)$m[1]*1000+(int)str_pad($m[2]??'0',3,'0',STR_PAD_RIGHT);
    }
    private static function money(mixed $v):int {
        if(!is_string($v)&&!is_int($v)
            ||!preg_match('/^(0|[1-9][0-9]{0,11})(?:\.([0-9]{1,2}))?$/D',(string)$v,$m))
            throw new DomainException('Invalid money in posted settlement.','field_audit_source_invalid',500);
        return (int)$m[1]*100+(int)str_pad($m[2]??'0',2,'0',STR_PAD_RIGHT);
    }
}

final class DailyFieldStockAuditWpReader implements DailyFieldStockAuditReader {
    private function rows(string $sql,mixed ...$args):array {
        $db=Db::wpdb();$query=$db->prepare($sql,...$args);
        if(!is_string($query)||$query==='')throw new DomainException('Field audit query not prepared.','field_audit_query_failed',500);
        $result=$db->get_results($query,ARRAY_A);
        if(!is_array($result)||!empty($db->last_error))
            throw new DomainException('Field audit source unavailable.','field_audit_query_failed',500);
        return $result;
    }
    public function cycle(int $company,int $id):?array {
        $r=$this->rows('SELECT id,company_id,branch_id,employee_id,status FROM '.Db::table('daily_cycles').' WHERE company_id=%d AND id=%d LIMIT 2',$company,$id);
        return count($r)===1?$r[0]:null;
    }
    public function issues(int $company,int $id):array {
        return $this->rows('SELECT il.id,r.id request_id,r.status request_status,il.product_id,il.batch_id,il.quantity FROM '.Db::table('daily_issue_lines').' il JOIN '.Db::table('daily_requests').' r ON r.id=il.daily_request_id JOIN '.Db::table('daily_cycles').' c ON c.id=r.daily_cycle_id WHERE c.company_id=%d AND c.id=%d ORDER BY il.id LIMIT 251',$company,$id);
    }
    public function closing(int $company,int $id):array {
        return $this->rows('SELECT es.daily_cycle_id,es.status,es.expected_amount,es.cash_amount,es.upi_amount FROM '.Db::table('evening_settlements').' es JOIN '.Db::table('daily_cycles').' c ON c.id=es.daily_cycle_id WHERE c.company_id=%d AND c.id=%d LIMIT 2',$company,$id);
    }
    public function closingLines(int $company,int $id):array {
        return $this->rows('SELECT el.issue_line_id,el.product_id,el.batch_id,el.issued_quantity,el.return_quantity,el.retail_quantity,el.wholesale_quantity,el.total_amount,el.points,el.salary_fund FROM '.Db::table('evening_lines').' el JOIN '.Db::table('evening_settlements').' es ON es.id=el.evening_settlement_id JOIN '.Db::table('daily_cycles').' c ON c.id=es.daily_cycle_id WHERE c.company_id=%d AND c.id=%d ORDER BY el.id LIMIT 251',$company,$id);
    }
    public function movements(int $company,int $branch,int $cycle,array $requestIds):array {
        $in=implode(',',array_fill(0,count($requestIds),'%d'));
        $in=$in!==''?$in:'0';
        return $this->rows('SELECT id,company_id,branch_id,source_type,source_id,product_id,batch_id,custodian_employee_id,direction,quantity FROM '.Db::table('stock_ledger').' WHERE company_id=%d AND branch_id=%d AND ((source_type=\'daily_issue\' AND source_id IN ('.$in.')) OR (source_type IN (\'daily_sale\',\'daily_return\') AND source_id=%d)) ORDER BY id LIMIT 3001',...array_merge([$company,$branch],$requestIds,[$cycle]));
    }
    public function journalHeaders(int $company,int $id):array {
        return $this->rows('SELECT id,branch_id,status FROM '.Db::table('journal_entries')." WHERE company_id=%d AND source_type='daily_cycle' AND source_id=%d LIMIT 3",$company,$id);
    }
    public function journalLines(int $company,int $cycle,int $journalId):array {
        return $this->rows('SELECT jl.id,jl.journal_entry_id,jl.account_id,a.company_id account_company_id,'
            .'a.code account_code,a.type account_type,a.subtype account_subtype,jl.debit,jl.credit '
            .'FROM '.Db::table('journal_lines').' jl '
            .'JOIN '.Db::table('journal_entries').' je ON je.id=jl.journal_entry_id '
            .'LEFT JOIN '.Db::table('accounts').' a ON a.id=jl.account_id '
            ."WHERE je.company_id=%d AND je.source_type='daily_cycle' AND je.source_id=%d "
            .'AND je.id=%d ORDER BY jl.id LIMIT 21',$company,$cycle,$journalId);
    }
    public function performance(int $company,int $id):array {
        return $this->rows('SELECT id,branch_id,employee_id,points,salary_fund FROM '.Db::table('performance_entries')." WHERE company_id=%d AND source_type='daily_cycle' AND source_id=%d LIMIT 3",$company,$id);
    }
}
