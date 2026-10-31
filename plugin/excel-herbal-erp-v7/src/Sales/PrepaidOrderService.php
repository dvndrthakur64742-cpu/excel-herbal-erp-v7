<?php
namespace ExcelHerbal\ERP7\Sales;

use ExcelHerbal\ERP7\Core\NumberSeries;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Finance\AccountingService;
use ExcelHerbal\ERP7\Finance\BranchDayGuard;
use ExcelHerbal\ERP7\Inventory\StockService;
use ExcelHerbal\ERP7\Policy\DistributorVolumePricing;
use ExcelHerbal\ERP7\Policy\PrepaidOrderRules as Money;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;

/**
 * Order -> optional independent discount review -> confirmed cash / manually
 * verified UPI -> atomic invoice, stock, ledger. NEVER posts on order creation.
 */
final class PrepaidOrderService {
    private static function row(Actor $a,int $id,bool $lock=false):array {
        $db=Db::wpdb();$t=Db::table('prepaid_sales_orders');
        $r=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d".($lock?' FOR UPDATE':''),$id,$a->companyId),ARRAY_A);
        if(!$r)throw new DomainException('Sales order not found.','sales_order_not_found',404);
        return $r;
    }
    private static function lines(int $id):array {
        $db=Db::wpdb();
        return (array)$db->get_results($db->prepare('SELECT * FROM '.Db::table('prepaid_sales_order_lines').' WHERE order_id=%d ORDER BY id',$id),ARRAY_A);
    }
    private static function payments(Actor $a,int $id):array {
        $db=Db::wpdb();
        return (array)$db->get_results($db->prepare('SELECT * FROM '.Db::table('prepaid_sales_order_payments').' WHERE company_id=%d AND order_id=%d ORDER BY id',$a->companyId,$id),ARRAY_A);
    }
    private static function percentagePolicy(Actor $a):?string {
        $db=Db::wpdb();
        $raw=$db->get_var($db->prepare('SELECT setting_value FROM '.Db::table('settings').' WHERE company_id=%d AND setting_key=%s',$a->companyId,'sales_discount_ho_threshold_percent'));
        if($raw===null)return null;
        $parsed=json_decode((string)$raw,true);
        return is_string($parsed)?$parsed:null;
    }
    private static function distributorSlabs(Actor $a,int $product):array {
        $db=Db::wpdb();$table=Db::table('distributor_price_slabs');$at=Db::now();
        return (array)$db->get_results($db->prepare(
            "SELECT id,min_qty,max_qty,unit_price FROM {$table} WHERE company_id=%d AND product_id=%d AND effective_from=(SELECT MAX(effective_from) FROM {$table} WHERE company_id=%d AND product_id=%d AND effective_from<=%s) ORDER BY min_qty",
            $a->companyId,$product,$a->companyId,$product,$at
        ),ARRAY_A);
    }
    public static function setDistributorSlabs(Actor $a,int $product,array $slabs):array {
        Guard::cap($a,Capabilities::PRODUCT_MANAGE);
        Guard::cap($a,Capabilities::ACCESS_MANAGE);
        StockService::product($a,$product);
        if(!$slabs||count($slabs)>100)throw new DomainException('Supply 1 to 100 distributor price slabs.','price_slabs_invalid',422);
        $checks=[];$records=[];
        foreach($slabs as $i=>$s){
            if(!is_array($s))throw new DomainException('Invalid price slab.','price_slab_invalid',422);
            $min=filter_var($s['min_qty']??null,FILTER_VALIDATE_INT,['options'=>['min_range'=>1,'max_range'=>1000000]]);
            $max=($s['max_qty']??null)===null?null:filter_var($s['max_qty'],FILTER_VALIDATE_INT,['options'=>['min_range'=>1,'max_range'=>1000000]]);
            if($min===false||($max===false)||($max!==null&&$max<$min))throw new DomainException('Invalid distributor quantity range.','price_slab_invalid',422);
            $price=Money::minor($s['unit_price']??null);
            if($price<1)throw new DomainException('Distributor unit price must be positive.','price_slab_invalid',422);
            $records[]=['min_qty'=>(int)$min,'max_qty'=>$max===null?null:(int)$max,'unit_price'=>Money::format($price)];
            $checks[]=['id'=>$i+1,'min_qty'=>(int)$min,'max_qty'=>$max===null?null:(int)$max,'unit_price'=>Money::format($price)];
        }
        // Full coverage from 1, no gaps, no overlaps; enforces an open-ended last slab.
        usort($records,static fn($x,$y)=>$x['min_qty']<=>$y['min_qty']);
        $expected=1;
        foreach($records as $i=>$s){
            if($expected===null||$s['min_qty']!==$expected)throw new DomainException('Distributor price slabs must be contiguous starting at quantity 1.','price_slabs_gap',422);
            $expected=$s['max_qty']===null?null:$s['max_qty']+1;
            if($expected===null&&$i<count($records)-1)throw new DomainException('Unbounded slab must be the final slab.','price_slabs_overlap',422);
        }
        if($expected!==null)throw new DomainException('Final distributor slab must have no maximum quantity.','price_slabs_gap',422);
        return Transaction::run(function()use($a,$product,$records){
            $db=Db::wpdb();$at=Db::now();$t=Db::table('distributor_price_slabs');
            foreach($records as $s)Db::mustInsert($db,$t,['company_id'=>$a->companyId,'product_id'=>$product,'effective_from'=>$at]+$s+['created_by'=>$a->employeeId,'created_at'=>$at],'Distributor price list changed at the same time.','price_slab_conflict');
            Audit::add($a,'distributor.pricing.update','product',$product,['slabs'=>$records,'effective_from'=>$at]);
            return ['product_id'=>$product,'effective_from'=>$at,'slabs'=>$records];
        });
    }
    public static function quote(Actor $a,int $product,int $quantity):array {
        Guard::any($a,[Capabilities::SALES_VIEW,Capabilities::SALES_CREATE]);
        StockService::product($a,$product);
        return DistributorVolumePricing::quote($quantity,self::distributorSlabs($a,$product));
    }
    public static function discountPolicy(Actor $a,?string $threshold=null):array {
        if($threshold===null){Guard::any($a,[Capabilities::SALES_VIEW,Capabilities::SALES_CREATE,Capabilities::SALES_DISCOUNT_HO_APPROVE]);$current=self::percentagePolicy($a);return ['ho_threshold_percent'=>$current,'configured'=>$current!==null];}
        Guard::cap($a,Capabilities::SALES_DISCOUNT_HO_APPROVE);
        $basisPoints=Money::minor($threshold);
        if($basisPoints>10000)throw new DomainException('Head Office discount cutoff must be 0–100%.','discount_policy_invalid',422);
        return Transaction::run(function()use($a,$threshold){
            $db=Db::wpdb();$t=Db::table('settings');$key='sales_discount_ho_threshold_percent';
            $row=$db->get_row($db->prepare("SELECT id,setting_value FROM {$t} WHERE company_id=%d AND setting_key=%s FOR UPDATE",$a->companyId,$key),ARRAY_A);
            if($row)Db::mustUpdate($db,$t,['setting_value'=>wp_json_encode($threshold),'updated_by'=>$a->employeeId,'updated_at'=>Db::now()],['id'=>(int)$row['id']]);
            else Db::mustInsert($db,$t,['company_id'=>$a->companyId,'setting_key'=>$key,'setting_value'=>wp_json_encode($threshold),'updated_by'=>$a->employeeId,'updated_at'=>Db::now()]);
            Audit::add($a,'sales.discount.policy','setting',$key,['old'=>$row['setting_value']??null,'new'=>$threshold]);
            return ['ho_threshold_percent'=>$threshold,'configured'=>true];
        });
    }
    public static function create(Actor $a,int $branch,string $channel,?int $customer,array $lines,string $discount='0.00',string $reason=''):array {
        Guard::branch($a,$branch,Capabilities::SALES_CREATE);BranchDayGuard::assertOpen($a,$branch,Db::today());
        if(!in_array($channel,['b2c','b2b','distributor'],true))throw new DomainException('Unknown sales channel.','sales_channel_invalid',422);
        if(!$lines||count($lines)>100)throw new DomainException('Supply 1–100 sale lines.','sales_lines_invalid',422);
        if($channel!=='b2c'&&(!$customer||$customer<1))throw new DomainException('B2B and distributor orders need a registered customer.','customer_required',422);
        if($customer){
            $db=Db::wpdb();$ok=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('parties')." WHERE id=%d AND company_id=%d AND branch_id=%d AND type='customer' AND status='active'",$customer,$a->companyId,$branch));
            if(!$ok)throw new DomainException('Active customer not found in selected branch.','customer_invalid',422);
        }
        $gross=0;$prepared=[];$seen=[];
        foreach($lines as $line){
            if(!is_array($line))throw new DomainException('Invalid sales line.','sales_line_invalid',422);
            $product=(int)($line['product_id']??0);$batch=(int)($line['batch_id']??0);
            $raw=(string)($line['quantity']??'');
            if(!preg_match('/^[1-9][0-9]{0,5}(?:\.[0-9]{1,3})?$/',$raw))throw new DomainException('Quantity must be positive with at most 3 decimals.','quantity_invalid',422);
            $quantity=(float)$raw;
            if($product<1||isset($seen[$product.'|'.$batch]))throw new DomainException('Duplicate/invalid product and batch.','sales_line_invalid',422);
            $seen[$product.'|'.$batch]=true;
            $p=StockService::product($a,$product);StockService::validateBatch($a,$p,$batch?:null,true);
            $commercial=StockService::commercial($a,$product);
            $slab=null;$unit=Money::minor((string)$commercial['sale_price']);
            if($channel==='distributor'){
                if(!ctype_digit($raw))throw new DomainException('Distributor slabs require whole PCS.','quantity_invalid',422);
                $quote=DistributorVolumePricing::quote((int)$raw,self::distributorSlabs($a,$product));
                $unit=Money::minor($quote['unit_price']);$slab=(int)$quote['slab_id'];
            }
            if($unit<1)throw new DomainException('Sale price must be positive.','sales_price_invalid',422);
            $lineGross=(int)round($unit*$quantity);
            if($lineGross<1)throw new DomainException('Sale line amount must be positive.','sales_amount_invalid',422);
            $gross+=$lineGross;
            if($gross>999999999999)throw new DomainException('Order amount is out of range.','sales_amount_invalid',422);
            $prepared[]=['product_id'=>$product,'batch_id'=>$batch?:null,'quantity'=>$quantity,'list_unit_price'=>Money::format($unit),'line_total'=>Money::format($lineGross),'price_slab_id'=>$slab,'points_snapshot'=>(float)$commercial['points'],'salary_fund_snapshot'=>(float)$commercial['salary_fund']];
        }
        $discountMinor=Money::minor($discount);$net=$gross-$discountMinor;
        if($net<=0)throw new DomainException('Discount must be below gross amount.','discount_invalid',422);
        if($discountMinor>0&&strlen(trim($reason))<5)throw new DomainException('A reason is required for discounts.','discount_reason_required',422);
        $status=$discountMinor?'discount_pending':'approved';
        return Transaction::run(function()use($a,$branch,$channel,$customer,$gross,$discountMinor,$net,$reason,$status,$prepared){
            $db=Db::wpdb();$no=NumberSeries::next($a->companyId,'prepaid_sales_order','SO-');
            Db::mustInsert($db,Db::table('prepaid_sales_orders'),['company_id'=>$a->companyId,'branch_id'=>$branch,'customer_id'=>$customer,'channel'=>$channel,'order_no'=>$no,'status'=>$status,'gross_amount'=>Money::format($gross),'discount_amount'=>Money::format($discountMinor),'net_amount'=>Money::format($net),'discount_reason'=>$discountMinor?trim($reason):null,'created_by'=>$a->employeeId,'created_at'=>Db::now()]);
            $id=(int)$db->insert_id;
            foreach($prepared as $line)Db::mustInsert($db,Db::table('prepaid_sales_order_lines'),['order_id'=>$id]+$line);
            Audit::add($a,'sales.order.create','prepaid_sales_order',$id,['branch_id'=>$branch,'channel'=>$channel,'gross_amount'=>Money::format($gross),'discount_amount'=>Money::format($discountMinor),'status'=>$status]);
            return ['id'=>$id,'order_no'=>$no,'channel'=>$channel,'status'=>$status,'gross_amount'=>Money::format($gross),'net_amount'=>Money::format($net)];
        });
    }
    /** Branch-scoped, compact order queue for seller, manager, cashier and finance. */
    public static function list(Actor $a,int $branch,string $status=''):array {
        Guard::any($a,[Capabilities::SALES_VIEW,Capabilities::SALES_CREATE,Capabilities::RECEIPT_CREATE,Capabilities::BANK_RECONCILE,Capabilities::SALES_DISCOUNT_APPROVE,Capabilities::SALES_DISCOUNT_HO_APPROVE]);
        if($branch<1||!$a->hasBranch($branch))throw new DomainException('Branch is outside effective authority.','branch_forbidden',403);
        if($status!==''&&!in_array($status,['approved','discount_pending','posted'],true))throw new DomainException('Invalid sales order status.','sales_order_status_invalid',422);
        $db=Db::wpdb();$params=[$a->companyId,$branch];$where="company_id=%d AND branch_id=%d";
        if($status!==''){$where.=" AND status=%s";$params[]=$status;}
        return (array)$db->get_results($db->prepare(
            "SELECT id,order_no,channel,status,customer_id,gross_amount,discount_amount,net_amount,sale_id,created_by,created_at FROM ".Db::table('prepaid_sales_orders')." WHERE {$where} ORDER BY id DESC LIMIT 100",...$params
        ),ARRAY_A);
    }
    public static function detail(Actor $a,int $id):array {
        Guard::any($a,[Capabilities::SALES_VIEW,Capabilities::SALES_CREATE,Capabilities::RECEIPT_CREATE]);
        $o=self::row($a,$id);if(!$a->hasBranch((int)$o['branch_id']))throw new DomainException('Order branch outside authority.','branch_forbidden',403);
        $payments=self::payments($a,$id);
        if(!$a->can(Capabilities::RECEIPT_CREATE)&&!$a->can(Capabilities::BANK_RECONCILE))foreach($payments as &$payment){unset($payment['reference'],$payment['bank_evidence_ref'],$payment['verified_by']);}unset($payment);
        return ['order'=>$o,'lines'=>self::lines($id),'payments'=>$payments];
    }
    public static function approveDiscount(Actor $a,int $id):array {
        return Transaction::run(function()use($a,$id){
            $o=self::row($a,$id,true);
            if($o['status']!=='discount_pending')throw new DomainException('Order is not awaiting discount review.','discount_state_invalid',409);
            if((int)$o['created_by']===$a->employeeId)throw new DomainException('A different employee must approve the discount.','maker_checker_required',409);
            $scope=Money::discountAuthority(Money::minor((string)$o['gross_amount']),Money::minor((string)$o['discount_amount']),self::percentagePolicy($a));
            if($scope==='head_office')Guard::cap($a,Capabilities::SALES_DISCOUNT_HO_APPROVE);
            else Guard::branch($a,(int)$o['branch_id'],Capabilities::SALES_DISCOUNT_APPROVE);
            Db::mustUpdate(Db::wpdb(),Db::table('prepaid_sales_orders'),['status'=>'approved','discount_approved_by'=>$a->employeeId,'discount_approved_at'=>Db::now()],['id'=>$id,'company_id'=>$a->companyId]);
            Audit::add($a,'sales.discount.approve','prepaid_sales_order',$id,['branch_id'=>(int)$o['branch_id'],'discount_amount'=>$o['discount_amount'],'scope'=>$scope]);
            return ['id'=>$id,'status'=>'approved','approval_scope'=>$scope];
        });
    }
    public static function collect(Actor $a,int $id,int $account,string $amount,string $method,string $reference=''):array {
        $method=strtolower(trim($method));if(!in_array($method,['cash','upi'],true))throw new DomainException('Only Cash or UPI collection accepted.','payment_mode_invalid',422);
        $minor=Money::minor($amount);if($minor<1)throw new DomainException('Payment amount must be positive.','payment_amount_invalid',422);
        $ref=trim($reference);
        if($method==='upi'&&(strlen($ref)<6||strlen($ref)>120))throw new DomainException('UPI reference must be 6–120 characters.','upi_reference_required',422);
        if($method==='cash'&&strlen($ref)>120)throw new DomainException('Cash reference is too long.','payment_reference_invalid',422);
        return Transaction::run(function()use($a,$id,$account,$minor,$method,$ref){
            $o=self::row($a,$id,true);Guard::branch($a,(int)$o['branch_id'],Capabilities::RECEIPT_CREATE);
            if($o['status']!=='approved')throw new DomainException('Discount approval is required before collection.','sales_order_not_approved',409);
            $accountRow=AccountingService::paymentAccount($a,$account);
            if(strtolower((string)$accountRow['subtype'])!==$method)throw new DomainException('Collection account must match Cash or UPI payment method.','payment_account_invalid',422);
            $existing=self::payments($a,$id);$reserved=0;
            foreach($existing as $p)if(in_array($p['status'],['confirmed','pending'],true))$reserved+=Money::minor((string)$p['amount']);
            if($reserved+$minor>Money::minor((string)$o['net_amount']))throw new DomainException('Collections may not exceed the order net amount.','payment_overpaid',409);
            $status=$method==='cash'?'confirmed':'pending';
            $t=Db::table('prepaid_sales_order_payments');
            Db::mustInsert(Db::wpdb(),$t,['company_id'=>$a->companyId,'branch_id'=>(int)$o['branch_id'],'order_id'=>$id,'payment_account_id'=>$account,'method'=>$method,'amount'=>Money::format($minor),'reference'=>$ref?:null,'status'=>$status,'received_by'=>$a->employeeId,'verified_by'=>$method==='cash'?$a->employeeId:null,'verified_at'=>$method==='cash'?Db::now():null,'created_at'=>Db::now()],'Payment reference already recorded.','payment_reference_duplicate');
            $pid=(int)Db::wpdb()->insert_id;
            Audit::add($a,'sales.payment.record','prepaid_sales_order_payment',$pid,['branch_id'=>(int)$o['branch_id'],'order_id'=>$id,'method'=>$method,'amount'=>Money::format($minor),'status'=>$status]);
            return ['id'=>$pid,'order_id'=>$id,'status'=>$status,'amount'=>Money::format($minor),'method'=>$method];
        });
    }
    public static function verifyUpi(Actor $a,int $paymentId,string $bankEvidence):array {
        $bankEvidence=trim($bankEvidence);
        if(strlen($bankEvidence)<6||strlen($bankEvidence)>120)throw new DomainException('Verified bank evidence reference is required.','upi_bank_evidence_required',422);
        Guard::cap($a,Capabilities::BANK_RECONCILE);
        return Transaction::run(function()use($a,$paymentId,$bankEvidence){
            $db=Db::wpdb();$t=Db::table('prepaid_sales_order_payments');
            $p=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d",$paymentId,$a->companyId),ARRAY_A);
            if(!$p||$p['method']!=='upi')throw new DomainException('UPI receipt not found.','upi_payment_not_found',404);
            $o=self::row($a,(int)$p['order_id'],true);
            // Re-read while holding both locks so simultaneous finance reviews cannot
            // confirm the same UPI receipt twice using stale pending state.
            $p=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d FOR UPDATE",$paymentId,$a->companyId),ARRAY_A);
            Guard::branch($a,(int)$o['branch_id'],Capabilities::BANK_RECONCILE);
            if($o['status']!=='approved'||!$p||$p['status']!=='pending')throw new DomainException('UPI payment is not awaiting verification.','upi_payment_state_invalid',409);
            if((int)$p['received_by']===$a->employeeId||((int)$o['created_by']===$a->employeeId))throw new DomainException('UPI requires an independent bank verifier.','maker_checker_required',409);
            AccountingService::bankAccount($a,(int)$p['payment_account_id']);
            Db::mustUpdate($db,$t,['status'=>'confirmed','bank_evidence_ref'=>$bankEvidence,'verified_by'=>$a->employeeId,'verified_at'=>Db::now()],['id'=>$paymentId,'company_id'=>$a->companyId]);
            Audit::add($a,'sales.upi.verify','prepaid_sales_order_payment',$paymentId,['branch_id'=>(int)$o['branch_id'],'order_id'=>(int)$o['id'],'bank_evidence_ref'=>$bankEvidence]);
            return ['id'=>$paymentId,'order_id'=>(int)$o['id'],'status'=>'confirmed'];
        });
    }
    public static function post(Actor $a,int $id):array {
        return Transaction::run(function()use($a,$id){
            $o=self::row($a,$id,true);$branch=(int)$o['branch_id'];
            Guard::branch($a,$branch,Capabilities::SALES_CREATE);
            if($o['status']==='posted'&&(int)$o['sale_id']>0)return ['id'=>$id,'sale_id'=>(int)$o['sale_id'],'status'=>'posted','idempotent'=>true];
            if($o['status']!=='approved')throw new DomainException('Discount approval is required before invoice.','sales_order_not_approved',409);
            BranchDayGuard::assertOpen($a,$branch,Db::today());
            $payments=self::payments($a,$id);
            foreach($payments as $p)if($p['status']==='pending')throw new DomainException('UPI verification pending.','upi_verification_required',409);
            $net=Money::minor((string)$o['net_amount']);Money::requireCovered($net,$payments);
            $lines=self::lines($id);if(!$lines)throw new DomainException('Order has no lines.','sales_lines_invalid',409);
            $db=Db::wpdb();$saleNo=NumberSeries::next($a->companyId,'counter_sale','CS-');
            $h=Db::table('counter_sales');
            Db::mustInsert($db,$h,['company_id'=>$a->companyId,'branch_id'=>$branch,'customer_id'=>$o['customer_id'],'sale_no'=>$saleNo,'sale_date'=>Db::now(),'status'=>'posted','gross_amount'=>Money::format($net),'paid_amount'=>Money::format($net),'outstanding_amount'=>'0.00','payment_account_id'=>count($payments)===1?(int)$payments[0]['payment_account_id']:null,'created_by'=>$a->employeeId,'created_at'=>Db::now()]);
            $saleId=(int)$db->insert_id;$gross=Money::minor((string)$o['gross_amount']);$discount=Money::minor((string)$o['discount_amount']);
            $remainingNet=$net;$cogs=0;
            foreach($lines as $i=>$line){
                $original=Money::minor((string)$line['line_total']);
                $effective=$i===count($lines)-1?$remainingNet:intdiv($original*$net,$gross);$remainingNet-=$effective;
                $qty=(float)$line['quantity'];$pid=(int)$line['product_id'];$batch=$line['batch_id']===null?null:(int)$line['batch_id'];
                $cost=StockService::cost($a,$branch,$pid,$batch,null);
                $cogs+=(int)round($cost*$qty*100);
                Db::mustInsert($db,Db::table('counter_sale_lines'),['sale_id'=>$saleId,'product_id'=>$pid,'batch_id'=>$batch,'quantity'=>$qty,'unit_price'=>Money::format((int)round($effective/$qty)),'line_total'=>Money::format($effective),'points_snapshot'=>$line['points_snapshot'],'salary_fund_snapshot'=>$line['salary_fund_snapshot'],'purchase_cost_snapshot'=>$cost]);
                StockService::move($a,$branch,$pid,$batch,null,'OUT',$qty,$cost,'counter_sale',$saleId);
            }
            $journal=[];
            foreach($payments as $p)if($p['status']==='confirmed')$journal[]=['account_id'=>(int)$p['payment_account_id'],'debit'=>(float)$p['amount']];
            $sales=AccountingService::accountByCode($a,'SALES');$journal[]=['account_id'=>(int)$sales['id'],'credit'=>(float)Money::format($net)];
            if($cogs>0){$ca=AccountingService::accountByCode($a,'COGS');$ia=AccountingService::accountByCode($a,'INVENTORY');$journal[]=['account_id'=>(int)$ca['id'],'debit'=>(float)Money::format($cogs)];$journal[]=['account_id'=>(int)$ia['id'],'credit'=>(float)Money::format($cogs)];}
            $journalId=AccountingService::post($a,$branch,'counter_sale',$saleId,Db::businessNow(),$journal,'Prepaid '.$o['channel'].' order '.$o['order_no']);
            Db::mustUpdate($db,$h,['journal_entry_id'=>$journalId],['id'=>$saleId]);
            Db::mustUpdate($db,Db::table('prepaid_sales_orders'),['status'=>'posted','sale_id'=>$saleId,'posted_by'=>$a->employeeId,'posted_at'=>Db::now()],['id'=>$id,'company_id'=>$a->companyId]);
            Audit::add($a,'sales.order.post','prepaid_sales_order',$id,['branch_id'=>$branch,'sale_id'=>$saleId,'journal_entry_id'=>$journalId,'channel'=>$o['channel'],'net_amount'=>Money::format($net)]);
            return ['id'=>$id,'sale_id'=>$saleId,'sale_no'=>$saleNo,'status'=>'posted','paid_amount'=>Money::format($net),'outstanding_amount'=>'0.00'];
        });
    }
}
