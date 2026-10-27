<?php
declare(strict_types=1);
/** Full canonical V7 route-registration + dispatcher role-smoke (NO WP DB writes). */
require_once __DIR__.'/../src/Domain/DomainException.php';
require_once __DIR__.'/../src/Security/Actor.php';
require_once __DIR__.'/../src/Security/Capabilities.php';
require_once __DIR__.'/../src/Security/Guard.php';
require_once __DIR__.'/../src/Database/Db.php';
require_once __DIR__.'/../src/Core/Input.php';
require_once __DIR__.'/../src/Reporting/B2BStagingRestProbe.php';
require_once __DIR__.'/../src/Http/RouteRegistry.php';
require_once __DIR__.'/../src/Http/ApiContract.php';
require_once __DIR__.'/../src/Http/ApiDispatch.php';
require_once __DIR__.'/../src/Http/Api.php';

use ExcelHerbal\ERP7\Reporting\B2BStagingRestProbe as Probe;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities as C};
use ExcelHerbal\ERP7\Http\{Api,ApiDispatch,ApiContract,RouteRegistry};
use ExcelHerbal\ERP7\Domain\DomainException;

if(!defined('ARRAY_A'))define('ARRAY_A','ARRAY_A');
// This is a TEST-ONLY registration toggle. Staging probe always also checks
// actual database name and WordPress environment *on every request*.
if(!defined('EH8_ENABLE_B2B_STAGING_REST_PROBE'))
    define('EH8_ENABLE_B2B_STAGING_REST_PROBE',true);
$GLOBALS['fake_environment']='production';
function wp_get_environment_type():string{return $GLOBALS['fake_environment'];}
$GLOBALS['routes_registered']=[];
function register_rest_route(string $namespace,string $path,array $args):void {
    $GLOBALS['routes_registered'][]=['namespace'=>$namespace,'path'=>$path,'args'=>$args];
}
function testRoutes():array {
    $GLOBALS['routes_registered']=[];Api::register();
    return array_values(array_filter($GLOBALS['routes_registered'],
        static fn(array $r):bool=>str_contains($r['path'],'b2b-staging-readiness')));
}
final class ReadOnlyWpdbStub {
    public string $prefix='wp_';public string $database='v8_test';
    public string $last_error='';public int $dataReads=0;public int $prepares=0;
    public bool $fail=false;
    public array $engines=[];
    public array $bound=[];
    public function get_var(string $sql):?string {
        if($sql!=='SELECT DATABASE()')throw new RuntimeException('Unexpected read');
        return $this->database;
    }
    public function prepare(string $sql,mixed ...$args):string {
        if(!str_contains($sql,'information_schema.TABLES')
          ||!str_contains($sql,'TABLE_SCHEMA=DATABASE()')
          ||substr_count($sql,'%s')!==14
          ||count($args)!==14)throw new RuntimeException('Unsafe source discovery query');
        $this->bound=$args;$this->prepares++;
        return $sql;
    }
    public function get_results(string $sql,string $mode):?array {
        if(!str_contains($sql,'information_schema.TABLES')||$mode!==ARRAY_A)
            throw new RuntimeException('Financial business table queried');
        $this->dataReads++;
        if($this->fail){$this->last_error='Injected permissions error';return null;}
        return array_map(static fn(string $t,string $engine):array=>[
            'TABLE_NAME'=>$t,'ENGINE'=>$engine],
            array_keys($this->engines),array_values($this->engines));
    }
}
$GLOBALS['wpdb']=$db=new ReadOnlyWpdbStub();
$counter=0;
function ok(bool $good,string $why):void {
    global $counter;
    if(!$good)throw new RuntimeException('FAIL '.$why);
    ++$counter;echo 'PASS '.$why.PHP_EOL;
}
function rejects(callable $fn,string $code):void {
    try{$fn();throw new RuntimeException('Expected '. $code);}
    catch(DomainException $e){ok($e->codeKey===$code,'fails closed '.$code);}
}
$finance=new Actor(501,111,11,31,[31],[
    C::ACCOUNTING_VIEW,C::REPORTS_VIEW],'RM');
$regional=new Actor(502,222,11,31,[31],[C::REPORTS_VIEW],'RM');
$bm=new Actor(503,333,11,31,[31],[C::REPORTS_VIEW,C::REPORT_SUBMIT],'BM');
$field=new Actor(504,444,11,31,[31],[C::DAILY_SELF],'FSE');
$otherBranch=new Actor(505,555,11,32,[32],[C::ACCOUNTING_VIEW],'RM');
$foreign=new Actor(506,666,12,31,[31],[C::ACCOUNTING_VIEW],'RM');
$path='/development/b2b-staging-readiness';
$reg=RouteRegistry::routes();
$matched=array_values(array_filter($reg,static fn(array $r):bool=>$r[1]===$path));
ok(count($matched)===1&&$matched[0]===['GET',$path,'dev.b2b_probe',true],
    'exactly one authenticated, GET-only diagnostic declared with no POST/PUT counterpart');
