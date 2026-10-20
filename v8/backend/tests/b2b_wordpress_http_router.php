<?php
declare(strict_types=1);

/**
 * Disposable loopback-only HTTP fixture, not WordPress itself.
 * Exercises the REAL V7 Api::register(), Api::respond(), ApiContract,
 * ApiDispatch, Actor/Guard and B2BStagingRestProbe over a socket.
 * Synthetic identities are assigned by a STUB ActorResolver; real
 * WordPress bearer-token authentication still requires separate live UAT.
 */

namespace ExcelHerbal\ERP7\Security {
    final class ActorResolver {
        public static function current():Actor {
            $authorization=$_SERVER['HTTP_AUTHORIZATION']??'';
            return match($authorization){
                'Bearer synthetic-finance'=>new Actor(101,201,11,31,[31],
                    [Capabilities::ACCOUNTING_VIEW,Capabilities::REPORTS_VIEW],'RM'),
                'Bearer synthetic-bm'=>new Actor(102,202,11,31,[31],
                    [Capabilities::REPORTS_VIEW,Capabilities::REPORT_SUBMIT],'BM'),
                'Bearer synthetic-fse'=>new Actor(103,203,11,31,[31],
                    [Capabilities::DAILY_SELF],'FSE'),
                'Bearer synthetic-other-branch'=>new Actor(104,204,11,32,[32],
                    [Capabilities::ACCOUNTING_VIEW],'RM'),
                'Bearer synthetic-other-company'=>new Actor(105,205,12,31,[31],
                    [Capabilities::ACCOUNTING_VIEW],'RM'),
                default=>throw new \ExcelHerbal\ERP7\Domain\DomainException(
                    'Authentication required.','not_authenticated',401),
            };
        }
    }
}

namespace {
    const EH7_VERSION='7.4.0-http-fixture-only';
    const EH8_ENABLE_B2B_STAGING_REST_PROBE=true;
    const ARRAY_A='ARRAY_A';

    function wp_get_environment_type():string {
        return getenv('B2B_HTTP_ENV')?:'production';
    }
    function wp_generate_uuid4():string {return bin2hex(random_bytes(16));}

    final class WP_REST_Response {
        public array $headers=[];
        public function __construct(public mixed $body,public int $status=200){}
        public function header(string $name,string $value):void{$this->headers[$name]=$value;}
    }
    final class HttpProbeWpdb {
        public string $prefix='wp_';public string $last_error='';
        public function get_var(string $sql):string {
            if($sql!=='SELECT DATABASE()')throw new \RuntimeException('Only DB identity supported');
            return getenv('B2B_HTTP_DB')?:'not_v8_test';
        }
        public function prepare(string $sql,mixed ...$args):string {
            if(!str_contains($sql,'information_schema.TABLES')
               ||substr_count($sql,'%s')!==14
               ||count($args)!==14)
                throw new \RuntimeException('Unexpected financial query');
            return str_replace('%s',"'synthetic'", $sql);
        }
        public function get_results(string $sql,string $mode):array {
            if($mode!==ARRAY_A||!str_contains($sql,'information_schema.TABLES'))
                throw new \RuntimeException('Nonmetadata query forbidden in HTTP stub');
            $p=$this->prefix.'eh7_';
            $v7=['b2b_retailer_sales','b2b_retailer_sale_lines','stock_ledger',
                 'b2b_verified_tenders','journal_entries','journal_lines',
                 'accounts','b2b_cash_remittances','b2b_cashier_receipts_uat'];
            $v8=['v8_b2b_sale_intents_uat','v8_b2b_verified_tenders',
                 'v8_b2b_sale_tender_reservations_uat','v8_b2b_payment_intents_uat',
                 'v8_b2b_tender_intake_evidence_uat'];
            $all=[...array_map(static fn($name)=>$p.$name,$v7),...$v8];
            $missing=getenv('B2B_HTTP_MISSING')?:'';
            $myisam=getenv('B2B_HTTP_MYISAM')?:'';
            $out=[];
            foreach($all as $table){
                if($table===$missing)continue;
                $out[]=['TABLE_NAME'=>$table,'ENGINE'=>$table===$myisam?'MyISAM':'InnoDB'];
            }
            return $out;
        }
    }

