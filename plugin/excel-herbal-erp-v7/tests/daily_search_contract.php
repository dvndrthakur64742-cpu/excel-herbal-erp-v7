<?php
/** Synthetic least-privilege Daily Order history tests. No live data used. */
if (!defined('ARRAY_A')) define('ARRAY_A','ARRAY_A');
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\DailyOrder\DailyOrderSearchService as Search;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Http\ApiContract;
use ExcelHerbal\ERP7\Http\RouteRegistry;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities as Cap;

final class FakeDailyHistoryWpdb {
    public string $prefix='wp_';
    public array $prepared=[];
    public int $found=1;
    public function prepare(string $sql,mixed ...$args):string {
        $this->prepared[]=['sql'=>$sql,'args'=>$args];
        return $sql;
    }
    public function esc_like(string $text):string {
        return addcslashes($text,'_%\\');
    }
    public function get_var(string $sql):int { return $this->found; }
    public function get_results(string $sql,mixed $format=null):array {
        if(str_contains($sql,'SELECT id,assigned_branch_id,reporting_employee_id,designation_code')) {
            return [
                ['id'=>20,'assigned_branch_id'=>1,'reporting_employee_id'=>null,'designation_code'=>'SM'],
                ['id'=>21,'assigned_branch_id'=>1,'reporting_employee_id'=>20,'designation_code'=>'EMPLOYEE'],
                ['id'=>22,'assigned_branch_id'=>2,'reporting_employee_id'=>20,'designation_code'=>'EMPLOYEE'],
            ];
        }
        return [[
            'id'=>7,'company_id'=>1,'branch_id'=>1,'employee_id'=>21,
            'business_date'=>'2026-11-02','status'=>'issued','employee_name'=>'Synthetic Staff',
            'employee_code'=>'DEMO','initial_request_status'=>'issued',
            'additional_request_status'=>null,
        ]];
    }
}
$GLOBALS['wpdb']=new FakeDailyHistoryWpdb();
function passDaily(bool $condition,string $label):void {
    if(!$condition){fwrite(STDERR,"FAIL $label\n");exit(1);}
    echo "PASS $label\n";
}
function deniedDaily(callable $action,string $code,string $label):void {
    try{$action();}catch(DomainException $e){
        passDaily($e->codeKey===$code,$label);return;
    }
    passDaily(false,$label);
}
$db=$GLOBALS['wpdb'];
$self=new Actor(21,21,1,1,[1],[Cap::DAILY_SELF],'EMPLOYEE');
$view=Search::search($self,null,1,25,'Synthetic','issued','2026-11-01','2026-11-03');
passDaily($view['total']===1&&count($view['items'])===1&&$view['page_size']===25,
    'paginated result matches existing Flutter search shape');
passDaily(!$view['has_more'],'last page cannot show next');
$select=array_values(array_filter($db->prepared,static fn($x)=>
    str_contains($x['sql'],'SELECT c.id,')));
passDaily(count($select)===1,'search runs one scoped record query');
$sql=$select[0]['sql'];$args=$select[0]['args'];
passDaily(str_contains($sql,'c.company_id=%d')&&
    str_contains($sql,'c.branch_id IN (%d)')&&
    str_contains($sql,'c.employee_id IN (%d)')&&
    $args[0]===1&&$args[1]===1&&$args[2]===21,
    'self search is explicitly company, branch and employee restricted');
passDaily(str_contains($sql,'ORDER BY c.business_date DESC,c.id DESC LIMIT %d OFFSET %d'),
    'stable pagination is bounded');
deniedDaily(fn()=>Search::search($self,2),'branch_forbidden','cross-branch history denied');
deniedDaily(fn()=>Search::search(new Actor(21,21,1,1,[1],[],'EMPLOYEE'),1),
    'permission_denied','history requires authenticated daily capability');

$manager=new Actor(20,20,1,1,[1],[Cap::DAILY_OTHERS],'SM');
$db->prepared=[];
Search::search($manager,null,2,20);
$select=array_values(array_filter($db->prepared,static fn($x)=>
    str_contains($x['sql'],'SELECT c.id,')));
passDaily(count($select)===1,'manager history queried');
$args=$select[0]['args'];
passDaily($args[0]===1&&$args[1]===1&&in_array(20,$args,true)&&
    in_array(21,$args,true)&&!in_array(22,$args,true)&&
    str_contains($select[0]['sql'],'c.employee_id IN (%d,%d)'),
    'manager search excludes employee assigned outside authorized branch');
passDaily(array_slice($args,-2)===[20,20],
    'page two uses exact bounded size and offset');
$db->prepared=[];
Search::search($self,1,1,1,'ACME%_');
$select=array_values(array_filter($db->prepared,static fn($x)=>
    str_contains($x['sql'],'SELECT c.id,')));
passDaily(in_array('%ACME\\%\\_%',$select[0]['args'],true),
    'search wildcard characters are SQL-escaped');

deniedDaily(fn()=>Search::search($self,1,0),'daily_search_pagination_invalid','page zero rejected');
deniedDaily(fn()=>Search::search($self,1,1,100),'daily_search_pagination_invalid','unbounded page size rejected');
deniedDaily(fn()=>Search::search($self,1,1,25,'','malicious'),
    'daily_search_status_invalid','unknown status rejected');
deniedDaily(fn()=>Search::search($self,1,1,25,'','', '2026-11-31'),
    'date_invalid','invalid calendar date rejected');
deniedDaily(fn()=>Search::search($self,1,1,25,'','', '2026-11-03','2026-11-02'),
    'date_range_invalid','reversed date range rejected');
$db->found=0;
$empty=Search::search($self,1);
passDaily($empty['total']===0&&$empty['items']===[]&&$empty['has_more']===false,
    'empty history returns safe pagination shape');

$routes=array_values(array_filter(RouteRegistry::routes(),static fn($r)=>
    $r[0]==='GET'&&$r[1]==='/daily/cycles/search'&&
    $r[2]==='daily.search'&&$r[3]===true));
passDaily(count($routes)===1,'authenticated search route is GET-only');
$declared=array_values(array_filter(ApiContract::describe()['routes'],
    static fn($r)=>$r['method']==='GET'&&$r['path']==='/daily/cycles/search'));
passDaily(count($declared)===1&&$declared[0]['idempotency_required']===false,
    'search contract never requires a mutation token');
$service=file_get_contents(__DIR__.'/../src/DailyOrder/DailyOrderSearchService.php');
foreach(['Db::mustInsert(','Db::mustUpdate(','StockService::move(',
         'StockService::transferCustody(','AccountingService::post('] as $write){
    passDaily(!str_contains($service,$write),'search has no business mutation '.$write);
}
echo "PASSED Daily Order history scope, paging, input and route contracts\n";
