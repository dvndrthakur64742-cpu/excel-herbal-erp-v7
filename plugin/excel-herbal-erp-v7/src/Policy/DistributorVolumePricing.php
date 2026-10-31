<?php
namespace ExcelHerbal\ERP7\Policy;

use ExcelHerbal\ERP7\Domain\DomainException;

/**
 * Volume pricing calculation is pure and does NOT create invoices or payments.
 * An effective-dated price-list resolver supplies the validated per-product
 * slabs, and posting remains blocked until server-side full-payment clearance.
 */
final class DistributorVolumePricing {
    /** @return array{quantity:int,unit_price:string,line_total:string,slab_id:int} */
    public static function quote(int $quantity,array $slabs):array {
        if($quantity<1||$quantity>1000000)throw new DomainException('Product quantity must be between 1 and 1,000,000 whole PCS.','quantity_invalid',422);
        if(!$slabs)throw new DomainException('Distributor price list has no slabs.','price_slabs_missing',409);
        $rows=[];
        foreach($slabs as $s){
            if(!is_array($s))throw new DomainException('Invalid distributor slab.','price_slab_invalid',422);
            $min=self::whole($s['min_qty']??null);
            $max=($s['max_qty']??null)===null?null:self::whole($s['max_qty']);
            $id=self::whole($s['id']??null);
            $price=self::minor($s['unit_price']??null);
            if($min===null||$min<1||$id===null||$id<1||($max!==null&&$max<$min)||$price===null){
                throw new DomainException('Distributor price slab has invalid boundaries or price.','price_slab_invalid',422);
            }
            $rows[]=['id'=>$id,'min'=>$min,'max'=>$max,'minor'=>$price];
        }
        usort($rows,static fn($a,$b)=>$a['min']<=>$b['min']);
        $selected=null;$prevMax=0;
        foreach($rows as $i=>$row){
            if($prevMax===null||$row['min']<=$prevMax)throw new DomainException('Distributor quantity slabs overlap.','price_slabs_overlap',409);
            if($row['max']===null&&$i!==count($rows)-1)throw new DomainException('Unbounded price slab must be last.','price_slabs_overlap',409);
            if($quantity>=$row['min']&&($row['max']===null||$quantity<=$row['max']))$selected=$row;
            $prevMax=$row['max'];
        }
        if($selected===null)throw new DomainException('No distributor price slab covers the order quantity.','price_slab_not_found',409);
        $total=$selected['minor']*$quantity;
        if($total>PHP_INT_MAX||$total<0)throw new DomainException('Distributor line total is out of range.','price_total_invalid',422);
        return ['quantity'=>$quantity,'unit_price'=>self::display($selected['minor']),'line_total'=>self::display($total),'slab_id'=>$selected['id']];
    }

    private static function whole(mixed $value):?int {
        if(!is_int($value)&&!(is_string($value)&&ctype_digit($value)))return null;
        $raw=(string)$value;
        if(strlen($raw)>12)return null;
        return (int)$raw;
    }
    private static function minor(mixed $value):?int {
        if(!is_string($value)&&!is_int($value))return null;
        $raw=(string)$value;
        if(!preg_match('/^(0|[1-9][0-9]{0,9})(?:\\.([0-9]{1,2}))?$/',$raw,$m))return null;
        $whole=(int)$m[1];$fraction=(int)str_pad($m[2]??'',2,'0');
        return $whole*100+$fraction;
    }
    private static function display(int $minor):string {
        return intdiv($minor,100).'.'.str_pad((string)($minor%100),2,'0',STR_PAD_LEFT);
    }
}
