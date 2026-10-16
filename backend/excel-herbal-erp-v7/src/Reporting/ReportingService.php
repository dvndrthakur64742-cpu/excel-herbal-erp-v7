<?php
namespace ExcelHerbal\ERP7\Reporting;
use ExcelHerbal\ERP7\Core\Input;use ExcelHerbal\ERP7\Database\Db;use ExcelHerbal\ERP7\Domain\DomainException;use ExcelHerbal\ERP7\Security\Actor;use ExcelHerbal\ERP7\Security\Capabilities;use ExcelHerbal\ERP7\Security\Guard;use ExcelHerbal\ERP7\Security\HierarchyScope;
final class ReportingService{
 public static function sales(Actor $a,int $branch,string $from,string $to):array{
  Guard::branch($a,$branch,Capabilities::REPORTS_VIEW);
  [$from,$to]=Input::dateRange($from,$to,'Sales report period');
  [$startUtc,$endUtc]=Input::utcBoundsForBusinessRange($from,$to,'Sales report period');
  $db=Db::wpdb();
  $rows=(array)$db->get_results($db->prepare(
   "SELECT id,sale_no reference,sale_date,gross_amount,paid_amount,outstanding_amount,status FROM ".Db::table('counter_sales').
   " WHERE company_id=%d AND branch_id=%d AND sale_date>=%s AND sale_date<%s ORDER BY sale_date DESC,id DESC",
   $a->companyId,$branch,$startUtc,$endUtc
  ),ARRAY_A);
  foreach($rows as&$row){
   $row['business_date']=get_date_from_gmt((string)$row['sale_date'],'Y-m-d');
   unset($row['sale_date']);
   $row['source_type']='counter_sale';
   $row['source_id']=(int)$row['id'];
  }
  unset($row);
  // Completed Daily Orders are posted directly to journals and stock; they
  // never create a counter_sale row. Include them once, from posted
  // settlements only, so the report reflects both independent sale sources.
  $daily=(array)$db->get_results($db->prepare(
   "SELECT c.id,c.business_date,es.expected_amount,es.cash_amount,es.upi_amount ".
   "FROM ".Db::table('daily_cycles')." c ".
   "JOIN ".Db::table('evening_settlements')." es ON es.daily_cycle_id=c.id AND es.status='posted' ".
   "WHERE c.company_id=%d AND c.branch_id=%d AND c.status='completed' ".
   "AND c.business_date BETWEEN %s AND %s ORDER BY c.business_date DESC,c.id DESC",
   $a->companyId,$branch,$from,$to
  ),ARRAY_A);
  foreach($daily as$cycle){
   $id=(int)$cycle['id'];
   $gross=round((float)$cycle['expected_amount'],2);
   $paid=round((float)$cycle['cash_amount']+(float)$cycle['upi_amount'],2);
   $rows[]=[
    'id'=>'daily_order:'.$id,
    'reference'=>'DO-'.$id,
    'gross_amount'=>$gross,
    'paid_amount'=>$paid,
    'outstanding_amount'=>round($gross-$paid,2),
    'status'=>'posted',
    'business_date'=>(string)$cycle['business_date'],
    'source_type'=>'daily_order',
    'source_id'=>$id,
   ];
  }
  usort($rows,static function(array $a,array $b):int{
   $byDate=strcmp((string)$b['business_date'],(string)$a['business_date']);
   return $byDate!==0?$byDate:strcmp((string)$b['reference'],(string)$a['reference']);
  });
  return $rows;
 }
 public static function purchase(Actor $a,int $branch,string $from,string $to):array{Guard::branch($a,$branch,Capabilities::REPORTS_VIEW);[$from,$to]=Input::dateRange($from,$to,'Purchase report period');$db=Db::wpdb();return(array)$db->get_results($db->prepare("SELECT b.*,s.name supplier_name FROM ".Db::table('purchase_bills')." b JOIN ".Db::table('suppliers')." s ON s.id=b.supplier_id WHERE b.company_id=%d AND b.branch_id=%d AND b.bill_date BETWEEN %s AND %s ORDER BY b.bill_date DESC,b.id DESC",$a->companyId,$branch,$from,$to),ARRAY_A);}
 public static function stock(Actor $a,int $branch):array{Guard::branch($a,$branch,Capabilities::REPORTS_VIEW);$db=Db::wpdb();return(array)$db->get_results($db->prepare("SELECT sb.*,p.sku,p.name product_name,b.batch_no,e.full_name custodian_name FROM ".Db::table('stock_balances')." sb JOIN ".Db::table('products')." p ON p.id=sb.product_id LEFT JOIN ".Db::table('batches')." b ON b.id=NULLIF(sb.batch_key,0) LEFT JOIN ".Db::table('employees')." e ON e.id=NULLIF(sb.custodian_key,0) WHERE sb.company_id=%d AND sb.branch_id=%d AND ABS(sb.quantity)>.0001 ORDER BY p.name,b.batch_no",$a->companyId,$branch),ARRAY_A);}
 public static function finance(Actor $a,int $branch,string $from,string $to):array{Guard::branch($a,$branch,Capabilities::REPORTS_VIEW);[$from,$to]=Input::dateRange($from,$to,'Finance report period');$db=Db::wpdb();return(array)$db->get_results($db->prepare("SELECT je.id,je.entry_no,je.entry_date,je.source_type,je.source_id,je.status,je.memo,SUM(jl.debit) debit,SUM(jl.credit) credit FROM ".Db::table('journal_entries')." je JOIN ".Db::table('journal_lines')." jl ON jl.journal_entry_id=je.id WHERE je.company_id=%d AND je.branch_id=%d AND DATE(je.entry_date) BETWEEN %s AND %s GROUP BY je.id ORDER BY je.entry_date DESC,je.id DESC",$a->companyId,$branch,$from,$to),ARRAY_A);}

