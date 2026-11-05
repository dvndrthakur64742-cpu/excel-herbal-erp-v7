<?php
namespace ExcelHerbal\ERP7\Policy;

use ExcelHerbal\ERP7\Domain\DomainException;

/** Exact decimal money and fail-closed sales posting/approval gates. */
final class PrepaidOrderRules {
    public static function minor(mixed $value):int {
        if(!is_string($value)&&!is_int($value))throw new DomainException('Money must be a decimal string.','money_invalid',422);
        $text=(string)$value;
        if(!preg_match('/^(0|[1-9][0-9]{0,9})(?:\.([0-9]{1,2}))?$/',$text,$m))throw new DomainException('Money must be non-negative with at most two decimal places.','money_invalid',422);
        return ((int)$m[1])*100+(int)str_pad($m[2]??'',2,'0');
    }
    public static function format(int $paise):string{
        if($paise<0)throw new DomainException('Negative money cannot be posted.','money_invalid',422);
        return intdiv($paise,100).'.'.str_pad((string)($paise%100),2,'0',STR_PAD_LEFT);
    }
    public static function requireCovered(int $expected,array $payments):void {
        if($expected<=0)throw new DomainException('Invoice amount must be positive.','order_amount_invalid',422);
        $paid=0;
        foreach($payments as $p){
            if(($p['status']??'')!=='confirmed')continue;
            if(!in_array($p['method']??'', ['cash','upi'],true))throw new DomainException('Only Cash and verified UPI can settle an invoice.','payment_mode_invalid',409);
            $paid+=self::minor($p['amount']??null);
            if($paid>$expected)throw new DomainException('Confirmed receipts exceed the order amount.','payment_overpaid',409);
        }
        if($paid!==$expected)throw new DomainException('100% confirmed Cash/UPI required before invoice and stock posting.','full_prepayment_required',409);
    }
    /** @return 'none'|'branch_manager'|'head_office' */
    public static function discountAuthority(int $gross,int $discount,?string $hoThresholdPercent):string {
        if($gross<1||$discount<0||$discount>=$gross)throw new DomainException('Invalid order discount.','discount_invalid',422);
        if($discount===0)return 'none';
        // No numeric policy was approved yet: discount remains pending until configured.
        if($hoThresholdPercent===null)throw new DomainException('Head Office discount threshold must be configured before discounts can be approved.','discount_policy_unconfigured',409);
        $threshold=self::minor($hoThresholdPercent); // integer basis points: e.g. 10.00 => 1000
        if($threshold>10000)throw new DomainException('Discount threshold must be between 0 and 100%.','discount_policy_invalid',422);
        return ($discount*10000 > $gross*$threshold)?'head_office':'branch_manager';
    }
}
