<?php
namespace ExcelHerbal\ERP7\Sales;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Finance\BranchDayGuard;
use ExcelHerbal\ERP7\Policy\PrepaidOrderRules as Money;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;

/**
 * Phase 1 of the prepaid return / credit-note workflow.
 *
 * This is deliberately NOT a refund payment or accounting reversal.
 * The paid invoice, collected payments, journals and stock ledger remain
 * immutable until a separately reviewed, atomic refund-posting phase ships.
 * Only complete-invoice returns are currently supported.
 */
final class PrepaidReturnService {
    private static function row(Actor $a,int $id,bool $lock=false):array {
        $db=Db::wpdb();$t=Db::table('prepaid_return_requests');
        $r=$db->get_row($db->prepare(
            "SELECT * FROM {$t} WHERE id=%d AND company_id=%d".($lock?' FOR UPDATE':''),
            $id,$a->companyId
        ),ARRAY_A);
        if(!$r)throw new DomainException('Prepaid return request not found.','prepaid_return_not_found',404);
        Guard::branch($a,(int)$r['branch_id'],Capabilities::SALES_VIEW);
        return $r;
    }

    public static function list(Actor $a,int $branch):array {
        Guard::branch($a,$branch,Capabilities::SALES_VIEW);
        $db=Db::wpdb();$t=Db::table('prepaid_return_requests');
        return (array)$db->get_results($db->prepare(
            "SELECT * FROM {$t} WHERE company_id=%d AND branch_id=%d ORDER BY id DESC LIMIT 200",
            $a->companyId,$branch
        ),ARRAY_A);
    }

    /**
     * Existing authenticated return-detail endpoint now reports whether all
     * original Cash/UPI tender evidence is reconciled. This is read-only:
     * evidence_complete NEVER means refund paid or credit note posted.
     */
    public static function detail(Actor $a,int $id):array {
        $r=self::row($a,$id);
        $db=Db::wpdb();
        $payments=(array)$db->get_results($db->prepare(
            'SELECT id,company_id,branch_id,order_id,payment_account_id,method,status,amount'.
            ' FROM '.Db::table('prepaid_sales_order_payments').
            ' WHERE company_id=%d AND branch_id=%d AND order_id=%d ORDER BY id',
            $a->companyId,(int)$r['branch_id'],(int)$r['order_id']
        ),ARRAY_A);
        $evidence=(array)$db->get_results($db->prepare(
            'SELECT id,order_payment_id,company_id,branch_id,return_id,payment_account_id,evidence_reference,'.
            'method,status,amount,submitted_by,verified_by,verification_reference'.
            ' FROM '.Db::table('prepaid_refund_evidence').
            ' WHERE company_id=%d AND branch_id=%d AND return_id=%d ORDER BY id',
            $a->companyId,(int)$r['branch_id'],$id
        ),ARRAY_A);
        $r['refund_evidence_check']=PrepaidRefundEvidencePreflight::check($r,$payments,$evidence);
        $r['refund_clearing_reconciliation']=RefundClearingReconciliation::inspect($r,$payments,$evidence,$r['refund_evidence_check']);
        return $r;
    }

    public static function requirePostedSource(int $company,int $branch,int $order,int $sale,string $amount):void {
        $db=Db::wpdb();
        $orders=Db::table('prepaid_sales_orders');
        $sales=Db::table('counter_sales');
        $journals=Db::table('journal_entries');
        $journal=$db->get_var($db->prepare(
            "SELECT j.id FROM {$orders} o
             JOIN {$sales} s ON s.id=o.sale_id AND s.company_id=o.company_id AND s.branch_id=o.branch_id
             JOIN {$journals} j ON j.id=s.journal_entry_id AND j.company_id=s.company_id AND j.branch_id=s.branch_id
             WHERE o.company_id=%d AND o.branch_id=%d AND o.id=%d AND s.id=%d
             AND o.status='posted' AND s.status='posted' AND o.net_amount=CAST(%s AS DECIMAL(14,2))
             AND s.paid_amount=o.net_amount AND s.outstanding_amount=0
             AND j.source_type='counter_sale' AND j.source_id=s.id AND j.status='posted' AND j.reversal_of IS NULL
             AND NOT EXISTS (SELECT 1 FROM {$journals} rev WHERE rev.company_id=j.company_id AND rev.reversal_of=j.id)
             FOR UPDATE",
            $company,$branch,$order,$sale,$amount
        ));
        if (!$journal) throw new DomainException('Return invoice and original posted journal must reconcile.','prepaid_return_source_mismatch',409);
    }

