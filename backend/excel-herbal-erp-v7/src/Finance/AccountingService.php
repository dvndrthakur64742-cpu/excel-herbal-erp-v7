<?php
namespace ExcelHerbal\ERP7\Finance;
use ExcelHerbal\ERP7\Core\Input;
use ExcelHerbal\ERP7\Core\NumberSeries;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;

final class AccountingService{
 public static function accountByCode(Actor $a,string $code):array{$db=Db::wpdb();$r=$db->get_row($db->prepare("SELECT * FROM ".Db::table('accounts')." WHERE company_id=%d AND code=%s AND active=1",$a->companyId,$code),ARRAY_A);if(!$r)throw new DomainException('Required account missing: '.$code,'account_missing',409);return$r;}
 public static function account(Actor $a,int $id):array{$db=Db::wpdb();$r=$db->get_row($db->prepare("SELECT * FROM ".Db::table('accounts')." WHERE company_id=%d AND id=%d AND active=1",$a->companyId,$id),ARRAY_A);if(!$r)throw new DomainException('Active account not found.','account_invalid',422);return$r;}
 public static function paymentAccount(Actor $a,int $id):array{$r=self::account($a,$id);$sub=strtolower(trim((string)($r['subtype']??'')));if((string)$r['type']!=='asset'||!in_array($sub,['cash','bank','upi'],true))throw new DomainException('Payment account must be Cash, Bank or UPI ledger.','payment_account_invalid',422);return$r;}
 public static function bankAccount(Actor $a,int $id):array{$r=self::paymentAccount($a,$id);$sub=strtolower(trim((string)($r['subtype']??'')));if(!in_array($sub,['bank','upi'],true))throw new DomainException('Bank reconciliation requires Bank or UPI ledger.','bank_account_invalid',422);return$r;}
 public static function assertPeriodOpen(Actor $a,string $date):void{$businessDate=Input::date(substr(trim($date),0,10),'Journal business date');$db=Db::wpdb();if((int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('accounting_periods')." WHERE company_id=%d AND status='closed' AND %s BETWEEN period_start AND period_end",$a->companyId,$businessDate)))throw new DomainException('Accounting period closed.','accounting_period_closed',409);}

 private static function sourceTable(string $source):string{
  $map=['counter_sale'=>'counter_sales','customer_receipt'=>'customer_receipts','daily_cycle'=>'daily_cycles','expense'=>'expenses','payroll'=>'payroll_runs','payroll_payment'=>'payroll_runs','purchase_bill'=>'purchase_bills','supplier_payment'=>'supplier_payments','stock_transfer_dispatch'=>'stock_transfers','stock_transfer_receive'=>'stock_transfers','stock_transfer_cancel'=>'stock_transfers','stock_transfer_variance'=>'stock_transfers','stock_adjustment'=>'stock_adjustments','stock_quarantine_writeoff'=>'stock_quarantine','reversal'=>'reversals'];
  if(!isset($map[$source]))throw new DomainException('Unsupported journal source.','journal_source_invalid',422);
  return $map[$source];
 }
 private static function lockSource(Actor $a,string $source,int $sourceId):void{
  $db=Db::wpdb();$table=Db::table(self::sourceTable($source));
  $id=$db->get_var($db->prepare("SELECT id FROM {$table} WHERE id=%d AND company_id=%d FOR UPDATE",$sourceId,$a->companyId));
  if(!$id)throw new DomainException('Journal source not found.','journal_source_not_found',404);
 }

 public static function post(Actor $a,?int $branch,string $source,int $sourceId,string $date,array $lines,string $memo=''):int{
  self::assertPeriodOpen($a,$date);if(count($lines)<2)throw new DomainException('Journal needs at least two lines.');
  $dr=0.0;$cr=0.0;foreach($lines as$l){self::account($a,(int)$l['account_id']);$d=round((float)($l['debit']??0),2);$c=round((float)($l['credit']??0),2);if(($d>0)==($c>0))throw new DomainException('Each journal line must be debit or credit.');$dr+=$d;$cr+=$c;}if(abs($dr-$cr)>.005)throw new DomainException('Journal not balanced.','journal_unbalanced',409);
  return Transaction::run(function()use($a,$branch,$source,$sourceId,$date,$lines,$memo){
   $db=Db::wpdb();$h=Db::table('journal_entries');
   self::lockSource($a,$source,$sourceId);
   $existing=(int)$db->get_var($db->prepare("SELECT id FROM {$h} WHERE company_id=%d AND source_type=%s AND source_id=%d AND status='posted' ORDER BY id DESC LIMIT 1 FOR UPDATE",$a->companyId,$source,$sourceId));
   if($existing)return$existing;
   $no=NumberSeries::next($a->companyId,'journal','JE-');
   Db::mustInsert($db,$h,['company_id'=>$a->companyId,'branch_id'=>$branch,'entry_no'=>$no,'entry_date'=>$date,'source_type'=>$source,'source_id'=>$sourceId,'status'=>'posted','memo'=>$memo,'created_by'=>$a->employeeId,'created_at'=>Db::now()]);
   $id=(int)$db->insert_id;if(!$id)throw new DomainException('Journal header insert failed.','journal_store_failed',500);
   foreach($lines as$l)Db::mustInsert($db,Db::table('journal_lines'),['journal_entry_id'=>$id,'account_id'=>(int)$l['account_id'],'debit'=>round((float)($l['debit']??0),2),'credit'=>round((float)($l['credit']??0),2),'party_type'=>$l['party_type']??null,'party_id'=>$l['party_id']??null,'description'=>$l['description']??null]);
   return$id;
  });
 }
 public static function reverse(Actor $a,int $journalId,string $reason,int $reversalId):int{$db=Db::wpdb();$h=Db::table('journal_entries');$r=$db->get_row($db->prepare("SELECT * FROM {$h} WHERE id=%d AND company_id=%d AND status='posted'",$journalId,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Posted journal not found.');$rows=(array)$db->get_results($db->prepare("SELECT * FROM ".Db::table('journal_lines')." WHERE journal_entry_id=%d ORDER BY id",$journalId),ARRAY_A);$lines=[];foreach($rows as$l)$lines[]=['account_id'=>(int)$l['account_id'],'debit'=>(float)$l['credit'],'credit'=>(float)$l['debit'],'party_type'=>$l['party_type'],'party_id'=>$l['party_id'],'description'=>'Reversal: '.$reason];$new=self::post($a,$r['branch_id']!==null?(int)$r['branch_id']:null,'reversal',$reversalId,Db::businessNow(),$lines,'Reversal '.$r['entry_no'].' '.$reason);Db::mustUpdate($db,$h,['reversal_of'=>$journalId],['id'=>$new]);Db::mustUpdate($db,$h,['status'=>'reversed'],['id'=>$journalId]);return$new;}
}