ok(count(testRoutes())===0,'production environment does not register development B2B route');
$GLOBALS['fake_environment']='staging';
ok(count(testRoutes())===0,'staging environment alone cannot activate financial diagnostic');
$GLOBALS['fake_environment']='development';
$db->database='office_live';
ok(count(testRoutes())===0,'development flag on non-v8_test live database cannot expose diagnostic');
$db->database='v8_test';
$db->prefix='not-safe!!';
ok(count(testRoutes())===0,'unsafe table prefix cannot expose diagnostic');
$db->prefix='wp_';
$routes=testRoutes();
ok(count($routes)===1&&$routes[0]['namespace']==='excel-herbal-erp/v7'
    &&$routes[0]['args']['methods']==='GET'
    &&is_callable($routes[0]['args']['callback']),
    'disposable development database exposes actual canonical WordPress GET callback');
$rest=new class{
    public array $params=['branch_id'=>'31'];
    public function get_param(string $key):mixed{return $this->params[$key]??null;}
    public function get_json_params():array{return [];}
};
ApiContract::validate('dev.b2b_probe',$rest,'GET');
ok(true,'REST contract accepts positive branch ID');
$rest->params=['branch_id'=>'ABC'];
rejects(fn()=>ApiContract::validate('dev.b2b_probe',$rest,'GET'),'parameter_invalid');
$rest->params=[];
rejects(fn()=>ApiContract::validate('dev.b2b_probe',$rest,'GET'),'parameter_required');
$rest->params=['branch_id'=>'31'];
$prefix=$db->prefix.'eh7_';
$v7=['b2b_retailer_sales','b2b_retailer_sale_lines','stock_ledger',
'b2b_verified_tenders','journal_entries','journal_lines','accounts',
'b2b_cash_remittances','b2b_cashier_receipts_uat'];
$v8=['v8_b2b_sale_intents_uat','v8_b2b_verified_tenders',
'v8_b2b_sale_tender_reservations_uat','v8_b2b_payment_intents_uat',
'v8_b2b_tender_intake_evidence_uat'];
foreach($v7 as $name)$db->engines[$prefix.$name]='InnoDB';
foreach($v8 as $name)$db->engines[$name]='InnoDB';
$report=ApiDispatch::dispatch('dev.b2b_probe',$rest,$finance);
ok($report['read_only']&&$report['structural_preflight_possible']
    &&$report['existing_source_table_count']===14
    &&$report['dependency_table_count']===14,
    'real dispatcher returns full fourteen-table InnoDB compatibility without reading sales rows');
ok($report['company_id']===11&&$report['branch_id']===31
    &&$report['financial_records_disclosed']===false
    &&$report['snapshot_executed']===false
    &&$report['financial_posting_enabled']===false
    &&$report['production_release_authorized']===false,
    'response preserves authorized branch and never claims posting, bank proof or snapshot');
ok($db->dataReads===1 && $db->prepares===1 &&count($db->bound)===14,
    'source discovery is one read-only metadata query with fourteen literal bindings');
$before=$db->dataReads;
rejects(fn()=>ApiDispatch::dispatch('dev.b2b_probe',$rest,$regional),'permission_denied');
rejects(fn()=>ApiDispatch::dispatch('dev.b2b_probe',$rest,$bm),'permission_denied');
rejects(fn()=>ApiDispatch::dispatch('dev.b2b_probe',$rest,$field),'permission_denied');
rejects(fn()=>ApiDispatch::dispatch('dev.b2b_probe',$rest,$otherBranch),'branch_forbidden');
ok($db->dataReads===$before,'unauthorized roles and branches never reach information_schema');
$db->engines['wp_eh7_journal_lines']='MyISAM';
$bad=Probe::view($finance,31);
ok($bad['all_sources_innodb']===false
    &&$bad['structural_preflight_possible']===false
    &&$bad['reason']==='nontransactional_source_table',
    'nontransactional GL table blocks staging financial-source compatibility');
$db->engines['wp_eh7_journal_lines']='InnoDB';
unset($db->engines['v8_b2b_payment_intents_uat']);
$missing=Probe::view($finance,31);
ok($missing['missing_source_table_count']===1
    &&$missing['structural_preflight_possible']===false
    &&$missing['reason']==='incomplete_disposable_uat_schema',
    'missing immutable payment-intent table never receives false green status');
$db->engines['v8_b2b_payment_intents_uat']='InnoDB';
$db->fail=true;
rejects(fn()=>Probe::view($finance,31),'b2b_staging_metadata_failed');
$db->fail=false;$db->last_error='';
$db->database='office_production';
rejects(fn()=>Probe::view($finance,31),'b2b_staging_probe_disabled');
ok(count(testRoutes())===0,'route is removed during subsequent registration if database changes');
$db->database='v8_test';
$GLOBALS['fake_environment']='production';
rejects(fn()=>Probe::view($finance,31),'b2b_staging_probe_disabled');
ok(count(testRoutes())===0,'production environment refuses stale diagnostic callbacks even after registration');
$php=file_get_contents(__DIR__.'/../src/Reporting/B2BStagingRestProbe.php');
ok(!str_contains($php,'->insert(')&&!str_contains($php,'->update(')
    &&!str_contains($php,'wp_mail(')&&!str_contains($php,'postJournal(')
    &&!str_contains($php,'BEGIN')&&!str_contains($php,'INSERT INTO'),
    'probe has no database writes, financial posting or notifications');
echo "B2B WORDPRESS STAGING REST ROLE/REGISTRATION: {$counter}/{$counter} PASS\n";
