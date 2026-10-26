<?php
namespace ExcelHerbal\ERP7\Inventory;
use ExcelHerbal\ERP7\Database\Db;use ExcelHerbal\ERP7\Finance\AccountingService;use ExcelHerbal\ERP7\Finance\BranchDayGuard;use ExcelHerbal\ERP7\Database\Transaction;use ExcelHerbal\ERP7\Domain\DomainException;use ExcelHerbal\ERP7\Security\Actor;use ExcelHerbal\ERP7\Security\Audit;use ExcelHerbal\ERP7\Security\Capabilities;use ExcelHerbal\ERP7\Security\Guard;
final class InventoryService{
 public static function stock(Actor $a,int $branch):array{Guard::branch($a,$branch,Capabilities::INVENTORY_VIEW);$db=Db::wpdb();return(array)$db->get_results($db->prepare("SELECT sb.*,p.sku,p.name product_name,p.uom,p.batch_tracking,b.batch_no,b.expires_on,e.full_name custodian_name FROM ".Db::table('stock_balances')." sb JOIN ".Db::table('products')." p ON p.id=sb.product_id LEFT JOIN ".Db::table('batches')." b ON b.id=NULLIF(sb.batch_key,0) LEFT JOIN ".Db::table('employees')." e ON e.id=NULLIF(sb.custodian_key,0) WHERE sb.company_id=%d AND sb.branch_id=%d AND ABS(sb.quantity)>.0001 ORDER BY p.name,b.batch_no,e.full_name",$a->companyId,$branch),ARRAY_A);}
 public static function transfers(Actor $a,int $branch):array{Guard::branch($a,$branch,Capabilities::INVENTORY_VIEW);$db=Db::wpdb();return(array)$db->get_results($db->prepare("SELECT * FROM ".Db::table('stock_transfers')." WHERE company_id=%d AND (source_branch_id=%d OR destination_branch_id=%d) ORDER BY id DESC LIMIT 200",$a->companyId,$branch,$branch),ARRAY_A);}
 public static function transferDetail(Actor $a,int $id):array{$db=Db::wpdb();$r=$db->get_row($db->prepare("SELECT * FROM ".Db::table('stock_transfers')." WHERE id=%d AND company_id=%d",$id,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Transfer not found.','transfer_not_found',404);if(!$a->hasBranch((int)$r['source_branch_id'])&&!$a->hasBranch((int)$r['destination_branch_id']))throw new DomainException('Transfer outside branch authority.','branch_forbidden',403);Guard::any($a,[Capabilities::INVENTORY_VIEW,Capabilities::TRANSFER_CREATE,Capabilities::TRANSFER_RECEIVE,Capabilities::TRANSFER_CANCEL,Capabilities::ADJ_APPROVE]);$lines=(array)$db->get_results($db->prepare("SELECT l.*,p.name product_name,p.uom,b.batch_no,b.expires_on FROM ".Db::table('stock_transfer_lines')." l JOIN ".Db::table('products')." p ON p.id=l.product_id LEFT JOIN ".Db::table('batches')." b ON b.id=l.batch_id WHERE l.transfer_id=%d ORDER BY l.id",$id),ARRAY_A);return['transfer'=>$r,'lines'=>$lines];}
 public static function adjustments(Actor $a,int $branch):array{Guard::branch($a,$branch,Capabilities::INVENTORY_VIEW);$db=Db::wpdb();return(array)$db->get_results($db->prepare("SELECT * FROM ".Db::table('stock_adjustments')." WHERE company_id=%d AND branch_id=%d ORDER BY id DESC LIMIT 200",$a->companyId,$branch),ARRAY_A);}
 public static function createTransfer(Actor $a,int $source,int $dest,array $lines,string $notes):array{Guard::branch($a,$source,Capabilities::TRANSFER_CREATE);BranchDayGuard::assertOpen($a,$source,Db::today());if(!$a->hasBranch($dest))throw new DomainException('Destination branch outside authority.','branch_forbidden',403);BranchDayGuard::assertOpen($a,$dest,Db::today());if($source===$dest||!$lines)throw new DomainException('Valid source, destination and lines required.');return Transaction::run(function()use($a,$source,$dest,$lines,$notes){$db=Db::wpdb();Db::mustInsert($db,Db::table('stock_transfers'),['company_id'=>$a->companyId,'source_branch_id'=>$source,'destination_branch_id'=>$dest,'status'=>'draft','created_by'=>$a->employeeId,'created_at'=>Db::now(),'notes'=>$notes]);$id=(int)$db->insert_id;$seen=[];foreach($lines as$x){$p=(int)($x['product_id']??0);$b=isset($x['batch_id'])?(int)$x['batch_id']:null;$rawQty=(float)($x['quantity']??0);if(!is_finite($rawQty))throw new DomainException('Transfer quantity must be finite.','transfer_quantity_invalid',422);$q=round($rawQty,3);if(!$p||$q<=0)throw new DomainException('Invalid transfer line.');$key=$p.'|'.($b?:0);if(isset($seen[$key]))throw new DomainException('Duplicate product/batch line.');$seen[$key]=1;$product=StockService::product($a,$p);StockService::validateBatch($a,$product,$b,true);Db::mustInsert($db,Db::table('stock_transfer_lines'),['transfer_id'=>$id,'product_id'=>$p,'batch_id'=>$b,'quantity'=>$q]);}Audit::add($a,'stock_transfer.create','stock_transfer',$id,['branch_id'=>$source,'destination_branch_id'=>$dest]);return['id'=>$id,'status'=>'draft'];});}
 public static function transferAction(Actor $a,int $id,string $action,array $payload=[]):array{
  return Transaction::run(function()use($a,$id,$action,$payload){
   $db=Db::wpdb();$h=Db::table('stock_transfers');
   $r=$db->get_row($db->prepare("SELECT * FROM {$h} WHERE id=%d AND company_id=%d FOR UPDATE",$id,$a->companyId),ARRAY_A);
   if(!$r)throw new DomainException('Transfer not found.','transfer_not_found',404);
   $source=(int)$r['source_branch_id'];$dest=(int)$r['destination_branch_id'];
   $lines=(array)$db->get_results($db->prepare("SELECT * FROM ".Db::table('stock_transfer_lines')." WHERE transfer_id=%d ORDER BY id",$id),ARRAY_A);
   $journal=null;$value=0.0;
   if($action==='pack'){
    Guard::branch($a,$source,Capabilities::TRANSFER_CREATE);BranchDayGuard::assertOpen($a,$source,Db::today());
    if($r['status']!=='draft')throw new DomainException('Only draft transfer can pack.');
    Db::mustUpdate($db,$h,['status'=>'packed','packed_by'=>$a->employeeId],['id'=>$id]);$status='packed';
   }elseif($action==='dispatch'){
    Guard::branch($a,$source,Capabilities::TRANSFER_CREATE);BranchDayGuard::assertOpen($a,$source,Db::today());
    if($r['status']!=='packed')throw new DomainException('Only packed transfer can dispatch.');
    foreach($lines as$l){
     $batch=$l['batch_id']!==null?(int)$l['batch_id']:null;$estimate=StockService::cost($a,$source,(int)$l['product_id'],$batch,null);
     $cost=StockService::move($a,$source,(int)$l['product_id'],$batch,null,'OUT',(float)$l['quantity'],$estimate,'stock_transfer_dispatch',$id);
     Db::mustUpdate($db,Db::table('stock_transfer_lines'),['unit_cost_snapshot'=>$cost],['id'=>(int)$l['id']]);
     $value+=self::lineValue((float)$l['quantity'],$cost);
    }
    $value=round($value,2);
    if($value>0.005){
     $clearing=AccountingService::accountByCode($a,'INTER_BRANCH_CLEARING');$inventory=AccountingService::accountByCode($a,'INVENTORY');
     $journal=AccountingService::post($a,$source,'stock_transfer_dispatch',$id,Db::businessNow(),[
      ['account_id'=>(int)$clearing['id'],'debit'=>$value],['account_id'=>(int)$inventory['id'],'credit'=>$value]
     ],'Stock transfer dispatch #'.$id);
    }
    Db::mustUpdate($db,$h,['status'=>'in_transit','dispatched_by'=>$a->employeeId,'dispatched_at'=>Db::now()],['id'=>$id]);$status='in_transit';
   }elseif($action==='receive'){
    Guard::branch($a,$dest,Capabilities::TRANSFER_RECEIVE);BranchDayGuard::assertOpen($a,$dest,Db::today());
    if($r['status']!=='in_transit')throw new DomainException('Transfer not in transit.');
    $map=[];$expected=[];foreach($lines as$l)$expected[(int)$l['id']]=true;
    foreach((array)($payload['lines']??[]) as$x){$lineId=(int)($x['transfer_line_id']??0);if(!$lineId||!isset($expected[$lineId]))throw new DomainException('Unknown transfer line in receipt.','transfer_receive_unknown_line',422);if(isset($map[$lineId]))throw new DomainException('Duplicate transfer line in receipt.','transfer_receive_duplicate_line',422);$map[$lineId]=$x;}
    if(count($map)!==count($expected))throw new DomainException('Every dispatched transfer line must be received exactly once.','transfer_receive_incomplete',422);
    $diff=false;
    foreach($lines as$l){
     $rawReceived=(float)($map[(int)$l['id']]['received_quantity']??0);if(!is_finite($rawReceived))throw new DomainException('Received quantity must be finite.','transfer_receive_quantity_invalid',422);$actual=round($rawReceived,3);if($actual<0||$actual>(float)$l['quantity']+0.0001)throw new DomainException('Received quantity cannot exceed dispatched quantity.');
     $batch=$l['batch_id']!==null?(int)$l['batch_id']:null;$cost=(float)$l['unit_cost_snapshot'];
     if($actual>0)StockService::move($a,$dest,(int)$l['product_id'],$batch,null,'IN',$actual,$cost,'stock_transfer_receive',$id);
     $updated=$db->update(Db::table('stock_transfer_lines'),['received_quantity'=>$actual],['id'=>(int)$l['id']]);if($updated===false)throw new DomainException('Transfer receipt line update failed.','transfer_receive_store_failed',500);
     $value+=self::lineValue($actual,$cost);if(abs($actual-(float)$l['quantity'])>.0001)$diff=true;
    }
    $value=round($value,2);
    if($value>0.005){
     $inventory=AccountingService::accountByCode($a,'INVENTORY');$clearing=AccountingService::accountByCode($a,'INTER_BRANCH_CLEARING');
     $journal=AccountingService::post($a,$dest,'stock_transfer_receive',$id,Db::businessNow(),[
      ['account_id'=>(int)$inventory['id'],'debit'=>$value],['account_id'=>(int)$clearing['id'],'credit'=>$value]
     ],'Stock transfer receipt #'.$id);
    }
    $status=$diff?'difference_reported':'received';
    $updated=$db->update($h,['status'=>$status,'received_by'=>$a->employeeId,'received_at'=>Db::now()],['id'=>$id]);if($updated===false)throw new DomainException('Transfer receipt update failed.','transfer_receive_store_failed',500);
   }elseif($action==='approve-correction'){
    Guard::branch($a,$source,Capabilities::ADJ_APPROVE);if(!$a->hasBranch($dest))throw new DomainException('Destination branch is outside transfer correction authority.','branch_forbidden',403);BranchDayGuard::assertOpen($a,$source,Db::today());BranchDayGuard::assertOpen($a,$dest,Db::today());
    if($r['status']!=='difference_reported')throw new DomainException('No transfer difference to approve.');
    if((int)$r['created_by']===$a->employeeId)throw new DomainException('Transfer maker cannot approve discrepancy correction.','maker_checker_required',409);
    $note=trim((string)($payload['note']??''));if(strlen($note)<5)throw new DomainException('Transfer discrepancy resolution note is required.','transfer_resolution_note_required',422);
    $variance=0.0;foreach($lines as$l)$variance+=self::shortageValue($l);$variance=round($variance,2);$value=$variance;
    if($variance>0.005){
     $varianceAccount=AccountingService::accountByCode($a,'STOCK_VARIANCE');$clearing=AccountingService::accountByCode($a,'INTER_BRANCH_CLEARING');
     $journal=AccountingService::post($a,$source,'stock_transfer_variance',$id,Db::businessNow(),[
      ['account_id'=>(int)$varianceAccount['id'],'debit'=>$variance],['account_id'=>(int)$clearing['id'],'credit'=>$variance]
     ],'Transfer shortage #'.$id.': '.$note);
    }
    $status='received';Db::mustUpdate($db,$h,['status'=>$status,'notes'=>trim((string)$r['notes']).' | Discrepancy resolution: '.$note],['id'=>$id]);
    Audit::add($a,'stock_transfer.approve-correction','stock_transfer',$id,['branch_id'=>$source,'variance_amount'=>$variance,'journal_entry_id'=>$journal,'note'=>$note]);
    return['id'=>$id,'status'=>$status,'variance_amount'=>$variance,'journal_entry_id'=>$journal];
   }elseif($action==='cancel'){
    $reason=trim((string)($payload['reason']??''));if(strlen($reason)<5)throw new DomainException('Transfer cancellation reason is required.','transfer_cancel_reason_required',422);
    if(in_array($r['status'],['draft','packed'],true)){
     Guard::branch($a,$source,Capabilities::TRANSFER_CREATE);BranchDayGuard::assertOpen($a,$source,Db::today());$status='cancelled';
     Db::mustUpdate($db,$h,['status'=>$status,'cancelled_by'=>$a->employeeId,'cancelled_at'=>Db::now(),'cancel_reason'=>$reason],['id'=>$id]);
    }elseif($r['status']==='in_transit'){
     Guard::branch($a,$source,Capabilities::TRANSFER_CANCEL);BranchDayGuard::assertOpen($a,$source,Db::today());
     if((int)$r['created_by']===$a->employeeId)throw new DomainException('In-transit cancellation requires maker-checker.','maker_checker_required',409);
     foreach($lines as$l){$cost=(float)$l['unit_cost_snapshot'];StockService::move($a,$source,(int)$l['product_id'],$l['batch_id']!==null?(int)$l['batch_id']:null,null,'IN',(float)$l['quantity'],$cost,'stock_transfer_cancel',$id);$value+=self::lineValue((float)$l['quantity'],$cost);}
     $value=round($value,2);
     if($value>0.005){
      $inventory=AccountingService::accountByCode($a,'INVENTORY');$clearing=AccountingService::accountByCode($a,'INTER_BRANCH_CLEARING');
      $journal=AccountingService::post($a,$source,'stock_transfer_cancel',$id,Db::businessNow(),[
       ['account_id'=>(int)$inventory['id'],'debit'=>$value],['account_id'=>(int)$clearing['id'],'credit'=>$value]
      ],'Stock transfer cancellation #'.$id);
     }
     $status='cancelled';Db::mustUpdate($db,$h,['status'=>$status,'cancelled_by'=>$a->employeeId,'cancelled_at'=>Db::now(),'cancel_reason'=>$reason],['id'=>$id]);
    }else throw new DomainException('Only Draft, Packed or In-Transit transfer can be cancelled. Received transfers require controlled reversal/correction.','transfer_cancel_not_allowed',409);
    Audit::add($a,'stock_transfer.cancel','stock_transfer',$id,['branch_id'=>$source,'reason'=>$reason,'previous_status'=>$r['status'],'journal_entry_id'=>$journal,'value'=>$value]);
    return['id'=>$id,'status'=>$status,'journal_entry_id'=>$journal,'value'=>$value];
   }else throw new DomainException('Unsupported transfer action.');
   Audit::add($a,'stock_transfer.'.$action,'stock_transfer',$id,['branch_id'=>$source,'journal_entry_id'=>$journal,'value'=>$value]);
   return['id'=>$id,'status'=>$status,'journal_entry_id'=>$journal,'value'=>$value];
  });
 }

 public static function transferAccountingRepairPreview(Actor $a):array{
  Guard::cap($a,Capabilities::ACCESS_MANAGE);Guard::cap($a,Capabilities::ACCOUNT_MANAGE);
  $db=Db::wpdb();$rows=(array)$db->get_results($db->prepare("SELECT * FROM ".Db::table('stock_transfers')." WHERE company_id=%d ORDER BY id",$a->companyId),ARRAY_A);
  $out=[];$repairable=0;$blocked=0;
  foreach($rows as$r){$state=self::accountingRepairState($a,$r);if(!$state['needs_repair']&&!$state['blockers'])continue;if($state['blockers'])$blocked++;else$repairable++;$out[]=$state;}
  return['repairable'=>$repairable,'blocked'=>$blocked,'transfers'=>$out];
 }

 public static function repairTransferAccounting(Actor $a,string $confirmation):array{
  Guard::cap($a,Capabilities::ACCESS_MANAGE);Guard::cap($a,Capabilities::ACCOUNT_MANAGE);
  if(trim($confirmation)!=='REPAIR TRANSFER ACCOUNTING')throw new DomainException('Exact repair confirmation is required.','repair_confirmation_required',422);
  AccountingService::accountByCode($a,'INTER_BRANCH_CLEARING');AccountingService::accountByCode($a,'INVENTORY');
  $preview=self::transferAccountingRepairPreview($a);if((int)$preview['blocked']>0)throw new DomainException('Blocked legacy transfer accounting rows require manual review before repair.','transfer_accounting_repair_blocked',409);
  $repaired=[];
  foreach((array)$preview['transfers'] as$state){
   if(empty($state['needs_repair']))continue;$id=(int)$state['id'];
   $repaired[]=Transaction::run(function()use($a,$id){
    $db=Db::wpdb();$r=$db->get_row($db->prepare("SELECT * FROM ".Db::table('stock_transfers')." WHERE id=%d AND company_id=%d FOR UPDATE",$id,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Transfer not found during repair.','transfer_not_found',404);
    $state=self::accountingRepairState($a,$r);if($state['blockers'])throw new DomainException('Transfer accounting repair became blocked.','transfer_accounting_repair_blocked',409);
    $created=[];$clearing=AccountingService::accountByCode($a,'INTER_BRANCH_CLEARING');$inventory=AccountingService::accountByCode($a,'INVENTORY');
    if($state['dispatch_needed']&&$state['dispatch_value']>0.005){$created['dispatch']=AccountingService::post($a,(int)$r['source_branch_id'],'stock_transfer_dispatch',$id,self::businessTime($r['dispatched_at']??$r['created_at']),[['account_id'=>(int)$clearing['id'],'debit'=>$state['dispatch_value']],['account_id'=>(int)$inventory['id'],'credit'=>$state['dispatch_value']]],'Historical stock transfer dispatch repair #'.$id);}
    if($state['receive_needed']&&$state['receive_value']>0.005){$created['receive']=AccountingService::post($a,(int)$r['destination_branch_id'],'stock_transfer_receive',$id,self::businessTime($r['received_at']??$r['dispatched_at']??$r['created_at']),[['account_id'=>(int)$inventory['id'],'debit'=>$state['receive_value']],['account_id'=>(int)$clearing['id'],'credit'=>$state['receive_value']]],'Historical stock transfer receipt repair #'.$id);}
    if($state['cancel_needed']&&$state['dispatch_value']>0.005){$created['cancel']=AccountingService::post($a,(int)$r['source_branch_id'],'stock_transfer_cancel',$id,self::businessTime($r['cancelled_at']??$r['dispatched_at']??$r['created_at']),[['account_id'=>(int)$inventory['id'],'debit'=>$state['dispatch_value']],['account_id'=>(int)$clearing['id'],'credit'=>$state['dispatch_value']]],'Historical stock transfer cancellation repair #'.$id);}
    Audit::add($a,'stock_transfer.accounting_repair','stock_transfer',$id,['branch_id'=>(int)$r['source_branch_id'],'created_journals'=>$created,'dispatch_value'=>$state['dispatch_value'],'receive_value'=>$state['receive_value']]);
    return['id'=>$id,'created_journals'=>$created];
   });
  }
  return['repaired_count'=>count($repaired),'repaired'=>$repaired,'preview_after'=>self::transferAccountingRepairPreview($a)];
 }

 private static function accountingRepairState(Actor $a,array $r):array{
  $db=Db::wpdb();$id=(int)$r['id'];$lines=(array)$db->get_results($db->prepare("SELECT * FROM ".Db::table('stock_transfer_lines')." WHERE transfer_id=%d ORDER BY id",$id),ARRAY_A);
  $dispatchValue=0.0;$receiveValue=0.0;foreach($lines as$l){$dispatchValue+=self::lineValue((float)$l['quantity'],(float)$l['unit_cost_snapshot']);$receiveValue+=self::lineValue((float)$l['received_quantity'],(float)$l['unit_cost_snapshot']);}$dispatchValue=round($dispatchValue,2);$receiveValue=round($receiveValue,2);
  $ledger=Db::table('stock_ledger');$journal=Db::table('journal_entries');
  $hasDispatchLedger=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$ledger} WHERE company_id=%d AND source_type='stock_transfer_dispatch' AND source_id=%d",$a->companyId,$id))>0;
  $hasReceiveLedger=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$ledger} WHERE company_id=%d AND source_type='stock_transfer_receive' AND source_id=%d",$a->companyId,$id))>0;
  $hasCancelLedger=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$ledger} WHERE company_id=%d AND source_type='stock_transfer_cancel' AND source_id=%d",$a->companyId,$id))>0;
  $journalId=function(string $type)use($db,$journal,$a,$id):int{return(int)$db->get_var($db->prepare("SELECT id FROM {$journal} WHERE company_id=%d AND source_type=%s AND source_id=%d AND status='posted' ORDER BY id DESC LIMIT 1",$a->companyId,$type,$id));};
  $dispatchJournal=$journalId('stock_transfer_dispatch');$receiveJournal=$journalId('stock_transfer_receive');$cancelJournal=$journalId('stock_transfer_cancel');$varianceJournal=$journalId('stock_transfer_variance');
  $blockers=[];if($varianceJournal&&(!$dispatchJournal||($hasReceiveLedger&&!$receiveJournal)))$blockers[]='legacy_variance_requires_manual_review';
  if($hasReceiveLedger&&!$hasDispatchLedger)$blockers[]='receive_without_dispatch_ledger';if($hasCancelLedger&&!$hasDispatchLedger)$blockers[]='cancel_without_dispatch_ledger';
  $dispatchNeeded=$hasDispatchLedger&&!$dispatchJournal;$receiveNeeded=$hasReceiveLedger&&!$receiveJournal;$cancelNeeded=$hasCancelLedger&&!$cancelJournal;
  return['id'=>$id,'status'=>(string)$r['status'],'source_branch_id'=>(int)$r['source_branch_id'],'destination_branch_id'=>(int)$r['destination_branch_id'],'dispatch_value'=>$dispatchValue,'receive_value'=>$receiveValue,'dispatch_needed'=>$dispatchNeeded,'receive_needed'=>$receiveNeeded,'cancel_needed'=>$cancelNeeded,'needs_repair'=>$dispatchNeeded||$receiveNeeded||$cancelNeeded,'blockers'=>$blockers,'existing_journals'=>['dispatch'=>$dispatchJournal?:null,'receive'=>$receiveJournal?:null,'cancel'=>$cancelJournal?:null,'variance'=>$varianceJournal?:null]];
 }

 private static function lineValue(float $quantity,float $unitCost):float{return round(max(0,$quantity)*max(0,$unitCost),2);}
 private static function shortageValue(array $line):float{return max(0,round(self::lineValue((float)$line['quantity'],(float)$line['unit_cost_snapshot'])-self::lineValue((float)$line['received_quantity'],(float)$line['unit_cost_snapshot']),2));}
 private static function businessTime(?string $utc):string{$utc=trim((string)$utc);if($utc==='')return Db::businessNow();if(function_exists('get_date_from_gmt')){$local=get_date_from_gmt($utc,'Y-m-d H:i:s');if(is_string($local)&&$local!=='')return$local;}return$utc;}
 public static function adjustment(Actor $a,int $branch,string $reason,array $lines):array{Guard::branch($a,$branch,Capabilities::ADJ_CREATE);BranchDayGuard::assertOpen($a,$branch,Db::today());if(strlen(trim($reason))<5||!$lines)throw new DomainException('Reason and lines required.');return Transaction::run(function()use($a,$branch,$reason,$lines){$db=Db::wpdb();$seen=[];Db::mustInsert($db,Db::table('stock_adjustments'),['company_id'=>$a->companyId,'branch_id'=>$branch,'status'=>'pending','reason'=>trim($reason),'created_by'=>$a->employeeId,'created_at'=>Db::now()]);if(!$db->insert_id)throw new DomainException('Stock adjustment could not be created.','adjustment_create_failed',500);$id=(int)$db->insert_id;foreach($lines as$x){$pid=(int)($x['product_id']??0);$batch=isset($x['batch_id'])?(int)$x['batch_id']:null;$key=$pid.'|'.($batch?:0);$rawDelta=(float)($x['quantity_delta']??0);if(!is_finite($rawDelta))throw new DomainException('Stock adjustment quantity must be finite.','adjustment_quantity_invalid',422);$delta=round($rawDelta,3);if($pid<1||isset($seen[$key]))throw new DomainException('Invalid or duplicate adjustment product/batch line.','duplicate_adjustment_line',422);if(abs($delta)<.0001)throw new DomainException('Adjustment delta cannot be zero.');$seen[$key]=1;$product=StockService::product($a,$pid);StockService::validateBatch($a,$product,$batch,$delta<0);$currentCost=StockService::cost($a,$branch,$pid,$batch,null);if($delta>0){$provided=array_key_exists('unit_cost',$x)?(float)$x['unit_cost']:null;if($provided!==null&&!is_finite($provided))throw new DomainException('Stock adjustment cost must be finite.','adjustment_cost_invalid',422);if($provided!==null&&$provided>0){$cost=$provided;}elseif($currentCost>0){$cost=$currentCost;}else{$commercial=StockService::commercial($a,$pid);$cost=max(0,(float)($commercial['purchase_cost']??0));}if($cost<=0)throw new DomainException('Positive stock adjustment requires a unit cost or active purchase cost.','adjustment_unit_cost_required',422);}else{$cost=$currentCost;}Db::mustInsert($db,Db::table('stock_adjustment_lines'),['adjustment_id'=>$id,'product_id'=>$pid,'batch_id'=>$batch,'quantity_delta'=>$delta,'unit_cost_snapshot'=>round($cost,4)]);if(!$db->insert_id)throw new DomainException('Stock adjustment line could not be created.','adjustment_line_failed',500);}Audit::add($a,'stock_adjustment.create','stock_adjustment',$id,['branch_id'=>$branch,'reason'=>trim($reason)]);return['id'=>$id,'status'=>'pending'];});}
 public static function decideAdjustment(Actor $a,int $id,bool $approve):array{return Transaction::run(function()use($a,$id,$approve){$db=Db::wpdb();$h=Db::table('stock_adjustments');$r=$db->get_row($db->prepare("SELECT * FROM {$h} WHERE id=%d AND company_id=%d FOR UPDATE",$id,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Adjustment not found.','adjustment_not_found',404);Guard::branch($a,(int)$r['branch_id'],Capabilities::ADJ_APPROVE);BranchDayGuard::assertOpen($a,(int)$r['branch_id'],Db::today());if($r['status']!=='pending')throw new DomainException('Adjustment not pending.');if((int)$r['created_by']===$a->employeeId)throw new DomainException('Maker cannot approve own adjustment.','maker_checker_required',409);$status=$approve?'approved':'rejected';$journal=null;if($approve){$lines=(array)$db->get_results($db->prepare("SELECT * FROM ".Db::table('stock_adjustment_lines')." WHERE adjustment_id=%d ORDER BY id",$id),ARRAY_A);$gain=0.0;$loss=0.0;foreach($lines as$l){$b=$l['batch_id']!==null?(int)$l['batch_id']:null;$d=(float)$l['quantity_delta'];$estimate=$d<0?StockService::cost($a,(int)$r['branch_id'],(int)$l['product_id'],$b,null):(float)$l['unit_cost_snapshot'];$cost=StockService::move($a,(int)$r['branch_id'],(int)$l['product_id'],$b,null,$d>0?'IN':'OUT',abs($d),$estimate,'stock_adjustment',$id);Db::mustUpdate($db,Db::table('stock_adjustment_lines'),['unit_cost_snapshot'=>round($cost,4)],['id'=>(int)$l['id']]);$value=round(abs($d)*$cost,2);if($d>0)$gain+=$value;else$loss+=$value;}$gain=round($gain,2);$loss=round($loss,2);if($gain>0.005||$loss>0.005){$inv=AccountingService::accountByCode($a,'INVENTORY');$var=AccountingService::accountByCode($a,'STOCK_VARIANCE');$jl=[];if($gain>0.005){$jl[]=['account_id'=>(int)$inv['id'],'debit'=>$gain];$jl[]=['account_id'=>(int)$var['id'],'credit'=>$gain];}if($loss>0.005){$jl[]=['account_id'=>(int)$var['id'],'debit'=>$loss];$jl[]=['account_id'=>(int)$inv['id'],'credit'=>$loss];}$journal=AccountingService::post($a,(int)$r['branch_id'],'stock_adjustment',$id,Db::businessNow(),$jl,'Stock adjustment #'.$id.' '.$r['reason']);}}Db::mustUpdate($db,$h,['status'=>$status,'decided_by'=>$a->employeeId,'decided_at'=>Db::now(),'journal_entry_id'=>$journal],['id'=>$id]);Audit::add($a,'stock_adjustment.'.($approve?'approve':'reject'),'stock_adjustment',$id,['branch_id'=>(int)$r['branch_id'],'journal_entry_id'=>$journal]);return['id'=>$id,'status'=>$status,'journal_entry_id'=>$journal];});}
 public static function quarantine(Actor $a,int $branch):array{Guard::branch($a,$branch,Capabilities::INVENTORY_VIEW);$db=Db::wpdb();return(array)$db->get_results($db->prepare("SELECT q.*,p.name product_name,b.batch_no FROM ".Db::table('stock_quarantine')." q JOIN ".Db::table('products')." p ON p.id=q.product_id LEFT JOIN ".Db::table('batches')." b ON b.id=q.batch_id WHERE q.company_id=%d AND q.branch_id=%d AND q.status='open' ORDER BY q.id DESC",$a->companyId,$branch),ARRAY_A);}
 public static function quarantineHold(Actor $a,int $branch,int $product,?int $batch,float $quantity,string $reason):array{Guard::branch($a,$branch,Capabilities::ADJ_CREATE);BranchDayGuard::assertOpen($a,$branch,Db::today());if(!is_finite($quantity))throw new DomainException('Quarantine quantity must be finite.','quarantine_fields_invalid',422);$quantity=round($quantity,3);$reason=trim($reason);if($product<1||$quantity<=0||strlen($reason)<5||strlen($reason)>255)throw new DomainException('Valid stock item, quantity and reason are required.','quarantine_fields_invalid',422);return Transaction::run(function()use($a,$branch,$product,$batch,$quantity,$reason){$p=StockService::product($a,$product);StockService::validateBatch($a,$p,$batch,true,true);$cost=StockService::cost($a,$branch,$product,$batch,null);$db=Db::wpdb();$t=Db::table('stock_quarantine');Db::mustInsert($db,$t,['company_id'=>$a->companyId,'branch_id'=>$branch,'product_id'=>$product,'batch_id'=>$batch,'quantity'=>$quantity,'unit_cost_snapshot'=>round($cost,4),'reason'=>$reason,'status'=>'open','created_by'=>$a->employeeId,'created_at'=>Db::now()]);$id=(int)$db->insert_id;if($id<1)throw new DomainException('Unable to create quarantine hold.','quarantine_create_failed',500);$cost=StockService::move($a,$branch,$product,$batch,null,'OUT',$quantity,$cost,'stock_quarantine_hold',$id);Db::mustUpdate($db,$t,['unit_cost_snapshot'=>round($cost,4)],['id'=>$id]);Audit::add($a,'stock_quarantine.hold','stock_quarantine',$id,['branch_id'=>$branch,'quantity'=>$quantity,'unit_cost'=>$cost,'reason'=>$reason]);return['id'=>$id,'status'=>'open','quantity'=>$quantity,'unit_cost_snapshot'=>round($cost,4)];});}
 public static function resolveQuarantine(Actor $a,int $id,string $action,string $reason):array{Guard::cap($a,Capabilities::ADJ_APPROVE);$reason=trim($reason);if(!in_array($action,['release','write_off'],true)||strlen($reason)<5)throw new DomainException('Valid action and reason required.');return Transaction::run(function()use($a,$id,$action,$reason){$db=Db::wpdb();$t=Db::table('stock_quarantine');$r=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d FOR UPDATE",$id,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Quarantine item not found.','quarantine_not_found',404);Guard::branch($a,(int)$r['branch_id'],Capabilities::ADJ_APPROVE);BranchDayGuard::assertOpen($a,(int)$r['branch_id'],Db::today());if($r['status']!=='open')throw new DomainException('Quarantine already resolved.','quarantine_state_invalid',409);if((int)$r['created_by']===$a->employeeId)throw new DomainException('Quarantine maker cannot resolve own hold.','maker_checker_required',409);$batch=$r['batch_id']!==null?(int)$r['batch_id']:null;$quantity=(float)$r['quantity'];$cost=(float)$r['unit_cost_snapshot'];$value=round($quantity*$cost,2);$journal=null;if($action==='release')StockService::move($a,(int)$r['branch_id'],(int)$r['product_id'],$batch,null,'IN',$quantity,$cost,'stock_quarantine_release',$id);elseif($value>0.005){$variance=AccountingService::accountByCode($a,'STOCK_VARIANCE');$inventory=AccountingService::accountByCode($a,'INVENTORY');$journal=AccountingService::post($a,(int)$r['branch_id'],'stock_quarantine_writeoff',$id,Db::businessNow(),[['account_id'=>(int)$variance['id'],'debit'=>$value],['account_id'=>(int)$inventory['id'],'credit'=>$value]],'Quarantine write-off #'.$id.': '.$reason);}$status=$action==='release'?'released':'written_off';Db::mustUpdate($db,$t,['status'=>$status,'resolved_by'=>$a->employeeId,'resolved_at'=>Db::now(),'journal_entry_id'=>$journal,'reason'=>$r['reason'].' | '.$reason],['id'=>$id]);Audit::add($a,'stock_quarantine.'.$action,'stock_quarantine',$id,['branch_id'=>(int)$r['branch_id'],'quantity'=>$quantity,'unit_cost'=>$cost,'value'=>$value,'journal_entry_id'=>$journal,'reason'=>$reason]);return['id'=>$id,'status'=>$status,'value'=>$value,'journal_entry_id'=>$journal];});}
}
