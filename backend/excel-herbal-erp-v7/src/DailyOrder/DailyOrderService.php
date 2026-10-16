<?php
namespace ExcelHerbal\ERP7\DailyOrder;
use ExcelHerbal\ERP7\Core\Input;use ExcelHerbal\ERP7\Database\Db;use ExcelHerbal\ERP7\Database\Transaction;use ExcelHerbal\ERP7\Domain\DomainException;use ExcelHerbal\ERP7\Finance\AccountingService;use ExcelHerbal\ERP7\Finance\BranchDayGuard;use ExcelHerbal\ERP7\Inventory\StockService;use ExcelHerbal\ERP7\Security\Actor;use ExcelHerbal\ERP7\Security\Audit;use ExcelHerbal\ERP7\Security\Capabilities;use ExcelHerbal\ERP7\Security\Guard;use ExcelHerbal\ERP7\Security\HierarchyScope;use ExcelHerbal\ERP7\Administration\ActingDutyService;use ExcelHerbal\ERP7\Recovery\WholePcsGuard;
final class DailyOrderService{
 public static function targetEmployees(Actor $a,int $branch):array{Guard::branch($a,$branch,Capabilities::DAILY_OTHERS);$ids=HierarchyScope::visibleEmployeeIds($a,$branch);if(!$ids)return[];$db=Db::wpdb();$sql="SELECT id,employee_code,full_name,designation_code FROM ".Db::table('employees')." WHERE company_id=%d AND assigned_branch_id=%d AND status='active' AND id IN (".implode(',',array_map('intval',$ids)).") ORDER BY full_name,id";return(array)$db->get_results($db->prepare($sql,$a->companyId,$branch),ARRAY_A);}
 public static function list(Actor $a,?int $branch=null):array{Guard::any($a,[Capabilities::DAILY_SELF,Capabilities::DAILY_OTHERS]);$db=Db::wpdb();$where='c.company_id=%d';$args=[$a->companyId];if($branch){Guard::branch($a,$branch,$a->can(Capabilities::DAILY_OTHERS)?Capabilities::DAILY_OTHERS:Capabilities::DAILY_SELF);$where.=' AND c.branch_id=%d';$args[]=$branch;}if($a->can(Capabilities::DAILY_OTHERS)){$ids=HierarchyScope::visibleEmployeeIds($a,$branch);if(!$ids)return[];$where.=' AND c.employee_id IN ('.implode(',',array_fill(0,count($ids),'%d')).')';$args=array_merge($args,$ids);}else{$where.=' AND c.employee_id=%d';$args[]=$a->employeeId;}return(array)$db->get_results($db->prepare("SELECT c.*,e.employee_code,e.full_name employee_name,e.designation_code,e.reporting_designation_code,r.id initial_request_id,r.status initial_request_status,r.requested_by initial_requested_by,r.approved_by initial_approved_by,r.issued_by initial_issued_by,ar.id additional_request_id,ar.status additional_request_status,ar.requested_by additional_requested_by,ar.approved_by additional_approved_by FROM ".Db::table('daily_cycles')." c JOIN ".Db::table('employees')." e ON e.id=c.employee_id AND e.company_id=c.company_id LEFT JOIN ".Db::table('daily_requests')." r ON r.daily_cycle_id=c.id AND r.type='initial' LEFT JOIN ".Db::table('daily_requests')." ar ON ar.id=(SELECT MAX(ar2.id) FROM ".Db::table('daily_requests')." ar2 WHERE ar2.daily_cycle_id=c.id AND ar2.type='additional' AND ar2.status IN ('submitted','approved')) WHERE {$where} ORDER BY c.business_date DESC,c.id DESC LIMIT 100",...$args),ARRAY_A);}

