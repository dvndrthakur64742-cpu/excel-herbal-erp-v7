<?php
namespace ExcelHerbal\ERP7\Reporting;
use ExcelHerbal\ERP7\Core\Input;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;

final class ReportReviewService
{
    private const TYPES = ['trial_balance','profit_loss','balance_sheet','stock_reconciliation','finance_reconciliation'];

    public static function list(Actor $a, string $status = 'pending'): array
    {
        Guard::cap($a, Capabilities::REPORT_REVIEW);
        Guard::cap($a, Capabilities::ACCOUNTING_VIEW);
        $status = trim($status) === '' ? 'pending' : strtolower(trim($status));
        if (!in_array($status, ['pending','approved','rejected','stale','all'], true)) {
            throw new DomainException('Unsupported report review status.', 'report_review_status_invalid', 422);
        }
        $db = Db::wpdb(); $where = 'r.company_id=%d'; $args = [$a->companyId];
        $branches = array_values(array_unique(array_filter(array_map('intval', $a->branchIds), static fn($id) => $id > 0)));
        $allBranches = self::hasAllActiveBranches($a);
        if ($branches) {
            $where .= ' AND r.branch_id IN (' . implode(',', array_fill(0, count($branches), '%d')) . ')';
            $args = array_merge($args, $branches);
            if ($allBranches) { $where = '(' . $where . ' OR (r.company_id=%d AND r.branch_id IS NULL))'; $args[] = $a->companyId; }
        } elseif ($allBranches) $where .= ' AND r.branch_id IS NULL';
        else $where .= ' AND 1=0';
        if ($status !== 'all') { $where .= ' AND r.status=%s'; $args[] = $status; }
        $sql = 'SELECT r.id,r.company_id,r.branch_id,r.report_type,r.period_from,r.period_to,r.as_of_date,r.status,r.snapshot_hash,r.row_count,r.summary_json,r.requested_by,r.requested_at,r.reviewed_by,r.reviewed_at,r.decision_reason,req.full_name requester_name,rev.full_name reviewer_name ' .
            'FROM ' . Db::table('report_reviews') . ' r LEFT JOIN ' . Db::table('employees') . ' req ON req.company_id=r.company_id AND req.id=r.requested_by ' .
            'LEFT JOIN ' . Db::table('employees') . ' rev ON rev.company_id=r.company_id AND rev.id=r.reviewed_by WHERE ' . $where .
            ' ORDER BY FIELD(r.status,\'pending\',\'stale\',\'rejected\',\'approved\'),r.requested_at DESC,r.id DESC LIMIT 200';
        $rows = (array)$db->get_results($db->prepare($sql, ...$args), ARRAY_A);
        foreach ($rows as &$row) { $row['id']=(int)$row['id']; $row['branch_id']=$row['branch_id']===null?null:(int)$row['branch_id']; $row['row_count']=(int)$row['row_count']; $row['summary']=json_decode((string)$row['summary_json'],true)?:[]; unset($row['summary_json']); }
        unset($row);
        return $rows;
    }

    public static function submit(Actor $a, array $input): array
    {
        $type = strtolower(trim((string)($input['report_type'] ?? '')));
        if (!in_array($type, self::TYPES, true)) throw new DomainException('Select a supported Accounts review report.', 'report_review_type_invalid', 422);
        $branch = null;
        if (array_key_exists('branch_id',$input) && $input['branch_id']!==null && $input['branch_id']!=='') {
            $branch=filter_var($input['branch_id'],FILTER_VALIDATE_INT);
            if ($branch===false || $branch<1) throw new DomainException('A valid branch is required for this report.','report_review_branch_invalid',422);
        }
        if ($type==='stock_reconciliation' && $branch===null) throw new DomainException('Stock Reconciliation review must be tied to one branch.','report_review_branch_required',422);
        $from=null; $to=null; $asOf=null;
        if ($type==='profit_loss') [$from,$to]=Input::dateRange((string)($input['from']??''),(string)($input['to']??''),'Profit and Loss review period');
        elseif ($type==='trial_balance'||$type==='balance_sheet') $asOf=Input::date((string)($input['as_of_date']??$input['to']??''),'Report review as-of date');
        self::assertScope($a,$type,$branch);
        $rows=self::snapshot($a,$type,$branch,$from,$to,$asOf); $hash=self::hashRows($rows); $summary=self::summarise($type,$rows);
        $summaryJson=wp_json_encode($summary,JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE);
        if(!is_string($summaryJson))throw new DomainException('Report review summary could not be encoded.','report_review_summary_failed',500);
        $db=Db::wpdb();$table=Db::table('report_reviews');$where='company_id=%d AND report_type=%s AND status=%s';$args=[$a->companyId,$type,'pending'];
        if($branch===null)$where.=' AND branch_id IS NULL';else{$where.=' AND branch_id=%d';$args[]=$branch;}
        foreach(['period_from'=>$from,'period_to'=>$to,'as_of_date'=>$asOf] as$column=>$value){if($value===null)$where.=' AND '.$column.' IS NULL';else{$where.=' AND '.$column.'=%s';$args[]=$value;}}
        return Transaction::run(function()use($a,$type,$branch,$from,$to,$asOf,$hash,$summaryJson,$rows,$db,$table,$where,$args){
            $db->get_var($db->prepare('SELECT id FROM '.Db::table('companies').' WHERE id=%d FOR UPDATE',$a->companyId));
            $existing=(int)$db->get_var($db->prepare('SELECT id FROM '.$table.' WHERE '.$where.' LIMIT 1 FOR UPDATE',...$args));
            if($existing>0)throw new DomainException('A pending review already exists for this report scope.','report_review_pending_exists',409);
            $id=Db::mustInsert($db,$table,['company_id'=>$a->companyId,'branch_id'=>$branch,'report_type'=>$type,'period_from'=>$from,'period_to'=>$to,'as_of_date'=>$asOf,'status'=>'pending','snapshot_hash'=>$hash,'row_count'=>count($rows),'summary_json'=>$summaryJson,'requested_by'=>$a->employeeId,'requested_at'=>Db::now()]);
            Audit::add($a,'report_review.submit','report_review',$id,['branch_id'=>$branch,'report_type'=>$type,'snapshot_hash'=>$hash,'row_count'=>count($rows),'period_from'=>$from,'period_to'=>$to,'as_of_date'=>$asOf]);
            return self::find($a->companyId,$id);
        });
    }