    final class SyntheticRestRequest implements \ArrayAccess {
        public function __construct(private array $params){}
        public function get_param(string $key):mixed{return $this->params[$key]??null;}
        public function get_json_params():array{return [];}
        public function get_params():array{return $this->params;}
        public function get_header(string $key):string {
            return (string)($_SERVER['HTTP_'.strtoupper(str_replace('-','_',$key))]??'');
        }
        public function offsetExists(mixed $offset):bool{return isset($this->params[$offset]);}
        public function offsetGet(mixed $offset):mixed{return $this->params[$offset]??null;}
        public function offsetSet(mixed $offset,mixed $value):void{throw new \LogicException('immutable');}
        public function offsetUnset(mixed $offset):void{throw new \LogicException('immutable');}
    }

    require_once __DIR__.'/../../../backend/excel-herbal-erp-v7/src/Domain/DomainException.php';
    require_once __DIR__.'/../../../backend/excel-herbal-erp-v7/src/Security/Actor.php';
    require_once __DIR__.'/../../../backend/excel-herbal-erp-v7/src/Security/Capabilities.php';
    require_once __DIR__.'/../../../backend/excel-herbal-erp-v7/src/Security/Guard.php';
    require_once __DIR__.'/../../../backend/excel-herbal-erp-v7/src/Database/Db.php';
    require_once __DIR__.'/../../../backend/excel-herbal-erp-v7/src/Core/Input.php';
    require_once __DIR__.'/../../../backend/excel-herbal-erp-v7/src/Reporting/B2BStagingRestProbe.php';
    require_once __DIR__.'/../../../backend/excel-herbal-erp-v7/src/Http/RouteRegistry.php';
    require_once __DIR__.'/../../../backend/excel-herbal-erp-v7/src/Http/ApiContract.php';
    require_once __DIR__.'/../../../backend/excel-herbal-erp-v7/src/Http/ApiDispatch.php';
    require_once __DIR__.'/../../../backend/excel-herbal-erp-v7/src/Http/Api.php';

    $GLOBALS['wpdb']=new HttpProbeWpdb();
    $GLOBALS['http_routes']=[];
    function register_rest_route(string $ns,string $path,array $args):void {
        $GLOBALS['http_routes'][]=[$ns,$path,$args];
    }
    \ExcelHerbal\ERP7\Http\Api::register();

    // Never claim this fixture is a full WP installation or reachable
    // staging server. It is an isolated loopback PHP transport test.
    $path=parse_url($_SERVER['REQUEST_URI']??'',PHP_URL_PATH);
    if(!is_string($path)||!str_starts_with($path,'/wp-json/excel-herbal-erp/v7/')){
        http_response_code(404);
        header('Content-Type: application/json');
        echo '{"code":"rest_no_route"}';
        return;
    }
    $restPath=substr($path,strlen('/wp-json/excel-herbal-erp/v7'));
    $result=null;
    foreach($GLOBALS['http_routes'] as [$ns,$route,$args]){
        $pattern='#^'.$route.'$#D';
        if(!preg_match($pattern,$restPath,$captures))continue;
        if(($args['methods']??'')!==($_SERVER['REQUEST_METHOD']??''))continue;
        $req=new SyntheticRestRequest(array_merge($_GET,
            array_filter($captures,static fn($k)=>is_string($k),ARRAY_FILTER_USE_KEY)));
        $result=($args['callback'])($req);
        break;
    }
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    header('X-Content-Type-Options: nosniff');
    if(!$result instanceof WP_REST_Response){
        http_response_code(404);
        echo '{"code":"rest_no_route"}';
        return;
    }
    http_response_code($result->status);
    foreach($result->headers as $name=>$value)header($name.': '.$value);
    echo json_encode($result->body,JSON_THROW_ON_ERROR);
}
