<?php
require_once __DIR__.'/../src/Domain/DomainException.php';
require_once __DIR__.'/../src/Policy/PrepaidOrderRules.php';
require_once __DIR__.'/../src/Sales/PrepaidRefundEvidencePreflight.php';

use ExcelHerbal\ERP7\Sales\PrepaidRefundEvidencePreflight as R;
function expectEvidence(bool $ok,string $name):void {
    if (!$ok) {fwrite(STDERR,"FAIL $name\n");exit(1);}
    echo "PASS $name\n";
}
function blockedBy(array $result,string $key):bool {
    return $result['evidence_complete']===false && in_array($key,$result['blockers'],true);
}
$return=['id'=>51,'company_id'=>1,'branch_id'=>2,'order_id'=>80,'status'=>'refund_pending','refund_amount'=>'150.00'];
$cash=['id'=>100,'company_id'=>1,'branch_id'=>2,'order_id'=>80,'payment_account_id'=>8,'method'=>'cash','status'=>'confirmed','amount'=>'100.00'];
$upi=['id'=>101,'company_id'=>1,'branch_id'=>2,'order_id'=>80,'payment_account_id'=>9,'method'=>'upi','status'=>'confirmed','amount'=>'50.00'];
$cashProof=['order_payment_id'=>100,'company_id'=>1,'branch_id'=>2,'return_id'=>51,'payment_account_id'=>8,'method'=>'cash','amount'=>'100.00','status'=>'evidence_verified','submitted_by'=>11,'verified_by'=>12,'verification_reference'=>'CASH-UAT-112'];
$upiProof=['order_payment_id'=>101,'company_id'=>1,'branch_id'=>2,'return_id'=>51,'payment_account_id'=>9,'method'=>'upi','amount'=>'50.00','status'=>'evidence_verified','submitted_by'=>11,'verified_by'=>13,'verification_reference'=>'UPI-UAT-113'];
$good=R::check($return,[$cash,$upi],[$cashProof,$upiProof]);
expectEvidence($good['evidence_complete']===true&&$good['verified_evidence_amount']==='150.00'&&$good['verified_evidence_count']===2,'complete Cash/UPI original payment evidence');
expectEvidence($good['refund_disbursed']===false&&$good['credit_note_posted']===false&&$good['stock_posted']===false,'complete evidence never implies financial posting');
expectEvidence(blockedBy(R::check($return,[$cash,$upi],[$cashProof]),'refund_evidence_missing'),'missing UPI proof blocks completeness');
expectEvidence(blockedBy(R::check($return,[$cash,$upi],[$cashProof,$cashProof,$upiProof]),'duplicate_refund_evidence'),'duplicate proof blocks completeness');
expectEvidence(blockedBy(R::check($return,[$cash,$upi],[$cashProof,array_replace($upiProof,['status'=>'evidence_submitted'])]),'refund_evidence_unverified'),'unverified evidence blocks completeness');
expectEvidence(blockedBy(R::check($return,[$cash,$upi],[$cashProof,array_replace($upiProof,['amount'=>'49.99'])]),'refund_evidence_amount_mismatch'),'one paisa short blocks completeness');
expectEvidence(blockedBy(R::check($return,[$cash,$upi],[$cashProof,array_replace($upiProof,['amount'=>'50.01'])]),'refund_evidence_amount_mismatch'),'one paisa over blocks completeness');
expectEvidence(blockedBy(R::check($return,[$cash,$upi],[$cashProof,array_replace($upiProof,['branch_id'=>3])]),'refund_evidence_scope_mismatch'),'cross-branch evidence blocks completeness');
expectEvidence(blockedBy(R::check($return,[$cash,$upi],[$cashProof,array_replace($upiProof,['payment_account_id'=>8])]),'refund_evidence_scope_mismatch'),'wrong payment account blocks completeness');
expectEvidence(blockedBy(R::check($return,[$cash,$upi],[$cashProof,array_replace($upiProof,['verified_by'=>11])]),'refund_evidence_independent_review_missing'),'self review blocks completeness');
expectEvidence(blockedBy(R::check($return,[$cash,$upi],[$cashProof,array_replace($upiProof,['verification_reference'=>'bad'])]),'refund_evidence_independent_review_missing'),'missing independent reference blocks completeness');
expectEvidence(blockedBy(R::check(array_replace($return,['status'=>'received']),[$cash,$upi],[$cashProof,$upiProof]),'return_not_approved'),'not independently approved return blocks completeness');
expectEvidence(blockedBy(R::check($return,[$cash,array_replace($upi,['status'=>'pending'])],[$cashProof,$upiProof]),'original_payment_not_confirmed'),'unconfirmed original UPI blocks completeness');
expectEvidence(blockedBy(R::check($return,[$cash,array_replace($upi,['amount'=>'49.99'])],[$cashProof,$upiProof]),'original_payment_total_mismatch'),'original tender total mismatch blocks completeness');
expectEvidence(blockedBy(R::check($return,[$cash,$upi],[$cashProof,$upiProof,array_replace($upiProof,['order_payment_id'=>777])]),'unexpected_refund_evidence'),'unlinked proof blocks completeness');
expectEvidence(blockedBy(R::check($return,[],[]),'original_payments_missing'),'missing originals fail closed');
expectEvidence(blockedBy(R::check(array_replace($return,['refund_amount'=>'1e5']),[$cash,$upi],[$cashProof,$upiProof]),'return_amount_invalid'),'invalid money fails closed');
echo "PASSED 17 prepaid refund evidence preflight assertions (read-only; NO payout)\n";