 /** Paginated historical discovery. Legacy list() remains unchanged for existing callers. */
 public static function search(Actor $a,?int $branch,int $page=1,int $pageSize=25,string $query='',string $status='',string $from='',string $to='',?int $employee=null):array{
  Guard::any($a,[Capabilities::DAILY_SELF,Capabilities::DAILY_OTHERS]);
  $page=max(1,min(100000,$page));$pageSize=max(1,min(100,$pageSize));$query=trim($query);$status=trim($status);
  if(strlen($query)>120)throw new DomainException('Search term too long.','daily_search_invalid',422);
  if($status!==''&&!in_array($status,['morning_draft','stock_requested','approved','issued','evening_draft','evening_submitted','completed','cancelled','rejected'],true))throw new DomainException('Invalid Daily Order status.','daily_search_invalid',422);
  $from=trim($from);$to=trim($to);
  if($from!=='')$from=Input::date($from,'From date');
  if($to!=='')$to=Input::date($to,'To date');
  if($from!==''&&$to!==''&&$from>$to)throw new DomainException('From date cannot exceed To date.','daily_search_invalid',422);
  $db=Db::wpdb();$where='c.company_id=%d';$args=[$a->companyId];
  if($branch!==null&&$branch>0){Guard::branch($a,$branch,$a->can(Capabilities::DAILY_OTHERS)?Capabilities::DAILY_OTHERS:Capabilities::DAILY_SELF);$where.=' AND c.branch_id=%d';$args[]=$branch;}
  if($a->can(Capabilities::DAILY_OTHERS)){
   $ids=HierarchyScope::visibleEmployeeIds($a,$branch);
   if(!$ids)return['items'=>[],'page'=>$page,'page_size'=>$pageSize,'total'=>0,'has_more'=>false];
   $where.=' AND c.employee_id IN ('.implode(',',array_fill(0,count($ids),'%d')).')';$args=array_merge($args,$ids);
  }else{$where.=' AND c.employee_id=%d';$args[]=$a->employeeId;}
  if($employee!==null&&$employee>0){$where.=' AND c.employee_id=%d';$args[]=$employee;}
  if($status!==''){$where.=' AND c.status=%s';$args[]=$status;}
  if($from!==''){$where.=' AND c.business_date>=%s';$args[]=$from;}
  if($to!==''){$where.=' AND c.business_date<=%s';$args[]=$to;}
  if($query!==''){
   $like='%'.addcslashes($query,'\\%_').'%';
   $where.=' AND (e.full_name LIKE %s OR e.employee_code LIKE %s OR CAST(c.id AS CHAR) LIKE %s)';
   $args[]=$like;$args[]=$like;$args[]=$like;
  }
  $cycles=Db::table('daily_cycles');$employees=Db::table('employees');$requests=Db::table('daily_requests');
  $join=" FROM {$cycles} c JOIN {$employees} e ON e.id=c.employee_id AND e.company_id=c.company_id";
  $total=(int)$db->get_var($db->prepare("SELECT COUNT(*) {$join} WHERE {$where}",...$args));
  $offset=($page-1)*$pageSize;
  $sql="SELECT c.*,e.employee_code,e.full_name employee_name,e.designation_code,e.reporting_designation_code,r.id initial_request_id,r.status initial_request_status,r.requested_by initial_requested_by,r.approved_by initial_approved_by,r.issued_by initial_issued_by,ar.id additional_request_id,ar.status additional_request_status,ar.requested_by additional_requested_by,ar.approved_by additional_approved_by {$join} LEFT JOIN {$requests} r ON r.daily_cycle_id=c.id AND r.type='initial' LEFT JOIN {$requests} ar ON ar.id=(SELECT MAX(ar2.id) FROM {$requests} ar2 WHERE ar2.daily_cycle_id=c.id AND ar2.type='additional' AND ar2.status IN ('submitted','approved')) WHERE {$where} ORDER BY c.business_date DESC,c.id DESC LIMIT %d OFFSET %d";
  $items=(array)$db->get_results($db->prepare($sql,...array_merge($args,[$pageSize,$offset])),ARRAY_A);
  return['items'=>$items,'page'=>$page,'page_size'=>$pageSize,'total'=>$total,'has_more'=>$offset+count($items)<$total];
 }
 public static function detail(Actor $a,int $id):array{$c=self::cycle($a,$id);$cap=(int)$c['employee_id']===$a->employeeId?Capabilities::DAILY_SELF:Capabilities::DAILY_OTHERS;if((int)$c['employee_id']!==$a->employeeId)HierarchyScope::assertCanViewEmployee($a,(int)$c['employee_id']);Guard::branch($a,(int)$c['branch_id'],$cap);$db=Db::wpdb();$requests=(array)$db->get_results($db->prepare("SELECT * FROM ".Db::table('daily_requests')." WHERE daily_cycle_id=%d ORDER BY id",$id),ARRAY_A);foreach($requests as&$r){$r['lines']=(array)$db->get_results($db->prepare("SELECT l.id,l.product_id,p.name product_name,p.batch_tracking,l.quantity FROM ".Db::table('daily_request_lines')." l JOIN ".Db::table('products')." p ON p.id=l.product_id WHERE l.daily_request_id=%d ORDER BY l.id",(int)$r['id']),ARRAY_A);$r['issued_lines']=(array)$db->get_results($db->prepare("SELECT il.*,p.name product_name,b.batch_no,b.expires_on FROM ".Db::table('daily_issue_lines')." il JOIN ".Db::table('products')." p ON p.id=il.product_id LEFT JOIN ".Db::table('batches')." b ON b.id=il.batch_id WHERE il.daily_request_id=%d ORDER BY il.id",(int)$r['id']),ARRAY_A);}unset($r);$evening=$db->get_row($db->prepare("SELECT * FROM ".Db::table('evening_settlements')." WHERE daily_cycle_id=%d",$id),ARRAY_A);if($evening)$evening['lines']=(array)$db->get_results($db->prepare("SELECT el.*,p.name product_name,b.batch_no FROM ".Db::table('evening_lines')." el JOIN ".Db::table('products')." p ON p.id=el.product_id LEFT JOIN ".Db::table('batches')." b ON b.id=el.batch_id WHERE el.evening_settlement_id=%d ORDER BY el.id",(int)$evening['id']),ARRAY_A);return['cycle'=>$c,'requests'=>$requests,'evening'=>$evening?:null];}
 public static function create(Actor $a,int $branch,int $employee,string $date,array $lines):array{$date=Input::date($date,'Daily Order business date');$cap=$employee===$a->employeeId?Capabilities::DAILY_SELF:Capabilities::DAILY_OTHERS;if($employee!==$a->employeeId)HierarchyScope::assertCanViewEmployee($a,$employee);Guard::branch($a,$branch,$cap);BranchDayGuard::assertOpen($a,$branch,$date);if(!$lines)throw new DomainException('Daily Order needs product lines.');$db=Db::wpdb();$emp=$db->get_row($db->prepare("SELECT id FROM ".Db::table('employees')." WHERE id=%d AND company_id=%d AND assigned_branch_id=%d AND status='active'",$employee,$a->companyId,$branch),ARRAY_A);if(!$emp)throw new DomainException('Target employee not active in branch.');return Transaction::run(function()use($a,$branch,$employee,$date,$lines,$db){$c=Db::table('daily_cycles');if((int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$c} WHERE company_id=%d AND employee_id=%d AND business_date=%s",$a->companyId,$employee,$date)))throw new DomainException('Daily Order already exists.','daily_duplicate',409);Db::mustInsert($db,$c,['company_id'=>$a->companyId,'branch_id'=>$branch,'employee_id'=>$employee,'business_date'=>$date,'status'=>'morning_draft','created_by'=>$a->employeeId,'created_at'=>Db::now()],'Daily Order already exists.','daily_duplicate');$cid=(int)$db->insert_id;Db::mustInsert($db,Db::table('daily_requests'),['daily_cycle_id'=>$cid,'type'=>'initial','status'=>'draft','requested_by'=>$a->employeeId,'created_at'=>Db::now()]);$rid=(int)$db->insert_id;$seen=[];foreach($lines as$x){$pid=(int)($x['product_id']??0);$qty=(float)($x['quantity']??0);if(!$pid||$qty<=0)throw new DomainException('Invalid Daily Order line.');if(isset($seen[$pid]))throw new DomainException('Duplicate product in Daily Order request.','duplicate_daily_line',422);$seen[$pid]=1;StockService::product($a,$pid);Db::mustInsert($db,Db::table('daily_request_lines'),['daily_request_id'=>$rid,'product_id'=>$pid,'batch_id'=>null,'quantity'=>$qty]);}Audit::add($a,'daily_order.create','daily_cycle',$cid,['branch_id'=>$branch,'employee_id'=>$employee]);return['id'=>$cid,'request_id'=>$rid,'status'=>'morning_draft'];});}

 /** Edit the existing initial request only before stock approval/issue. */
 public static function editDraft(Actor $a,int $id,array $lines):array{
  if(!$lines)throw new DomainException('Draft needs at least one product.','daily_line_invalid',422);
  return Transaction::run(function()use($a,$id,$lines){
   $c=self::cycle($a,$id,true);
   $cap=(int)$c['employee_id']===$a->employeeId?Capabilities::DAILY_SELF:Capabilities::DAILY_OTHERS;
   Guard::branch($a,(int)$c['branch_id'],$cap);
   if((int)$c['employee_id']!==$a->employeeId)HierarchyScope::assertCanViewEmployee($a,(int)$c['employee_id']);
   BranchDayGuard::assertOpen($a,(int)$c['branch_id'],(string)$c['business_date']);
   if($c['status']!=='morning_draft')throw new DomainException('Only a morning draft can be edited.','daily_state_invalid',409);
   $db=Db::wpdb();$requests=Db::table('daily_requests');$details=Db::table('daily_request_lines');
   $r=$db->get_row($db->prepare("SELECT * FROM {$requests} WHERE daily_cycle_id=%d AND type='initial' FOR UPDATE",$id),ARRAY_A);
   if(!$r||$r['status']!=='draft')throw new DomainException('Initial draft request not found.','daily_request_state_invalid',409);
   $prepared=[];$seen=[];
   foreach($lines as$x){
    $product=(int)($x['product_id']??0);$qty=(float)($x['quantity']??0);
    if($product<1||!is_finite($qty)||$qty<=0||isset($seen[$product]))throw new DomainException('Invalid or repeated draft product.','daily_line_invalid',422);
    StockService::product($a,$product);$seen[$product]=true;$prepared[]=['daily_request_id'=>(int)$r['id'],'product_id'=>$product,'batch_id'=>null,'quantity'=>round($qty,3)];
   }
   $removed=$db->query($db->prepare("DELETE FROM {$details} WHERE daily_request_id=%d",(int)$r['id']));
   if($removed===false)throw new DomainException('Draft lines could not be updated.','daily_draft_store_failed',500);
   foreach($prepared as$x)Db::mustInsert($db,$details,$x);
   Audit::add($a,'daily_order.edit_draft','daily_cycle',$id,['branch_id'=>(int)$c['branch_id'],'lines'=>count($prepared)]);
   return['id'=>$id,'request_id'=>(int)$r['id'],'status'=>'morning_draft','lines'=>count($prepared)];
  });
 }

 /** Controlled reviewer rejection: initial request returns to editable draft; additional request stops blocking closing. */
 public static function rejectRequest(Actor $a,int $request,string $reason):array{
  $reason=trim($reason);if(strlen($reason)<5||strlen($reason)>255)throw new DomainException('Rejection reason (5–255 chars) is required.','daily_reason_invalid',422);
  return Transaction::run(function()use($a,$request,$reason){
   $db=Db::wpdb();$rt=Db::table('daily_requests');$ct=Db::table('daily_cycles');
   $r=$db->get_row($db->prepare("SELECT r.*,c.branch_id,c.employee_id,c.company_id,c.business_date,c.status cycle_status FROM {$rt} r JOIN {$ct} c ON c.id=r.daily_cycle_id WHERE r.id=%d AND c.company_id=%d FOR UPDATE",$request,$a->companyId),ARRAY_A);
   if(!$r)throw new DomainException('Daily request not found.','daily_request_not_found',404);
   $authority=ActingDutyService::assertAction($a,(int)$r['branch_id'],'daily.approve',(int)$r['requested_by']);
   if($authority['mode']==='permanent')HierarchyScope::assertCanViewEmployee($a,(int)$r['employee_id']);
   BranchDayGuard::assertOpen($a,(int)$r['branch_id'],(string)$r['business_date']);
   if((int)$r['requested_by']===$a->employeeId)throw new DomainException('Requester cannot reject own request.','maker_checker_required',409);
   if($r['status']!=='submitted')throw new DomainException('Only submitted requests can be rejected.','daily_request_state_invalid',409);
   if($r['type']==='initial'&&$r['cycle_status']!=='stock_requested')throw new DomainException('Initial request not awaiting approval.','daily_state_invalid',409);
   if($r['type']==='additional'&&$r['cycle_status']!=='issued')throw new DomainException('Additional request not awaiting approval.','daily_state_invalid',409);
   if(!in_array($r['type'],['initial','additional'],true))throw new DomainException('Unknown request type.','daily_request_invalid',422);
   $newStatus=$r['type']==='initial'?'draft':'rejected';
   Db::mustUpdate($db,$rt,['status'=>$newStatus],['id'=>$request]);
   if($r['type']==='initial')Db::mustUpdate($db,$ct,['status'=>'morning_draft'],['id'=>(int)$r['daily_cycle_id']]);
   Audit::add($a,'daily_order.reject','daily_request',$request,['cycle_id'=>(int)$r['daily_cycle_id'],'reason'=>$reason,'type'=>$r['type']]);
   return['id'=>$request,'cycle_id'=>(int)$r['daily_cycle_id'],'status'=>$newStatus];
  });
 }

 /** Cancel a not-yet-issued additional stock request; stock already issued is never reverted here. */
 public static function cancelAdditional(Actor $a,int $request,string $reason):array{
  $reason=trim($reason);if(strlen($reason)<5||strlen($reason)>255)throw new DomainException('Cancellation reason (5–255 chars) is required.','daily_reason_invalid',422);
  return Transaction::run(function()use($a,$request,$reason){
   $db=Db::wpdb();$rt=Db::table('daily_requests');$ct=Db::table('daily_cycles');
   $r=$db->get_row($db->prepare("SELECT r.*,c.branch_id,c.employee_id,c.company_id,c.business_date,c.status cycle_status FROM {$rt} r JOIN {$ct} c ON c.id=r.daily_cycle_id WHERE r.id=%d AND c.company_id=%d FOR UPDATE",$request,$a->companyId),ARRAY_A);
   if(!$r)throw new DomainException('Daily request not found.','daily_request_not_found',404);
   $cap=(int)$r['employee_id']===$a->employeeId?Capabilities::DAILY_SELF:Capabilities::DAILY_OTHERS;
   Guard::branch($a,(int)$r['branch_id'],$cap);
   if((int)$r['employee_id']!==$a->employeeId)HierarchyScope::assertCanViewEmployee($a,(int)$r['employee_id']);
   BranchDayGuard::assertOpen($a,(int)$r['branch_id'],(string)$r['business_date']);
   if($r['type']!=='additional'||$r['cycle_status']!=='issued'||!in_array($r['status'],['draft','submitted','approved'],true))throw new DomainException('Only pending additional requests may be cancelled.','daily_request_state_invalid',409);
   Db::mustUpdate($db,$rt,['status'=>'cancelled'],['id'=>$request]);
   Audit::add($a,'daily_order.cancel_additional','daily_request',$request,['cycle_id'=>(int)$r['daily_cycle_id'],'reason'=>$reason]);
   return['id'=>$request,'cycle_id'=>(int)$r['daily_cycle_id'],'status'=>'cancelled'];
  });
 }

 /** A cancelled day keeps its unique record; reopening restores its original request instead of duplicating a cycle. */
 public static function cancelCycle(Actor $a,int $id,string $reason):array{
  $reason=trim($reason);if(strlen($reason)<5||strlen($reason)>255)throw new DomainException('Cancellation reason (5–255 chars) is required.','daily_reason_invalid',422);
  return Transaction::run(function()use($a,$id,$reason){
   $c=self::cycle($a,$id,true);
   $cap=(int)$c['employee_id']===$a->employeeId?Capabilities::DAILY_SELF:Capabilities::DAILY_OTHERS;
   Guard::branch($a,(int)$c['branch_id'],$cap);
   if((int)$c['employee_id']!==$a->employeeId)HierarchyScope::assertCanViewEmployee($a,(int)$c['employee_id']);
   BranchDayGuard::assertOpen($a,(int)$c['branch_id'],(string)$c['business_date']);
   if(!in_array($c['status'],['morning_draft','stock_requested'],true))throw new DomainException('Only unapproved Daily Orders can be cancelled.','daily_state_invalid',409);
   $db=Db::wpdb();$rt=Db::table('daily_requests');
   $r=$db->get_row($db->prepare("SELECT * FROM {$rt} WHERE daily_cycle_id=%d AND type='initial' FOR UPDATE",$id),ARRAY_A);
   if(!$r||!in_array($r['status'],['draft','submitted'],true))throw new DomainException('The initial request is not cancellable.','daily_request_state_invalid',409);
   Db::mustUpdate($db,$rt,['status'=>'cancelled'],['id'=>(int)$r['id']]);
   Db::mustUpdate($db,Db::table('daily_cycles'),['status'=>'cancelled'],['id'=>$id]);
   Audit::add($a,'daily_order.cancel','daily_cycle',$id,['branch_id'=>(int)$c['branch_id'],'reason'=>$reason]);
   return['id'=>$id,'status'=>'cancelled'];
  });
 }
 public static function reopenCancelled(Actor $a,int $id):array{
  return Transaction::run(function()use($a,$id){
   $c=self::cycle($a,$id,true);
   $cap=(int)$c['employee_id']===$a->employeeId?Capabilities::DAILY_SELF:Capabilities::DAILY_OTHERS;
   Guard::branch($a,(int)$c['branch_id'],$cap);
   if((int)$c['employee_id']!==$a->employeeId)HierarchyScope::assertCanViewEmployee($a,(int)$c['employee_id']);
   BranchDayGuard::assertOpen($a,(int)$c['branch_id'],(string)$c['business_date']);
   if($c['status']!=='cancelled')throw new DomainException('Only a cancelled initial order can be reopened.','daily_state_invalid',409);
   $db=Db::wpdb();$rt=Db::table('daily_requests');
   $r=$db->get_row($db->prepare("SELECT * FROM {$rt} WHERE daily_cycle_id=%d AND type='initial' FOR UPDATE",$id),ARRAY_A);
   if(!$r||$r['status']!=='cancelled')throw new DomainException('Cancelled initial request missing.','daily_request_state_invalid',409);
   $issued=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('daily_issue_lines')." WHERE daily_request_id=%d",(int)$r['id']));
   $evening=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('evening_settlements')." WHERE daily_cycle_id=%d",$id));
   if($issued||$evening)throw new DomainException('Issued or closed orders cannot reopen as drafts.','daily_state_invalid',409);
   Db::mustUpdate($db,$rt,['status'=>'draft'],['id'=>(int)$r['id']]);
   Db::mustUpdate($db,Db::table('daily_cycles'),['status'=>'morning_draft'],['id'=>$id]);
   Audit::add($a,'daily_order.reopen_draft','daily_cycle',$id,['branch_id'=>(int)$c['branch_id']]);
   return['id'=>$id,'status'=>'morning_draft'];
  });
 }
 public static function submit(Actor $a,int $id):array{return Transaction::run(function()use($a,$id){$c=self::cycle($a,$id,true);$cap=(int)$c['employee_id']===$a->employeeId?Capabilities::DAILY_SELF:Capabilities::DAILY_OTHERS;Guard::branch($a,(int)$c['branch_id'],$cap);if((int)$c['employee_id']!==$a->employeeId)HierarchyScope::assertCanViewEmployee($a,(int)$c['employee_id']);BranchDayGuard::assertOpen($a,(int)$c['branch_id'],(string)$c['business_date']);if($c['status']!=='morning_draft')throw new DomainException('Daily Order not draft.');$db=Db::wpdb();$r=$db->get_row($db->prepare("SELECT * FROM ".Db::table('daily_requests')." WHERE daily_cycle_id=%d AND type='initial'",$id),ARRAY_A);if(!$r||$r['status']!=='draft')throw new DomainException('Initial request is not draft.','daily_request_state_invalid',409);Db::mustUpdate($db,Db::table('daily_requests'),['status'=>'submitted'],['id'=>(int)$r['id']]);Db::mustUpdate($db,Db::table('daily_cycles'),['status'=>'stock_requested'],['id'=>$id]);Audit::add($a,'daily_order.submit','daily_cycle',$id,['branch_id'=>(int)$c['branch_id'],'request_id'=>(int)$r['id']]);return['id'=>$id,'status'=>'stock_requested'];});}
 public static function additional(Actor $a,int $id,array $lines):array{return Transaction::run(function()use($a,$id,$lines){$c=self::cycle($a,$id,true);$cap=(int)$c['employee_id']===$a->employeeId?Capabilities::DAILY_SELF:Capabilities::DAILY_OTHERS;Guard::branch($a,(int)$c['branch_id'],$cap);if((int)$c['employee_id']!==$a->employeeId)HierarchyScope::assertCanViewEmployee($a,(int)$c['employee_id']);BranchDayGuard::assertOpen($a,(int)$c['branch_id'],(string)$c['business_date']);if($c['status']!=='issued')throw new DomainException('Additional stock only after issue.');if(!$lines)throw new DomainException('Additional Stock request needs product lines.');$db=Db::wpdb();$pending=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('daily_requests')." WHERE daily_cycle_id=%d AND type='additional' AND status IN ('draft','submitted','approved')",$id));if($pending)throw new DomainException('A pending Additional Stock request already exists.','additional_request_pending',409);$prepared=[];$seen=[];foreach($lines as$x){$pid=(int)($x['product_id']??0);$qty=(float)($x['quantity']??0);if(!$pid||$qty<=0)throw new DomainException('Invalid additional line.');if(isset($seen[$pid]))throw new DomainException('Duplicate product in Additional Stock request.','duplicate_daily_line',422);$seen[$pid]=1;StockService::product($a,$pid);$prepared[]=['product_id'=>$pid,'quantity'=>$qty];}Db::mustInsert($db,Db::table('daily_requests'),['daily_cycle_id'=>$id,'type'=>'additional','status'=>'submitted','requested_by'=>$a->employeeId,'created_at'=>Db::now()]);$rid=(int)$db->insert_id;foreach($prepared as$x)Db::mustInsert($db,Db::table('daily_request_lines'),['daily_request_id'=>$rid,'product_id'=>$x['product_id'],'batch_id'=>null,'quantity'=>$x['quantity']]);Audit::add($a,'daily_order.additional','daily_request',$rid,['branch_id'=>(int)$c['branch_id'],'cycle_id'=>$id]);return['id'=>$rid,'cycle_id'=>$id,'status'=>'submitted'];});}
 public static function approve(Actor $a,int $request):array{return Transaction::run(function()use($a,$request){$db=Db::wpdb();$r=$db->get_row($db->prepare("SELECT r.*,c.branch_id,c.employee_id,c.company_id,c.business_date FROM ".Db::table('daily_requests')." r JOIN ".Db::table('daily_cycles')." c ON c.id=r.daily_cycle_id WHERE r.id=%d AND c.company_id=%d FOR UPDATE",$request,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Daily request not found.');$authority=ActingDutyService::assertAction($a,(int)$r['branch_id'],'daily.approve',(int)$r['requested_by']);if($authority['mode']==='permanent')HierarchyScope::assertCanViewEmployee($a,(int)$r['employee_id']);BranchDayGuard::assertOpen($a,(int)$r['branch_id'],(string)$r['business_date']);if($r['status']!=='submitted')throw new DomainException('Request not submitted.');if((int)$r['requested_by']===$a->employeeId)throw new DomainException('Maker cannot approve own request.','maker_checker_required',409);Db::mustUpdate($db,Db::table('daily_requests'),['status'=>'approved','approved_by'=>$a->employeeId,'approved_at'=>Db::now()],['id'=>$request]);if($r['type']==='initial')Db::mustUpdate($db,Db::table('daily_cycles'),['status'=>'approved'],['id'=>(int)$r['daily_cycle_id']]);Audit::add($a,'daily_order.approve','daily_request',$request,['branch_id'=>(int)$r['branch_id'],'cycle_id'=>(int)$r['daily_cycle_id'],'type'=>(string)$r['type']]);return['id'=>$request,'status'=>'approved'];});}
 public static function issuePreflight(Actor $a,int $request):array{
  $db=Db::wpdb();$r=$db->get_row($db->prepare("SELECT r.*,c.branch_id,c.employee_id,c.company_id,c.business_date,c.id daily_cycle_id FROM ".Db::table('daily_requests')." r JOIN ".Db::table('daily_cycles')." c ON c.id=r.daily_cycle_id WHERE r.id=%d AND c.company_id=%d",$request,$a->companyId),ARRAY_A);
  if(!$r)throw new DomainException('Daily request not found.','daily_request_not_found',404);
  $authority=ActingDutyService::assertAction($a,(int)$r['branch_id'],'daily.issue',(int)$r['requested_by']);
  if($authority['mode']==='permanent')HierarchyScope::assertCanViewEmployee($a,(int)$r['employee_id']);
  BranchDayGuard::assertOpen($a,(int)$r['branch_id'],(string)$r['business_date']);
  if($r['status']!=='approved')throw new DomainException('Request not approved.','daily_request_state_invalid',409);
  if((int)$r['requested_by']===$a->employeeId)throw new DomainException('Requester cannot issue own stock.','maker_checker_required',409);
  $lines=(array)$db->get_results($db->prepare("SELECT l.*,p.name product_name,p.sku FROM ".Db::table('daily_request_lines')." l JOIN ".Db::table('products')." p ON p.id=l.product_id WHERE l.daily_request_id=%d ORDER BY l.id",$request),ARRAY_A);
  $all=true;$out=[];$requestedTotal=0.0;$availableTotal=0.0;
  foreach($lines as$l){$required=round((float)$l['quantity'],3);$available=StockService::warehouseAvailable($a,(int)$r['branch_id'],(int)$l['product_id']);$issueable=$available+.0001>=$required;if(!$issueable)$all=false;$requestedTotal+=$required;$availableTotal+=min($available,$required);$out[]=['request_line_id'=>(int)$l['id'],'product_id'=>(int)$l['product_id'],'product_name'=>(string)$l['product_name'],'sku'=>(string)($l['sku']??''),'required_quantity'=>$required,'available_quantity'=>$available,'shortage_quantity'=>round(max(0,$required-$available),3),'issueable'=>$issueable];}
  return['request_id'=>$request,'cycle_id'=>(int)$r['daily_cycle_id'],'branch_id'=>(int)$r['branch_id'],'employee_id'=>(int)$r['employee_id'],'all_available'=>$all,'requested_quantity'=>round($requestedTotal,3),'allocatable_quantity'=>round($availableTotal,3),'lines'=>$out];
 }
 public static function issue(Actor $a,int $request,array $alloc):array{return Transaction::run(function()use($a,$request,$alloc){$db=Db::wpdb();$issuedQty=0.0;$issueRows=0;$r=$db->get_row($db->prepare("SELECT r.*,c.branch_id,c.employee_id,c.company_id,c.business_date FROM ".Db::table('daily_requests')." r JOIN ".Db::table('daily_cycles')." c ON c.id=r.daily_cycle_id WHERE r.id=%d AND c.company_id=%d FOR UPDATE",$request,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Daily request not found.');$authority=ActingDutyService::assertAction($a,(int)$r['branch_id'],'daily.issue',(int)$r['requested_by']);if($authority['mode']==='permanent')HierarchyScope::assertCanViewEmployee($a,(int)$r['employee_id']);BranchDayGuard::assertOpen($a,(int)$r['branch_id'],(string)$r['business_date']);if($r['status']!=='approved')throw new DomainException('Request not approved.');if((int)$r['requested_by']===$a->employeeId)throw new DomainException('Requester cannot issue own stock.','maker_checker_required',409);$wanted=(array)$db->get_results($db->prepare("SELECT * FROM ".Db::table('daily_request_lines')." WHERE daily_request_id=%d",$request),ARRAY_A);$map=[];foreach($alloc as$x)$map[(int)($x['request_line_id']??0)][]=$x;if(!$alloc){foreach($wanted as$w)$map[(int)$w['id']][]=['request_line_id'=>(int)$w['id'],'quantity'=>(float)$w['quantity']];}foreach($wanted as$w){$parts=$map[(int)$w['id']]??[];if(!$parts)throw new DomainException('Every request line needs allocation.');$sum=0.0;foreach($parts as$x)$sum+=(float)($x['quantity']??0);if(abs($sum-(float)$w['quantity'])>.0001)throw new DomainException('Issue allocation must equal requested quantity.');$p=StockService::product($a,(int)$w['product_id']);$com=StockService::commercial($a,(int)$w['product_id']);foreach($parts as$x){$batch=isset($x['batch_id'])?(int)$x['batch_id']:null;$qty=(float)$x['quantity'];$slices=$batch?[['batch_id'=>$batch,'quantity'=>$qty]]:StockService::automaticCustodyAllocations($a,(int)$r['branch_id'],(int)$w['product_id'],$qty);foreach($slices as$slice){$sliceBatch=$slice['batch_id']!==null?(int)$slice['batch_id']:null;$sliceQty=(float)$slice['quantity'];StockService::validateBatch($a,$p,$sliceBatch,true);$cost=StockService::transferCustody($a,(int)$r['branch_id'],(int)$r['employee_id'],(int)$w['product_id'],$sliceBatch,$sliceQty,'daily_issue',$request);Db::mustInsert($db,Db::table('daily_issue_lines'),['daily_request_id'=>$request,'product_id'=>(int)$w['product_id'],'batch_id'=>$sliceBatch,'quantity'=>$sliceQty,'sale_price_snapshot'=>(float)$com['sale_price'],'ho_amount_snapshot'=>(float)$com['ho_amount'],'bm_profit_snapshot'=>(float)$com['bm_profit'],'office_expense_snapshot'=>(float)$com['office_expense'],'points_snapshot'=>(float)$com['points'],'salary_fund_snapshot'=>(float)$com['salary_fund'],'purchase_cost_snapshot'=>$cost]);$issuedQty+=$sliceQty;$issueRows++;}}}Db::mustUpdate($db,Db::table('daily_requests'),['status'=>'issued','issued_by'=>$a->employeeId,'issued_at'=>Db::now()],['id'=>$request]);if($r['type']==='initial')Db::mustUpdate($db,Db::table('daily_cycles'),['status'=>'issued'],['id'=>(int)$r['daily_cycle_id']]);Audit::add($a,'daily_order.issue','daily_request',$request,['branch_id'=>(int)$r['branch_id'],'cycle_id'=>(int)$r['daily_cycle_id'],'type'=>(string)$r['type']]);return['id'=>$request,'status'=>'issued','cycle_id'=>(int)$r['daily_cycle_id'],'employee_id'=>(int)$r['employee_id'],'issued_quantity'=>round($issuedQty,3),'issue_lines'=>$issueRows,'stock_moved'=>$issuedQty>0];});}
 public static function eveningStart(Actor $a,int $id):array{return Transaction::run(function()use($a,$id){$c=self::cycle($a,$id,true);$cap=(int)$c['employee_id']===$a->employeeId?Capabilities::DAILY_SELF:Capabilities::DAILY_OTHERS;Guard::branch($a,(int)$c['branch_id'],$cap);if((int)$c['employee_id']!==$a->employeeId)HierarchyScope::assertCanViewEmployee($a,(int)$c['employee_id']);BranchDayGuard::assertOpen($a,(int)$c['branch_id'],(string)$c['business_date']);if($c['status']!=='issued')throw new DomainException('Evening can start only after issue.');$db=Db::wpdb();$pending=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('daily_requests')." WHERE daily_cycle_id=%d AND type='additional' AND status IN ('draft','submitted','approved')",$id));if($pending)throw new DomainException('Pending Additional Stock request must be completed first.','additional_request_pending',409);$existing=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('evening_settlements')." WHERE daily_cycle_id=%d",$id));if($existing)throw new DomainException('Evening Settlement already exists.','evening_exists',409);Db::mustInsert($db,Db::table('evening_settlements'),['daily_cycle_id'=>$id,'status'=>'draft','created_at'=>Db::now()]);$eid=(int)$db->insert_id;$issues=(array)$db->get_results($db->prepare("SELECT il.* FROM ".Db::table('daily_issue_lines')." il JOIN ".Db::table('daily_requests')." r ON r.id=il.daily_request_id WHERE r.daily_cycle_id=%d",$id),ARRAY_A);foreach($issues as$l)Db::mustInsert($db,Db::table('evening_lines'),['evening_settlement_id'=>$eid,'issue_line_id'=>(int)$l['id'],'product_id'=>(int)$l['product_id'],'batch_id'=>$l['batch_id'],'issued_quantity'=>(float)$l['quantity'],'return_quantity'=>0,'retail_quantity'=>(float)$l['quantity'],'wholesale_quantity'=>0,'retail_rate'=>(float)$l['sale_price_snapshot'],'wholesale_rate'=>0,'total_amount'=>round((float)$l['quantity']*(float)$l['sale_price_snapshot'],2),'ho_amount'=>round((float)$l['quantity']*(float)$l['ho_amount_snapshot'],2),'bm_profit'=>round((float)$l['quantity']*(float)$l['bm_profit_snapshot'],2),'office_expense'=>round((float)$l['quantity']*(float)$l['office_expense_snapshot'],2),'points'=>round((float)$l['quantity']*(float)$l['points_snapshot'],2),'salary_fund'=>round((float)$l['quantity']*(float)$l['salary_fund_snapshot'],2),'purchase_cost_snapshot'=>(float)$l['purchase_cost_snapshot']]);Db::mustUpdate($db,Db::table('daily_cycles'),['status'=>'evening_draft'],['id'=>$id]);Audit::add($a,'daily_order.evening_start','daily_cycle',$id,['branch_id'=>(int)$c['branch_id'],'evening_id'=>$eid]);return['id'=>$id,'evening_id'=>$eid,'status'=>'evening_draft'];});}
 public static function eveningSave(Actor $a,int $id,array $lines,array $wholesale,string $priceReason):array{
  return Transaction::run(function()use($a,$id,$lines,$wholesale,$priceReason){
   $c=self::cycle($a,$id,true);$cap=(int)$c['employee_id']===$a->employeeId?Capabilities::DAILY_SELF:Capabilities::DAILY_OTHERS;Guard::branch($a,(int)$c['branch_id'],$cap);if((int)$c['employee_id']!==$a->employeeId)HierarchyScope::assertCanViewEmployee($a,(int)$c['employee_id']);BranchDayGuard::assertOpen($a,(int)$c['branch_id'],(string)$c['business_date']);if($c['status']!=='evening_draft')throw new DomainException('Evening not editable.');
   $db=Db::wpdb();$e=$db->get_row($db->prepare("SELECT * FROM ".Db::table('evening_settlements')." WHERE daily_cycle_id=%d FOR UPDATE",$id),ARRAY_A);if(!$e||$e['status']!=='draft')throw new DomainException('Evening Settlement is not draft.','evening_state_invalid',409);
   $stored=(array)$db->get_results($db->prepare("SELECT * FROM ".Db::table('evening_lines')." WHERE evening_settlement_id=%d ORDER BY id FOR UPDATE",(int)$e['id']),ARRAY_A);
   $map=[];foreach($lines as$x){$issueLine=(int)($x['issue_line_id']??0);if($issueLine<1||isset($map[$issueLine]))throw new DomainException('Every issued line must be supplied exactly once.','evening_line_invalid',422);$map[$issueLine]=$x;}if(count($map)!==count($stored))throw new DomainException('Every issued line must be verified exactly once.','evening_line_missing',422);
   // Always price a closing from the immutable issued-unit snapshots, never a prior evening save.
   $issueRows=(array)$db->get_results($db->prepare("SELECT il.id,il.ho_amount_snapshot,il.bm_profit_snapshot,il.office_expense_snapshot,il.points_snapshot,il.salary_fund_snapshot FROM ".Db::table('daily_issue_lines')." il JOIN ".Db::table('daily_requests')." dr ON dr.id=il.daily_request_id WHERE dr.daily_cycle_id=%d",$id),ARRAY_A);
   $snapshots=[];foreach($issueRows as$issueRow)$snapshots[(int)$issueRow['id']]=$issueRow;
   $expected=0.0;$hasWholesale=false;
   foreach($stored as$r){
    $x=$map[(int)$r['issue_line_id']]??throw new DomainException('Issued line missing from Evening Settlement.','evening_line_missing',422);$issued=(float)$r['issued_quantity'];$ret=0;$wh=0;try{$ret=WholePcsGuard::assertWhole($x['return_quantity']??0,'return_quantity');$wh=WholePcsGuard::assertWhole($x['wholesale_quantity']??0,'wholesale_quantity');}catch(\InvalidArgumentException $error){throw new DomainException($error->getMessage(),'whole_pcs_required',422);}if($ret+$wh>$issued+.0001)throw new DomainException('Return + wholesale cannot exceed issued.');$retail=$issued-$ret-$wh;$rr=(float)($x['retail_rate']??$r['retail_rate']);$wr=(float)($x['wholesale_rate']??0);$approved=(float)$r['retail_rate'];if(abs($rr-$approved)>.005)throw new DomainException('Retail rate cannot change without approved pricing authority.','price_authority_required',409);if($rr<0||$wr<0||($wh>0&&($wr<=0||$wr>$rr)))throw new DomainException('Invalid retail/wholesale sale rate.');$amount=round($retail*$rr+$wh*$wr,2);$snapshot=$snapshots[(int)$r['issue_line_id']]??throw new DomainException('Original issued line missing.','evening_issue_snapshot_missing',409);$sold=$retail+$wh;$ho=round($sold*(float)$snapshot['ho_amount_snapshot'],2);$bm=round($sold*(float)$snapshot['bm_profit_snapshot'],2);$expense=round($sold*(float)$snapshot['office_expense_snapshot'],2);$points=round($sold*(float)$snapshot['points_snapshot'],2);$salary=round($sold*(float)$snapshot['salary_fund_snapshot'],2);
     // Owner-approved wholesale allocation: split the wholesale discount 50/50
     // between BM Profit and Salary Fund; leave HO, Office and Points unchanged.
     // Validate against the wholesale units' own budget (not retail units).
     // Any odd paise goes to BM; Salary Fund receives the exact remainder.
     $discount=round($wh*max(0.0,$rr-$wr),2);
     $bmDiscount=round($discount/2,2);
     $salaryDiscount=round($discount-$bmDiscount,2);
     if($bmDiscount>round($wh*(float)$snapshot['bm_profit_snapshot'],2)+.005||
        $salaryDiscount>round($wh*(float)$snapshot['salary_fund_snapshot'],2)+.005) {
         throw new DomainException('Wholesale discount exceeds BM Profit or Salary Fund available on wholesale units. Raise wholesale rate.','wholesale_discount_exceeds_allocation',422);
     }
     $bm=round($bm-$bmDiscount,2);$salary=round($salary-$salaryDiscount,2);
     if(abs(round($ho+$bm+$expense+$salary,2)-$amount)>.01) {
         throw new DomainException('Wholesale distribution does not reconcile to actual sales.','wholesale_distribution_mismatch',422);
     }
    Db::mustUpdate($db,Db::table('evening_lines'),['return_quantity'=>$ret,'retail_quantity'=>$retail,'wholesale_quantity'=>$wh,'retail_rate'=>$rr,'wholesale_rate'=>$wr,'total_amount'=>$amount,'ho_amount'=>$ho,'bm_profit'=>$bm,'office_expense'=>$expense,'points'=>$points,'salary_fund'=>$salary],['id'=>(int)$r['id']]);$expected+=$amount;if($wh>0)$hasWholesale=true;
   }
   if($hasWholesale&&trim((string)($wholesale['wholesale_customer_name']??''))==='')throw new DomainException('Wholesale customer name required.');
   Db::mustUpdate($db,Db::table('evening_settlements'),['expected_amount'=>round($expected,2),'wholesale_customer_name'=>$hasWholesale?(string)$wholesale['wholesale_customer_name']:null,'notes'=>$priceReason],['id'=>(int)$e['id']]);
   Audit::add($a,'daily_order.evening_save','daily_cycle',$id,['branch_id'=>(int)$c['branch_id'],'evening_id'=>(int)$e['id'],'expected_amount'=>round($expected,2)]);
   return['id'=>$id,'expected_amount'=>round($expected,2)];
  });
 }
 public static function eveningSubmit(Actor $a,int $id):array{
  return Transaction::run(function()use($a,$id){
   $c=self::cycle($a,$id,true);$cap=(int)$c['employee_id']===$a->employeeId?Capabilities::DAILY_SELF:Capabilities::DAILY_OTHERS;Guard::branch($a,(int)$c['branch_id'],$cap);if((int)$c['employee_id']!==$a->employeeId)HierarchyScope::assertCanViewEmployee($a,(int)$c['employee_id']);BranchDayGuard::assertOpen($a,(int)$c['branch_id'],(string)$c['business_date']);if($c['status']!=='evening_draft')throw new DomainException('Evening not draft.');
   $db=Db::wpdb();$e=$db->get_row($db->prepare("SELECT * FROM ".Db::table('evening_settlements')." WHERE daily_cycle_id=%d FOR UPDATE",$id),ARRAY_A);if(!$e||$e['status']!=='draft')throw new DomainException('Evening Settlement is not draft.','evening_state_invalid',409);
   // Never submit unsaved or stale totals. EveningStart creates draft lines
   // with default retail assumptions, but only EveningSave reconciles them
   // into expected_amount after the employee verifies returns/wholesale.
   $closingLines=(array)$db->get_results($db->prepare("SELECT issued_quantity,return_quantity,retail_quantity,wholesale_quantity,retail_rate,wholesale_rate,total_amount,ho_amount,bm_profit,office_expense,salary_fund FROM ".Db::table('evening_lines')." WHERE evening_settlement_id=%d FOR UPDATE",(int)$e['id']),ARRAY_A);
   if(!$closingLines)throw new DomainException('Evening Closing has no issued lines.','evening_lines_missing',409);
   $computed=0.0;
   foreach($closingLines as$line){
    $issued=(float)$line['issued_quantity'];$ret=(float)$line['return_quantity'];$retail=(float)$line['retail_quantity'];$wh=(float)$line['wholesale_quantity'];
    if($issued<0||$ret<0||$retail<0||$wh<0||abs(($ret+$retail+$wh)-$issued)>.0001)throw new DomainException('Evening Closing quantities do not reconcile.','evening_quantities_mismatch',409);
    $lineAmount=round($retail*(float)$line['retail_rate']+$wh*(float)$line['wholesale_rate'],2);
    if(abs($lineAmount-(float)$line['total_amount'])>.005)throw new DomainException('Evening Closing line amount does not reconcile.','evening_totals_mismatch',409);
    self::assertEveningDistribution($line);
    $computed+=$lineAmount;
   }
   if(abs(round($computed,2)-round((float)$e['expected_amount'],2))>.005)throw new DomainException('Save and verify the Evening Closing totals before submission.','evening_totals_mismatch',409);
   Db::mustUpdate($db,Db::table('evening_settlements'),['status'=>'submitted','submitted_by'=>$a->employeeId,'submitted_at'=>Db::now()],['id'=>(int)$e['id']]);
   Db::mustUpdate($db,Db::table('daily_cycles'),['status'=>'evening_submitted'],['id'=>$id]);
   Audit::add($a,'daily_order.evening_submit','daily_cycle',$id,['branch_id'=>(int)$c['branch_id'],'evening_id'=>(int)$e['id'],'expected_amount'=>(float)$e['expected_amount']]);
   return['id'=>$id,'status'=>'evening_submitted','expected_amount'=>(float)$e['expected_amount']];
  });
 }
 public static function finalPost(Actor $a,int $id,float $cash,float $upi):array{return Transaction::run(function()use($a,$id,$cash,$upi){$c=self::cycle($a,$id,true);BranchDayGuard::assertOpen($a,(int)$c['branch_id'],(string)$c['business_date']);if($c['status']!=='evening_submitted')throw new DomainException('Daily Order not ready for final post.');$db=Db::wpdb();$e=$db->get_row($db->prepare("SELECT * FROM ".Db::table('evening_settlements')." WHERE daily_cycle_id=%d FOR UPDATE",$id),ARRAY_A);if(!$e||$e['status']!=='submitted')throw new DomainException('Submitted Evening Settlement not found.','evening_state_invalid',409);$authority=ActingDutyService::assertAction($a,(int)$c['branch_id'],'daily.final_post',(int)$e['submitted_by']);if($authority['mode']==='permanent'&&(int)$c['employee_id']!==$a->employeeId)HierarchyScope::assertCanViewEmployee($a,(int)$c['employee_id']);$expected=round((float)$e['expected_amount'],2);if((int)$e['submitted_by']===$a->employeeId)throw new DomainException('Evening maker cannot final-post own settlement.','maker_checker_required',409);if($cash<0||$upi<0)throw new DomainException('Payment amounts cannot be negative.');if(abs(($cash+$upi)-$expected)>.005)throw new DomainException('Cash + UPI must equal expected amount.','payment_mismatch',409);$lines=(array)$db->get_results($db->prepare("SELECT * FROM ".Db::table('evening_lines')." WHERE evening_settlement_id=%d",(int)$e['id']),ARRAY_A);$points=0.0;$salary=0.0;$cogs=0.0;foreach($lines as$l){self::assertEveningDistribution($l);$batch=$l['batch_id']!==null?(int)$l['batch_id']:null;$ret=(float)$l['return_quantity'];$sold=(float)$l['retail_quantity']+(float)$l['wholesale_quantity'];$cost=(float)$l['purchase_cost_snapshot'];if($ret>0){StockService::move($a,(int)$c['branch_id'],(int)$l['product_id'],$batch,(int)$c['employee_id'],'OUT',$ret,$cost,'daily_return',$id);StockService::move($a,(int)$c['branch_id'],(int)$l['product_id'],$batch,null,'IN',$ret,$cost,'daily_return',$id);}if($sold>0)StockService::move($a,(int)$c['branch_id'],(int)$l['product_id'],$batch,(int)$c['employee_id'],'OUT',$sold,$cost,'daily_sale',$id);$points+=(float)$l['points'];$salary+=(float)$l['salary_fund'];$cogs+=round($sold*$cost,2);} $settings=(array)$db->get_results($db->prepare("SELECT setting_key,setting_value FROM ".Db::table('settings')." WHERE company_id=%d AND setting_key IN ('daily_cash_account_id','daily_upi_account_id')",$a->companyId),ARRAY_A);$map=[];foreach($settings as$s)$map[$s['setting_key']]=(int)$s['setting_value'];if(($cash>0&&!isset($map['daily_cash_account_id']))||($upi>0&&!isset($map['daily_upi_account_id'])))throw new DomainException('Daily payment accounts not configured.','payment_accounts_missing',409);if($cash>0){$cashAcc=AccountingService::paymentAccount($a,(int)$map['daily_cash_account_id']);if(strtolower((string)$cashAcc['subtype'])!=='cash')throw new DomainException('Daily Cash account must be Cash ledger.','payment_account_invalid',409);}if($upi>0){$upiAcc=AccountingService::paymentAccount($a,(int)$map['daily_upi_account_id']);if(strtolower((string)$upiAcc['subtype'])!=='upi')throw new DomainException('Daily UPI account must be UPI ledger.','payment_account_invalid',409);}$sales=AccountingService::accountByCode($a,'SALES');$cogsA=AccountingService::accountByCode($a,'COGS');$inv=AccountingService::accountByCode($a,'INVENTORY');$jl=[];if($cash>0)$jl[]=['account_id'=>$map['daily_cash_account_id'],'debit'=>$cash];if($upi>0)$jl[]=['account_id'=>$map['daily_upi_account_id'],'debit'=>$upi];$jl[]=['account_id'=>(int)$sales['id'],'credit'=>$expected];if($cogs>0){$jl[]=['account_id'=>(int)$cogsA['id'],'debit'=>$cogs];$jl[]=['account_id'=>(int)$inv['id'],'credit'=>$cogs];}$journal=AccountingService::post($a,(int)$c['branch_id'],'daily_cycle',$id,$c['business_date'].' 23:59:59',$jl,'Daily Order final post');Db::mustInsert($db,Db::table('performance_entries'),['company_id'=>$a->companyId,'branch_id'=>(int)$c['branch_id'],'employee_id'=>(int)$c['employee_id'],'business_date'=>$c['business_date'],'source_type'=>'daily_cycle','source_id'=>$id,'points'=>round($points,2),'salary_fund'=>round($salary,2),'created_at'=>Db::now()]);Db::mustUpdate($db,Db::table('evening_settlements'),['status'=>'posted','cash_amount'=>$cash,'upi_amount'=>$upi,'reviewed_by'=>$a->employeeId,'reviewed_at'=>Db::now()],['id'=>(int)$e['id']]);Db::mustUpdate($db,Db::table('daily_cycles'),['status'=>'completed','completed_at'=>Db::now()],['id'=>$id]);Audit::add($a,'daily_order.final_post','daily_cycle',$id,['branch_id'=>(int)$c['branch_id'],'amount'=>$expected,'journal_id'=>$journal]);return['id'=>$id,'status'=>'completed','amount'=>$expected,'points'=>round($points,2),'salary_fund'=>round($salary,2)];});}
 /** Guard posted financial splits against stale or tampered closing lines. */
 private static function assertEveningDistribution(array $line):void {
  $fields=['ho_amount','bm_profit','office_expense','salary_fund'];
  $total=0.0;
  foreach($fields as$field){
   $value=(float)($line[$field]??0);
   if(!is_finite($value)||$value<-.005)throw new DomainException('Evening distribution contains a negative or invalid allocation.','evening_distribution_mismatch',409);
   $total+=$value;
  }
  if(abs(round($total,2)-round((float)$line['total_amount'],2))>.01) {
   throw new DomainException('Evening distribution must equal actual sale amount. Resave the closing before posting.','evening_distribution_mismatch',409);
  }
 }
 private static function cycle(Actor $a,int $id,bool $lock=false):array{$db=Db::wpdb();$r=$db->get_row($db->prepare("SELECT * FROM ".Db::table('daily_cycles')." WHERE id=%d AND company_id=%d".($lock?' FOR UPDATE':''),$id,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Daily Order not found.','daily_not_found',404);return$r;}
}