    public static function decide(Actor $a,int $id,string $decision,string $reason):array
    {
        Guard::cap($a,Capabilities::REPORT_REVIEW);$decision=strtolower(trim($decision));
        if(!in_array($decision,['approve','reject'],true))throw new DomainException('Decision must be approve or reject.','report_review_decision_invalid',422);
        $reason=trim($reason);if(strlen($reason)<5||strlen($reason)>500)throw new DomainException('Enter a review note of 5 to 500 characters.','report_review_reason_required',422);
        return Transaction::run(function()use($a,$id,$decision,$reason){
            $db=Db::wpdb();$table=Db::table('report_reviews');
            $row=$db->get_row($db->prepare('SELECT * FROM '.$table.' WHERE id=%d AND company_id=%d FOR UPDATE',$id,$a->companyId),ARRAY_A);
            if(!$row)throw new DomainException('Report review request not found.','report_review_not_found',404);
            if((string)$row['status']!=='pending')throw new DomainException('This report review is no longer pending.','report_review_not_pending',409);
            if((int)$row['requested_by']===$a->employeeId)throw new DomainException('The requester cannot approve or reject their own report review.','report_review_maker_checker',403);
            $type=(string)$row['report_type'];$branch=$row['branch_id']===null?null:(int)$row['branch_id'];
            self::assertScope($a,$type,$branch);
            $from=$row['period_from']===null?null:(string)$row['period_from'];$to=$row['period_to']===null?null:(string)$row['period_to'];$asOf=$row['as_of_date']===null?null:(string)$row['as_of_date'];
            $currentHash=self::hashRows(self::snapshot($a,$type,$branch,$from,$to,$asOf));
            if(!hash_equals((string)$row['snapshot_hash'],$currentHash)){
                Db::mustUpdate($db,$table,['status'=>'stale','reviewed_by'=>$a->employeeId,'reviewed_at'=>Db::now(),'decision_reason'=>'Report data changed after submission. '.$reason],['id'=>$id,'company_id'=>$a->companyId,'status'=>'pending']);
                Audit::add($a,'report_review.stale','report_review',$id,['branch_id'=>$branch,'report_type'=>$type,'submitted_hash'=>(string)$row['snapshot_hash'],'current_hash'=>$currentHash,'reason'=>$reason]);
                return self::find($a->companyId,$id);
            }
            $status=$decision==='approve'?'approved':'rejected';
            Db::mustUpdate($db,$table,['status'=>$status,'reviewed_by'=>$a->employeeId,'reviewed_at'=>Db::now(),'decision_reason'=>$reason],['id'=>$id,'company_id'=>$a->companyId,'status'=>'pending']);
            Audit::add($a,'report_review.'.$status,'report_review',$id,['branch_id'=>$branch,'report_type'=>$type,'snapshot_hash'=>$currentHash,'reason'=>$reason]);
            return self::find($a->companyId,$id);
        });
    }

    private static function assertScope(Actor $a,string $type,?int $branch):void
    {
        if($branch!==null)return;
        if($type==='stock_reconciliation')throw new DomainException('Stock Reconciliation review must be tied to one branch.','report_review_branch_required',422);
        Guard::allActiveBranches($a,Capabilities::ACCOUNTING_VIEW);
    }

