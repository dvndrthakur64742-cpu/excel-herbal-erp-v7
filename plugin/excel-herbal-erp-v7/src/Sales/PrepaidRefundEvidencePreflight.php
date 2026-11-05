<?php
namespace ExcelHerbal\ERP7\Sales;

use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Policy\PrepaidOrderRules as Money;

/**
 * Read-only and fail-closed reconciliation of original prepaid tenders against
 * independently reviewed refund *evidence*. It never authorises a payout,
 * statutory credit note, journal reversal, or return-to-saleable-stock.
 */
final class PrepaidRefundEvidencePreflight {
    private static function minor(mixed $value):?int {
        try { return Money::minor($value); }
        catch (DomainException $e) { return null; }
    }

    /** @return array<string,mixed> */
    public static function check(array $return, array $payments, array $evidence):array {
        $blockers=[];
        $add=static function(string $code) use (&$blockers):void { $blockers[$code]=true; };
        $company=(int)($return['company_id']??0);
        $branch=(int)($return['branch_id']??0);
        $order=(int)($return['order_id']??0);
        $returnId=(int)($return['id']??0);
        $expected=self::minor($return['refund_amount']??null);
        if (($return['status']??'')!=='refund_pending') $add('return_not_approved');
        if ($company<1||$branch<1||$order<1||$returnId<1) $add('return_scope_invalid');
        if ($expected===null||$expected<1) $add('return_amount_invalid');

        $originals=[];
        $originalTotal=0;
        foreach ($payments as $p) {
            $id=(int)($p['id']??0);
            if ($id<1||isset($originals[$id])) { $add('original_payment_duplicate_or_invalid'); continue; }
            $originals[$id]=$p;
            $amount=self::minor($p['amount']??null);
            if ($amount===null||$amount<1) $add('original_payment_amount_invalid');
            else $originalTotal+=$amount;
            if ((int)($p['company_id']??0)!==$company||
                (int)($p['branch_id']??0)!==$branch||
                (int)($p['order_id']??0)!==$order||
                (int)($p['payment_account_id']??0)<1) $add('original_payment_scope_invalid');
            if (($p['status']??'')!=='confirmed'||
                !in_array($p['method']??'', ['cash','upi'],true)) $add('original_payment_not_confirmed');
        }
        if (!$originals) $add('original_payments_missing');
        if ($expected===null||$originalTotal!==$expected) $add('original_payment_total_mismatch');

        $evidenced=[];
        $verified=0;
        $verifiedTotal=0;
        foreach ($evidence as $ev) {
            $originalId=(int)($ev['order_payment_id']??0);
            if ($originalId<1||!isset($originals[$originalId])) {
                $add('unexpected_refund_evidence'); continue;
            }
            if (isset($evidenced[$originalId])) {
                $add('duplicate_refund_evidence'); continue;
            }
            $evidenced[$originalId]=true;
            $p=$originals[$originalId];
            $amount=self::minor($ev['amount']??null);
            $paymentAmount=self::minor($p['amount']??null);
            if ($amount===null||$paymentAmount===null||$amount<1||$amount!==$paymentAmount)
                $add('refund_evidence_amount_mismatch');
            if ((int)($ev['company_id']??0)!==$company||
                (int)($ev['branch_id']??0)!==$branch||
                (int)($ev['return_id']??0)!==$returnId||
                (int)($ev['payment_account_id']??0)!==(int)($p['payment_account_id']??0)||
                ($ev['method']??'')!==($p['method']??'')) $add('refund_evidence_scope_mismatch');
            if (($ev['status']??'')!=='evidence_verified') {
                $add('refund_evidence_unverified'); continue;
            }
            $submitter=(int)($ev['submitted_by']??0);
            $reviewer=(int)($ev['verified_by']??0);
            if ($submitter<1||$reviewer<1||$submitter===$reviewer||
                strlen(trim((string)($ev['verification_reference']??'')))<6)
                $add('refund_evidence_independent_review_missing');
            else {
                $verified++;
                if ($amount!==null&&$paymentAmount!==null&&$amount===$paymentAmount)
                    $verifiedTotal+=$amount;
            }
        }
        if (count($evidenced)!==count($originals)) $add('refund_evidence_missing');
        if ($expected===null||$verifiedTotal!==$expected) $add('verified_evidence_total_mismatch');

        return [
            'evidence_complete'=>!$blockers,
            'expected_amount'=>$expected===null?null:Money::format($expected),
            'original_payment_count'=>count($originals),
            'verified_evidence_count'=>$verified,
            'verified_evidence_amount'=>Money::format($verifiedTotal),
            'blockers'=>array_keys($blockers),
            'manual_evidence_only'=>true,
            'refund_disbursed'=>false,
            'credit_note_posted'=>false,
            'stock_posted'=>false,
        ];
    }
}
