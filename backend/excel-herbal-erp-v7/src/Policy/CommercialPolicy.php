<?php
namespace ExcelHerbal\ERP7\Policy;
use ExcelHerbal\ERP7\Domain\DomainException;

final class CommercialPolicy {
    private const FIELDS=['mrp','sale_price','ho_amount','bm_profit','salary_fund','office_expense','points','purchase_cost'];

    public static function values(array $data): array {
        $values=[];
        foreach(self::FIELDS as $field){
            $value=(float)($data[$field]??0);
            if(!is_finite($value)||$value<0)throw new DomainException('Commercial values must be finite and non-negative.','commercial_value_invalid',422);
            $values[$field]=$value;
        }
        self::assert($values);
        return $values;
    }

    public static function assert(array $data): void {
        $values=[];
        foreach(self::FIELDS as $field){
            if(!array_key_exists($field,$data))throw new DomainException('Commercial revision is incomplete.','commercial_missing',409);
            $value=(float)$data[$field];
            if(!is_finite($value)||$value<0)throw new DomainException('Commercial values must be finite and non-negative.','commercial_value_invalid',422);
            $values[$field]=$value;
        }
        if($values['mrp']<=0||$values['sale_price']<=0)throw new DomainException('MRP and Sale Price must be greater than zero.','commercial_value_invalid',422);
        if($values['sale_price']>$values['mrp']+.005)throw new DomainException('Sale Price cannot exceed MRP.','commercial_sale_price_invalid',422);
        $distribution=round($values['ho_amount']+$values['bm_profit']+$values['salary_fund']+$values['office_expense'],2);
        if(abs($distribution-round($values['sale_price'],2))>.01)throw new DomainException('HO Amount + BM Profit + Salary Fund + Office Expense must equal Sale Price.','commercial_distribution_invalid',422);
    }
}