    /** Open one full-order return request. Never adjust money or stock here. */
    public static function request(Actor $a,int $orderId,string $reason):array {
        Guard::cap($a,Capabilities::REVERSAL_CREATE);
        $reason=trim($reason);
        if(strlen($reason)<10||strlen($reason)>255)
            throw new DomainException('A return reason of 10–255 characters is required.','prepaid_return_reason_required',422);
        return Transaction::run(function()use($a,$orderId,$reason){
            $db=Db::wpdb();$orders=Db::table('prepaid_sales_orders');
            $o=$db->get_row($db->prepare(
                "SELECT * FROM {$orders} WHERE id=%d AND company_id=%d FOR UPDATE",
                $orderId,$a->companyId
            ),ARRAY_A);
            if(!$o)throw new DomainException('Prepaid order not found.','sales_order_not_found',404);
            $branch=(int)$o['branch_id'];
            Guard::branch($a,$branch,Capabilities::REVERSAL_CREATE);
            if($o['status']!=='posted'||(int)$o['sale_id']<1)
                throw new DomainException('Only a posted, fully paid order is returnable.','prepaid_return_invoice_not_posted',409);
            BranchDayGuard::assertOpen($a,$branch,Db::today());
            $sale=$db->get_row($db->prepare(
                "SELECT * FROM ".Db::table('counter_sales')." WHERE company_id=%d AND id=%d FOR UPDATE",
                $a->companyId,(int)$o['sale_id']
            ),ARRAY_A);
            if(!$sale||$sale['status']!=='posted'||(int)$sale['branch_id']!==$branch||
               (string)$sale['outstanding_amount']!=='0.00'||
               Money::minor((string)$sale['paid_amount'])!==Money::minor((string)$o['net_amount']))
                throw new DomainException('Posted invoice and prepaid balance are inconsistent.','prepaid_return_payment_mismatch',409);
            self::requirePostedSource($a->companyId,$branch,$orderId,(int)$sale['id'],(string)$o['net_amount']);
            $payments=(array)$db->get_results($db->prepare(
                "SELECT status,amount FROM ".Db::table('prepaid_sales_order_payments').
                " WHERE company_id=%d AND order_id=%d FOR UPDATE",
                $a->companyId,$orderId
            ),ARRAY_A);
            $covered=0;
            foreach($payments as $p){
                if($p['status']!=='confirmed')
                    throw new DomainException('Unverified payment cannot be refunded.','prepaid_return_payment_mismatch',409);
                $covered+=Money::minor((string)$p['amount']);
            }
            if(!$payments||$covered!==Money::minor((string)$o['net_amount']))
                throw new DomainException('Verified payments must cover the entire invoice.','prepaid_return_payment_mismatch',409);
            $count=(int)$db->get_var($db->prepare(
                "SELECT COUNT(*) FROM ".Db::table('counter_sale_lines')." WHERE sale_id=%d",
                (int)$sale['id']
            ));
            if($count<1)throw new DomainException('Invoice has no stock lines.','prepaid_return_lines_missing',409);
            $t=Db::table('prepaid_return_requests');
            if((int)$db->get_var($db->prepare(
                "SELECT id FROM {$t} WHERE company_id=%d AND order_id=%d FOR UPDATE",
                $a->companyId,$orderId
            )))throw new DomainException('A return is already registered for this prepaid order.','prepaid_return_already_requested',409);
            Db::mustInsert($db,$t,[
                'company_id'=>$a->companyId,'branch_id'=>$branch,'order_id'=>$orderId,
                'sale_id'=>(int)$sale['id'],'customer_id'=>$o['customer_id'],
                'refund_amount'=>(string)$o['net_amount'],'reason'=>$reason,
                'status'=>'requested','requested_by'=>$a->employeeId,'requested_at'=>Db::now()
            ],'Return already registered for this invoice.','prepaid_return_already_requested');
            $id=(int)$db->insert_id;
            Audit::add($a,'sales.return.request','prepaid_return_request',$id,[
                'branch_id'=>$branch,'order_id'=>$orderId,'sale_id'=>(int)$sale['id'],
                'refund_amount'=>(string)$o['net_amount']
            ]);
            return ['id'=>$id,'order_id'=>$orderId,'status'=>'requested','refund_amount'=>(string)$o['net_amount'],'financial_posted'=>false];
        });
    }