    private static function snapshot(Actor $a,string $type,?int $branch,?string $from,?string $to,?string $asOf):array
    {
        return match($type){
            'trial_balance'=>ReportingService::trialBalance($a,(string)$asOf,$branch),
            'profit_loss'=>ReportingService::profitLoss($a,(string)$from,(string)$to,$branch),
            'balance_sheet'=>ReportingService::balanceSheet($a,(string)$asOf,$branch),
            'stock_reconciliation'=>ReportingService::stockReconciliation($a,(int)$branch),
            'finance_reconciliation'=>ReportingService::financeReconciliation($a,$branch),
            default=>throw new DomainException('Unsupported report review type.','report_review_type_invalid',422),
        };
    }

    private static function hashRows(array $rows):string
    {
        $json=wp_json_encode($rows,JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE);
        if(!is_string($json))throw new DomainException('Report snapshot could not be encoded.','report_snapshot_encode_failed',500);
        return hash('sha256',$json);
    }

    private static function summarise(string $type,array $rows):array
    {
        if($type==='trial_balance'){$debit=0.0;$credit=0.0;foreach($rows as$row){$debit+=(float)($row['debit']??0);$credit+=(float)($row['credit']??0);}return['total_debit'=>round($debit,2),'total_credit'=>round($credit,2),'difference'=>round($debit-$credit,2),'balanced'=>abs($debit-$credit)<=0.01];}
        if($type==='profit_loss'){$income=0.0;$expenses=0.0;foreach($rows as$row){if(($row['section']??'')==='Income')$income+=(float)($row['amount']??0);else$expenses+=(float)($row['amount']??0);}return['income'=>round($income,2),'expenses'=>round($expenses,2),'net_profit'=>round($income-$expenses,2)];}
        if($type==='balance_sheet'){$assets=0.0;$liabilities=0.0;$equity=0.0;foreach($rows as$row){$section=(string)($row['section']??'');if($section==='Assets')$assets+=(float)($row['amount']??0);elseif($section==='Liabilities')$liabilities+=(float)($row['amount']??0);elseif($section==='Equity')$equity+=(float)($row['amount']??0);}return['assets'=>round($assets,2),'liabilities'=>round($liabilities,2),'equity'=>round($equity,2),'difference'=>round($assets-$liabilities-$equity,2),'balanced'=>abs($assets-$liabilities-$equity)<=0.01];}
        if($type==='stock_reconciliation'){$matched=0;$mismatched=0;$differenceQty=0.0;$differenceValue=0.0;$exceptions=[];foreach($rows as$row){if(($row['status']??'')==='matched')$matched++;else$mismatched++;$differenceQty+=(float)($row['difference_quantity']??0);$differenceValue+=(float)($row['difference_value']??0);if(($row['status']??'')!=='matched'&&count($exceptions)<10)$exceptions[]=['product_name'=>$row['product_name']??'','difference_quantity'=>$row['difference_quantity']??0,'difference_value'=>$row['difference_value']??0];}return['matched_rows'=>$matched,'mismatched_rows'=>$mismatched,'difference_quantity'=>round($differenceQty,3),'difference_value'=>round($differenceValue,2),'exceptions'=>$exceptions];}
        $matched=0;$mismatched=0;$checks=[];foreach($rows as$row){if(($row['status']??'')==='matched')$matched++;else$mismatched++;$checks[]=['check_name'=>$row['check_name']??'','book_value'=>$row['book_value']??0,'control_value'=>$row['control_value']??0,'difference'=>$row['difference']??0,'status'=>$row['status']??'mismatch'];}return['matched_checks'=>$matched,'mismatched_checks'=>$mismatched,'checks'=>$checks];
    }

    private static function hasAllActiveBranches(Actor $a):bool
    {
        $db=Db::wpdb();$active=array_map('intval',(array)$db->get_col($db->prepare('SELECT id FROM '.Db::table('branches').' WHERE company_id=%d AND status=%s ORDER BY id',$a->companyId,'active')));
        return count($active)>0&&count(array_diff($active,array_map('intval',$a->branchIds)))===0;
    }

    private static function find(int $companyId,int $id):array
    {
        $db=Db::wpdb();$row=$db->get_row($db->prepare(
            'SELECT r.id,r.company_id,r.branch_id,r.report_type,r.period_from,r.period_to,r.as_of_date,r.status,r.snapshot_hash,r.row_count,r.summary_json,r.requested_by,r.requested_at,r.reviewed_by,r.reviewed_at,r.decision_reason,req.full_name requester_name,rev.full_name reviewer_name FROM '.Db::table('report_reviews').' r LEFT JOIN '.Db::table('employees').' req ON req.company_id=r.company_id AND req.id=r.requested_by LEFT JOIN '.Db::table('employees').' rev ON rev.company_id=r.company_id AND rev.id=r.reviewed_by WHERE r.company_id=%d AND r.id=%d',
            $companyId,$id),ARRAY_A);
        if(!$row)throw new DomainException('Report review request not found.','report_review_not_found',404);
        $row['id']=(int)$row['id'];$row['branch_id']=$row['branch_id']===null?null:(int)$row['branch_id'];$row['row_count']=(int)$row['row_count'];$row['summary']=json_decode((string)$row['summary_json'],true)?:[];unset($row['summary_json']);return$row;
    }
}