 public static function trialBalance(Actor $a,string $to,?int $branch):array{
  Guard::cap($a,Capabilities::ACCOUNTING_VIEW);$to=Input::date($to,'Trial Balance date');$db=Db::wpdb();[$scope,$scopeArgs]=self::journalScope($a,$branch,'je.branch_id');
  $sql="SELECT ac.id,ac.code,ac.name,ac.type,COALESCE(SUM(CASE WHEN je.id IS NOT NULL THEN jl.debit ELSE 0 END),0) debit,COALESCE(SUM(CASE WHEN je.id IS NOT NULL THEN jl.credit ELSE 0 END),0) credit,COALESCE(SUM(CASE WHEN je.id IS NOT NULL THEN jl.debit-jl.credit ELSE 0 END),0) balance FROM ".Db::table('accounts')." ac LEFT JOIN ".Db::table('journal_lines')." jl ON jl.account_id=ac.id LEFT JOIN ".Db::table('journal_entries')." je ON je.id=jl.journal_entry_id AND je.company_id=%d AND je.status IN ('posted','reversed') AND DATE(je.entry_date)<=%s {$scope} WHERE ac.company_id=%d AND ac.active=1 GROUP BY ac.id ORDER BY ac.code";
  $args=array_merge([$a->companyId,$to],$scopeArgs,[$a->companyId]);return(array)$db->get_results($db->prepare($sql,...$args),ARRAY_A);
 }
 public static function ledger(Actor $a,int $account,string $from,string $to,?int $branch):array{
  Guard::cap($a,Capabilities::ACCOUNTING_VIEW);[$from,$to]=Input::dateRange($from,$to,'Ledger period');$db=Db::wpdb();[$scope,$scopeArgs]=self::journalScope($a,$branch,'je.branch_id');
  $accountExists=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('accounts')." WHERE id=%d AND company_id=%d AND active=1",$account,$a->companyId));if(!$accountExists)throw new DomainException('Ledger account not found.','ledger_account_not_found',404);
  $sql="SELECT je.entry_no,je.entry_date,je.source_type,je.source_id,je.memo,jl.debit,jl.credit,jl.party_type,jl.party_id,jl.description FROM ".Db::table('journal_lines')." jl JOIN ".Db::table('journal_entries')." je ON je.id=jl.journal_entry_id WHERE je.company_id=%d AND jl.account_id=%d AND je.status IN ('posted','reversed') AND DATE(je.entry_date) BETWEEN %s AND %s {$scope} ORDER BY je.entry_date,je.id,jl.id";
  return(array)$db->get_results($db->prepare($sql,...array_merge([$a->companyId,$account,$from,$to],$scopeArgs)),ARRAY_A);
 }

 public static function profitLoss(Actor $a,string $from,string $to,?int $branch):array{
  Guard::cap($a,Capabilities::ACCOUNTING_VIEW);[$from,$to]=Input::dateRange($from,$to,'Profit and Loss period');$db=Db::wpdb();[$scope,$scopeArgs]=self::journalScope($a,$branch,'je.branch_id');
  $sql="SELECT ac.id,ac.code,ac.name,ac.type,ac.subtype,COALESCE(SUM(CASE WHEN je.id IS NULL THEN 0 WHEN ac.type='income' THEN jl.credit-jl.debit ELSE jl.debit-jl.credit END),0) amount FROM ".Db::table('accounts')." ac LEFT JOIN ".Db::table('journal_lines')." jl ON jl.account_id=ac.id LEFT JOIN ".Db::table('journal_entries')." je ON je.id=jl.journal_entry_id AND je.company_id=%d AND je.status IN ('posted','reversed') AND DATE(je.entry_date) BETWEEN %s AND %s {$scope} WHERE ac.company_id=%d AND ac.active=1 AND ac.type IN ('income','expense') GROUP BY ac.id ORDER BY FIELD(ac.type,'income','expense'),ac.code";
  $args=array_merge([$a->companyId,$from,$to],$scopeArgs,[$a->companyId]);$rows=(array)$db->get_results($db->prepare($sql,...$args),ARRAY_A);foreach($rows as&$r){$r['section']=$r['type']==='income'?'Income':'Expenses';$r['amount']=round((float)$r['amount'],2);}return$rows;
 }
 public static function balanceSheet(Actor $a,string $to,?int $branch):array{
  Guard::cap($a,Capabilities::ACCOUNTING_VIEW);$to=Input::date($to,'Balance Sheet date');$db=Db::wpdb();[$scope,$scopeArgs]=self::journalScope($a,$branch,'je.branch_id');
  $sql="SELECT ac.id,ac.code,ac.name,ac.type,ac.subtype,COALESCE(SUM(CASE WHEN je.id IS NULL THEN 0 WHEN ac.type='asset' THEN jl.debit-jl.credit ELSE jl.credit-jl.debit END),0) amount FROM ".Db::table('accounts')." ac LEFT JOIN ".Db::table('journal_lines')." jl ON jl.account_id=ac.id LEFT JOIN ".Db::table('journal_entries')." je ON je.id=jl.journal_entry_id AND je.company_id=%d AND je.status IN ('posted','reversed') AND DATE(je.entry_date)<=%s {$scope} WHERE ac.company_id=%d AND ac.active=1 AND ac.type IN ('asset','liability','equity') GROUP BY ac.id ORDER BY FIELD(ac.type,'asset','liability','equity'),ac.code";
  $args=array_merge([$a->companyId,$to],$scopeArgs,[$a->companyId]);$rows=(array)$db->get_results($db->prepare($sql,...$args),ARRAY_A);foreach($rows as&$r){$r['section']=$r['type']==='asset'?'Assets':($r['type']==='liability'?'Liabilities':'Equity');$r['amount']=round((float)$r['amount'],2);}unset($r);
  $pl=self::profitLoss($a,'1900-01-01',$to,$branch);$earnings=0.0;foreach($pl as$r)$earnings+=($r['type']==='income'?1:-1)*(float)$r['amount'];$rows[]=['id'=>0,'code'=>'CURRENT_EARNINGS','name'=>'Current Earnings','type'=>'equity','subtype'=>'current_earnings','section'=>'Equity','amount'=>round($earnings,2),'virtual'=>1];return$rows;
 }
 public static function receivables(Actor $a,?int $branch):array{
  Guard::cap($a,Capabilities::ACCOUNTING_VIEW);$db=Db::wpdb();[$scope,$scopeArgs]=self::documentScope($a,$branch,'s.branch_id');
  $sql="SELECT s.id,s.sale_no reference,s.sale_date,c.name customer_name,s.gross_amount,s.paid_amount,s.outstanding_amount FROM ".Db::table('counter_sales')." s LEFT JOIN ".Db::table('parties')." c ON c.id=s.customer_id WHERE s.company_id=%d AND s.status='posted' AND s.outstanding_amount>.005 {$scope} ORDER BY s.sale_date,s.id";
  $rows=(array)$db->get_results($db->prepare($sql,...array_merge([$a->companyId],$scopeArgs)),ARRAY_A);$today=Db::today();foreach($rows as&$r){$r['business_date']=get_date_from_gmt((string)$r['sale_date'],'Y-m-d');unset($r['sale_date']);self::applyAge($r,$today,(string)$r['business_date']);}unset($r);return$rows;
 }
 public static function payables(Actor $a,?int $branch):array{
  Guard::cap($a,Capabilities::ACCOUNTING_VIEW);$db=Db::wpdb();[$scope,$scopeArgs]=self::documentScope($a,$branch,'b.branch_id');
  $sql="SELECT b.id,b.bill_no reference,b.bill_date business_date,s.name supplier_name,b.total_amount,b.paid_amount,b.outstanding_amount FROM ".Db::table('purchase_bills')." b JOIN ".Db::table('suppliers')." s ON s.id=b.supplier_id WHERE b.company_id=%d AND b.status='posted' AND b.outstanding_amount>.005 {$scope} ORDER BY b.bill_date,b.id";
  $rows=(array)$db->get_results($db->prepare($sql,...array_merge([$a->companyId],$scopeArgs)),ARRAY_A);$today=Db::today();foreach($rows as&$r)self::applyAge($r,$today,(string)$r['business_date']);unset($r);return$rows;
 }
 public static function stockReconciliation(Actor $a,int $branch):array{
  Guard::branch($a,$branch,Capabilities::REPORTS_VIEW);$db=Db::wpdb();$sb=Db::table('stock_balances');$sl=Db::table('stock_ledger');$p=Db::table('products');$ba=Db::table('batches');$e=Db::table('employees');
  $sql="SELECT k.product_id,k.batch_key,k.custodian_key,p.sku,p.name product_name,b.batch_no,e.full_name custodian_name,COALESCE(sb.quantity,0) balance_quantity,COALESCE(l.ledger_quantity,0) ledger_quantity,ROUND(COALESCE(sb.quantity,0)-COALESCE(l.ledger_quantity,0),3) difference_quantity,COALESCE(sb.average_unit_cost,0) average_unit_cost,ROUND((COALESCE(sb.quantity,0)-COALESCE(l.ledger_quantity,0))*COALESCE(sb.average_unit_cost,0),2) difference_value,CASE WHEN ABS(COALESCE(sb.quantity,0)-COALESCE(l.ledger_quantity,0))<=.0005 THEN 'matched' ELSE 'mismatch' END status FROM (SELECT product_id,batch_key,custodian_key FROM {$sb} WHERE company_id=%d AND branch_id=%d UNION SELECT product_id,COALESCE(batch_id,0),COALESCE(custodian_employee_id,0) FROM {$sl} WHERE company_id=%d AND branch_id=%d) k JOIN {$p} p ON p.id=k.product_id LEFT JOIN {$sb} sb ON sb.company_id=%d AND sb.branch_id=%d AND sb.product_id=k.product_id AND sb.batch_key=k.batch_key AND sb.custodian_key=k.custodian_key LEFT JOIN (SELECT product_id,COALESCE(batch_id,0) batch_key,COALESCE(custodian_employee_id,0) custodian_key,SUM(CASE WHEN direction='IN' THEN quantity ELSE -quantity END) ledger_quantity FROM {$sl} WHERE company_id=%d AND branch_id=%d GROUP BY product_id,COALESCE(batch_id,0),COALESCE(custodian_employee_id,0)) l ON l.product_id=k.product_id AND l.batch_key=k.batch_key AND l.custodian_key=k.custodian_key LEFT JOIN {$ba} b ON b.id=NULLIF(k.batch_key,0) LEFT JOIN {$e} e ON e.id=NULLIF(k.custodian_key,0) ORDER BY status DESC,p.name,b.batch_no,e.full_name";
  return(array)$db->get_results($db->prepare($sql,$a->companyId,$branch,$a->companyId,$branch,$a->companyId,$branch,$a->companyId,$branch),ARRAY_A);
 }
 public static function financeReconciliation(Actor $a,?int $branch):array{
  Guard::cap($a,Capabilities::ACCOUNTING_VIEW);$db=Db::wpdb();[$journalScope,$jArgs]=self::journalScope($a,$branch,'je.branch_id');[$saleScope,$sArgs]=self::documentScope($a,$branch,'s.branch_id');[$billScope,$bArgs]=self::documentScope($a,$branch,'b.branch_id');[$stockScope,$stArgs]=self::documentScope($a,$branch,'sb.branch_id');[$quarantineScope,$qArgs]=self::documentScope($a,$branch,'q.branch_id');
  $accountBalance=function(string $code,string $normal)use($db,$a,$journalScope,$jArgs):float{$sql="SELECT COALESCE(SUM(CASE WHEN %s='credit' THEN jl.credit-jl.debit ELSE jl.debit-jl.credit END),0) FROM ".Db::table('journal_lines')." jl JOIN ".Db::table('journal_entries')." je ON je.id=jl.journal_entry_id JOIN ".Db::table('accounts')." ac ON ac.id=jl.account_id WHERE je.company_id=%d AND ac.company_id=%d AND ac.code=%s AND je.status IN ('posted','reversed') {$journalScope}";$args=array_merge([$normal,$a->companyId,$a->companyId,$code],$jArgs);return round((float)$db->get_var($db->prepare($sql,...$args)),2);};
  $arBook=$accountBalance('AR','debit');$apBook=$accountBalance('AP','credit');$invBook=$accountBalance('INVENTORY','debit');
  $arSub=(float)$db->get_var($db->prepare("SELECT COALESCE(SUM(s.outstanding_amount),0) FROM ".Db::table('counter_sales')." s WHERE s.company_id=%d AND s.status='posted' {$saleScope}",...array_merge([$a->companyId],$sArgs)));
  $apSub=(float)$db->get_var($db->prepare("SELECT COALESCE(SUM(b.outstanding_amount),0) FROM ".Db::table('purchase_bills')." b WHERE b.company_id=%d AND b.status='posted' {$billScope}",...array_merge([$a->companyId],$bArgs)));
  $stockValue=(float)$db->get_var($db->prepare("SELECT COALESCE(SUM(sb.quantity*sb.average_unit_cost),0) FROM ".Db::table('stock_balances')." sb WHERE sb.company_id=%d {$stockScope}",...array_merge([$a->companyId],$stArgs)));$quarantineValue=(float)$db->get_var($db->prepare("SELECT COALESCE(SUM(q.quantity*q.unit_cost_snapshot),0) FROM ".Db::table('stock_quarantine')." q WHERE q.company_id=%d AND q.status='open' {$quarantineScope}",...array_merge([$a->companyId],$qArgs)));$stockValue=round($stockValue+$quarantineValue,2);
  $unbalancedSql="SELECT COUNT(*) FROM (SELECT je.id FROM ".Db::table('journal_entries')." je JOIN ".Db::table('journal_lines')." jl ON jl.journal_entry_id=je.id WHERE je.company_id=%d AND je.status IN ('posted','reversed') {$journalScope} GROUP BY je.id HAVING ABS(SUM(jl.debit)-SUM(jl.credit))>.005) x";$unbalanced=(int)$db->get_var($db->prepare($unbalancedSql,...array_merge([$a->companyId],$jArgs)));
  return[self::check('Accounts Receivable','AR Ledger',$arBook,'Open Customer Sales',round($arSub,2)),self::check('Accounts Payable','AP Ledger',$apBook,'Open Supplier Bills',round($apSub,2)),self::check('Inventory Value','Inventory Ledger',$invBook,'Stock Balance Value',round($stockValue,2)),['check_name'=>'Journal Balance','book_label'=>'Unbalanced Entries','book_value'=>$unbalanced,'control_label'=>'Expected','control_value'=>0,'difference'=>$unbalanced,'status'=>$unbalanced===0?'matched':'mismatch']];
 }

 public static function priceDistribution(Actor $a,?int $branch,string $from,string $to,?int $employeeId=null,string $reportingCategory=''):array{
  Guard::cap($a,Capabilities::REPORTS_VIEW);$from=trim($from);$to=trim($to);if($from==='')$from=current_time('Y-m').'-01';if($to==='')$to=Db::today();[$from,$to]=Input::dateRange($from,$to,'Price Distribution period');$branch=$branch&&$branch>0?$branch:null;if($branch!==null&&!in_array($branch,$a->branchIds,true)&&!in_array(HierarchyScope::normaliseCode($a->designationCode),['ZI','ZONAL_INSPECTOR','CM','CHAIRMAN','CHAIRMAN_MANAGING_DIRECTOR','MD','MANAGING_DIRECTOR','SYSADMIN','SYSTEM_ADMIN','ADMIN','ADMINISTRATOR'],true))throw new DomainException('Branch is outside effective authority.','branch_forbidden',403);
  $ids=HierarchyScope::visibleEmployeeIds($a,$branch);if($employeeId){HierarchyScope::assertCanViewEmployee($a,$employeeId);if(!in_array($employeeId,$ids,true))throw new DomainException('Employee is outside selected branch scope.','employee_scope_forbidden',403);$ids=[$employeeId];}if(!$ids)return['period'=>['from'=>$from,'to'=>$to],'rows'=>[],'totals'=>self::priceTotals([])];
  $db=Db::wpdb();$ph=implode(',',array_fill(0,count($ids),'%d'));$sql="SELECT c.branch_id,c.employee_id,e.employee_code,e.full_name,e.designation_code,e.reporting_designation_code,COUNT(DISTINCT c.business_date) sale_days,ROUND(SUM(el.total_amount),2) sale_price,ROUND(SUM(el.ho_amount),2) ho_amount,ROUND(SUM(el.bm_profit),2) bm_profit,ROUND(SUM(el.salary_fund),2) salary_fund,ROUND(SUM(el.office_expense),2) expense,ROUND(SUM(el.points),2) points FROM ".Db::table('daily_cycles')." c JOIN ".Db::table('employees')." e ON e.id=c.employee_id AND e.company_id=c.company_id JOIN ".Db::table('evening_settlements')." es ON es.daily_cycle_id=c.id AND es.status='posted' JOIN ".Db::table('evening_lines')." el ON el.evening_settlement_id=es.id WHERE c.company_id=%d AND c.status='completed' AND c.business_date BETWEEN %s AND %s AND c.employee_id IN ({$ph}) GROUP BY c.branch_id,c.employee_id,e.employee_code,e.full_name,e.designation_code,e.reporting_designation_code ORDER BY sale_price DESC,e.full_name";$args=array_merge([$a->companyId,$from,$to],$ids);$rows=(array)$db->get_results($db->prepare($sql,...$args),ARRAY_A);
  $category=HierarchyScope::normaliseCode($reportingCategory);foreach($rows as&$r)$r['reporting_category']=HierarchyScope::reportingCategoryForCode((string)$r['designation_code'],(string)($r['reporting_designation_code']??''));unset($r);if($category!=='')$rows=array_values(array_filter($rows,fn($r)=>$r['reporting_category']===$category));return['period'=>['from'=>$from,'to'=>$to],'rows'=>$rows,'totals'=>self::priceTotals($rows),'fields'=>['sale_price','ho_amount','bm_profit','salary_fund','expense','points']];
 }
 private static function priceTotals(array $rows):array{$out=['sale_price'=>0.0,'ho_amount'=>0.0,'bm_profit'=>0.0,'salary_fund'=>0.0,'expense'=>0.0,'points'=>0.0];foreach($rows as$r)foreach($out as$k=>$v)$out[$k]+=round((float)($r[$k]??0),2);foreach($out as$k=>$v)$out[$k]=round($v,2);return$out;}

 private static function applyAge(array &$row,string $today,string $businessDate):void{$a=new \DateTimeImmutable($businessDate);$b=new \DateTimeImmutable($today);$days=max(0,(int)$a->diff($b)->format('%r%a'));$row['age_days']=$days;$row['age_bucket']=$days<=30?'0-30 Days':($days<=60?'31-60 Days':($days<=90?'61-90 Days':'90+ Days'));}
 private static function check(string $name,string $bookLabel,float $book,string $controlLabel,float $control):array{$diff=round($book-$control,2);return['check_name'=>$name,'book_label'=>$bookLabel,'book_value'=>$book,'control_label'=>$controlLabel,'control_value'=>$control,'difference'=>$diff,'status'=>abs($diff)<=.01?'matched':'mismatch'];}
 private static function journalScope(Actor $a,?int $branch,string $column):array{return self::scope($a,$branch,$column,Capabilities::ACCOUNTING_VIEW);}
 private static function documentScope(Actor $a,?int $branch,string $column):array{return self::scope($a,$branch,$column,Capabilities::ACCOUNTING_VIEW);}
 private static function scope(Actor $a,?int $branch,string $column,string $cap):array{Guard::cap($a,$cap);if($branch!==null&&$branch>0){Guard::branch($a,$branch,$cap);return[" AND {$column}=%d",[$branch]];}$ids=array_values(array_unique(array_filter(array_map('intval',$a->branchIds),fn($id)=>$id>0)));if(!$ids)throw new DomainException('No authorised branch scope.','branch_scope_empty',403);$placeholders=implode(',',array_fill(0,count($ids),'%d'));return[" AND {$column} IN ({$placeholders})",$ids];}
}