    /**
     * Independent physical receipt confirmation. Stock stays unposted/
     * quarantined until a full refund+credit-note posting feature exists.
     */
    public static function inspect(Actor $a,int $id,string $reference,string $notes=''):array {
        Guard::cap($a,Capabilities::REVERSAL_APPROVE);
        $reference=trim($reference);$notes=trim($notes);
        if(strlen($reference)<6||strlen($reference)>120||strlen($notes)>255)
            throw new DomainException('Physical receipt reference of 6–120 characters required.','prepaid_return_inspection_required',422);
        return Transaction::run(function()use($a,$id,$reference,$notes){
            $r=self::row($a,$id,true);
            Guard::branch($a,(int)$r['branch_id'],Capabilities::REVERSAL_APPROVE);
            if($r['status']!=='requested')
                throw new DomainException('Return is not awaiting physical inspection.','prepaid_return_state_invalid',409);
            if((int)$r['requested_by']===$a->employeeId)
                throw new DomainException('Return requester cannot confirm their own physical receipt.','maker_checker_required',409);
            // The reference records a real-world check, but is NOT a verified
            // bank refund, journal, or automatic inventory acceptance.
            Db::mustUpdate(Db::wpdb(),Db::table('prepaid_return_requests'),[
                'status'=>'received','inspection_reference'=>$reference,
                'inspection_notes'=>$notes?:null,'inspected_by'=>$a->employeeId,
                'inspected_at'=>Db::now()
            ],['id'=>$id,'company_id'=>$a->companyId]);
            Audit::add($a,'sales.return.inspect','prepaid_return_request',$id,['branch_id'=>(int)$r['branch_id'],'inspection_reference'=>$reference]);
            return ['id'=>$id,'status'=>'received','stock_posted'=>false,'refund_posted'=>false];
        });
    }

    /**
     * Approval authorizes a future separately verified refund but never
     * disburses money or creates a credit note in this phase.
     */
    public static function decide(Actor $a,int $id,bool $approve):array {
        Guard::cap($a,Capabilities::REVERSAL_APPROVE);
        return Transaction::run(function()use($a,$id,$approve){
            $r=self::row($a,$id,true);
            Guard::branch($a,(int)$r['branch_id'],Capabilities::REVERSAL_APPROVE);
            if($r['status']!=='received')
                throw new DomainException('Only physically inspected returns can be decided.','prepaid_return_state_invalid',409);
            if(in_array($a->employeeId,[(int)$r['requested_by'],(int)$r['inspected_by']],true))
                throw new DomainException('Return request, physical inspection and approval require independent actors.','maker_checker_required',409);
            if ($approve) self::requirePostedSource($a->companyId,(int)$r['branch_id'],(int)$r['order_id'],
                (int)$r['sale_id'],(string)$r['refund_amount']);
            $status=$approve?'refund_pending':'rejected';
            Db::mustUpdate(Db::wpdb(),Db::table('prepaid_return_requests'),[
                'status'=>$status,'decided_by'=>$a->employeeId,'decided_at'=>Db::now()
            ],['id'=>$id,'company_id'=>$a->companyId]);
            Audit::add($a,'sales.return.decision','prepaid_return_request',$id,[
                'branch_id'=>(int)$r['branch_id'],'approved'=>$approve,
                'refund_pending'=>$approve
            ]);
            return ['id'=>$id,'status'=>$status,'refund_posted'=>false,'credit_note_posted'=>false,'stock_posted'=>false];
        });
    }
}
