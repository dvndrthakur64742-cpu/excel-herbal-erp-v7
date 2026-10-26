<?php
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
/**
 * Fail-closed service-level whole PCS: ApiDispatch bypasses REST payload guard.
 * Runs on disposable synthetic MariaDB only. Never touches Office.
 */
uat_case('uat_daily_positive_whole_pcs_internal_dispatch', function () use ($self,$manager,$wpdb) {
    $date=(new DateTimeImmutable(uat_date()))->modify('-219 days')->format('Y-m-d');
    $snapshot=static function()use($wpdb):array{
        $out=[];
        foreach(['daily_cycles','daily_requests','daily_request_lines','daily_issue_lines',
                 'stock_ledger','journal_entries','audit_log'] as $name) {
            $out[$name]=(int)$wpdb->get_var('SELECT COUNT(*) FROM '.Db::table($name));
        }
        $out['cycle_states']=(array)$wpdb->get_results('SELECT id,status FROM '.Db::table('daily_cycles').' ORDER BY id DESC LIMIT 20',ARRAY_A);
        $out['request_states']=(array)$wpdb->get_results('SELECT id,status FROM '.Db::table('daily_requests').' ORDER BY id DESC LIMIT 20',ARRAY_A);
        $out['request_lines']=(array)$wpdb->get_results('SELECT id,daily_request_id,product_id,quantity FROM '.Db::table('daily_request_lines').' ORDER BY id DESC LIMIT 20',ARRAY_A);
        $out['stock']=(array)$wpdb->get_results(
            'SELECT branch_id,custodian_key,quantity FROM '.Db::table('stock_balances').
            ' WHERE company_id=1 AND product_id=100 ORDER BY branch_id,custodian_key',ARRAY_A
        );
        return $out;
    };
    $deny=static function(string $kind,callable $operation)use($snapshot):void{
        $before=$snapshot();
        try {
            $operation();
            throw new RuntimeException('Invalid Daily whole PCS accepted: '.$kind);
        } catch(DomainException $error) {
            if($error->codeKey!=='whole_pcs_required'||$error->httpStatus!==422)throw $error;
        }
        if($snapshot()!==$before)throw new RuntimeException('Rejected Daily PCS changed stock/request/journal/audit: '.$kind);
    };
    $invalid=[NAN,INF,-INF,-1,0,0.5,1.5,'1.5','NaN'];
    foreach($invalid as$input) {
        $deny('create',fn()=>uat_dispatch('daily.create',$self,[
            'branch_id'=>1,'employee_id'=>10,'business_date'=>$date,
            'lines'=>[['product_id'=>100,'quantity'=>$input]]
        ]));
    }
    $created=uat_dispatch('daily.create',$self,[
        'branch_id'=>1,'employee_id'=>10,'business_date'=>$date,
        'lines'=>[['product_id'=>100,'quantity'=>2]]
    ]);
    if(($created['status']??'')!=='morning_draft')throw new RuntimeException('Valid positive PCS Daily create regressed');
    $id=(int)$created['id'];$request=(int)$created['request_id'];
    foreach($invalid as$input) {
        $deny('edit_draft',fn()=>uat_dispatch('daily.edit_draft',$self,[
            'id'=>$id,'lines'=>[['product_id'=>100,'quantity'=>$input]]
        ]));
    }
    $edited=uat_dispatch('daily.edit_draft',$self,[
        'id'=>$id,'lines'=>[['product_id'=>100,'quantity'=>2]]
    ]);
    if(($edited['status']??'')!=='morning_draft')throw new RuntimeException('Valid whole PCS draft edit regressed');
    $line=(int)$wpdb->get_var($wpdb->prepare(
        'SELECT id FROM '.Db::table('daily_request_lines').' WHERE daily_request_id=%d',$request
    ));
    if($line<=0)throw new RuntimeException('Edited draft line not found');
    $corrupt=static function(float $quantity)use($wpdb,$line):void{
        if($wpdb->update(Db::table('daily_request_lines'),['quantity'=>$quantity],['id'=>$line])===false)
            throw new RuntimeException('Could not create corrupted synthetic quantity');
    };
    $corrupt(1.5);
    $deny('submitted_corrupt_draft',fn()=>uat_dispatch('daily.submit',$self,['id'=>$id]));
    $corrupt(2.0);
    uat_dispatch('daily.submit',$self,['id'=>$id]);
    $corrupt(1.5);
    $deny('approve_corrupt_submitted',fn()=>uat_dispatch('daily.approve',$manager,['id'=>$request]));
    $corrupt(2.0);
    uat_dispatch('daily.approve',$manager,['id'=>$request]);
    $line=(int)$wpdb->get_var($wpdb->prepare(
        'SELECT id FROM '.Db::table('daily_request_lines').' WHERE daily_request_id=%d',$request
    ));
    if($line<=0)throw new RuntimeException('Valid initial request line not found');
    $corrupt(1.5);
    $deny('issue_preflight_corrupt_approved',fn()=>uat_dispatch('daily.issue_preflight',$manager,['id'=>$request]));
    $deny('issue_corrupt_approved',fn()=>uat_dispatch('daily.issue',$manager,['id'=>$request,'allocations'=>[]]));
    $corrupt(2.0);
    foreach($invalid as$input) {
        $deny('issue_allocation',fn()=>uat_dispatch('daily.issue',$manager,[
            'id'=>$request,'allocations'=>[['request_line_id'=>$line,'quantity'=>$input]]
        ]));
    }
    $issued=uat_dispatch('daily.issue',$manager,['id'=>$request,'allocations'=>[]]);
    if(($issued['status']??'')!=='issued'||abs((float)($issued['issued_quantity']??0)-2)>.001)
        throw new RuntimeException('Valid automatic whole PCS issue regressed');
    foreach($invalid as$input) {
        $deny('additional',fn()=>uat_dispatch('daily.additional',$self,[
            'id'=>$id,'lines'=>[['product_id'=>100,'quantity'=>$input]]
        ]));
    }
    $extra=uat_dispatch('daily.additional',$self,[
        'id'=>$id,'lines'=>[['product_id'=>100,'quantity'=>1]]
    ]);
    if(($extra['status']??'')!=='submitted')throw new RuntimeException('Valid additional request regressed');
    uat_dispatch('daily.approve',$manager,['id'=>(int)$extra['id']]);
    $issuedExtra=uat_dispatch('daily.issue',$manager,['id'=>(int)$extra['id'],'allocations'=>[]]);
    if(($issuedExtra['status']??'')!=='issued'||abs((float)($issuedExtra['issued_quantity']??0)-1)>.001)
        throw new RuntimeException('Valid additional issue regressed');
});
