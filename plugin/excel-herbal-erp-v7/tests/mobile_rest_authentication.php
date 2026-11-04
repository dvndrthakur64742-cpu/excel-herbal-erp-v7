<?php
/** Isolated PHP regression of the hosted ERP bearer-token WP REST gate.
 * No WordPress, DB credentials, real users or network access required.
 */
declare(strict_types=1);

namespace ExcelHerbal\ERP7\Database {
    final class Db {
        public static function wpdb():\MockDb {return $GLOBALS['fake_db'];}
        public static function table(string $table):string {return 'test_eh7_'.$table;}
    }
}

namespace {
    final class MockDb {
        public bool $allowAccess=false;
        public int $updates=0;
        public string $lastQuery='';
        public function prepare(string $query,...$args):string {
            $this->lastQuery=$query;
            return 'mock prepared query';
        }
        public function get_row(string $sql,$type=null):?array {
            return $this->allowAccess?['id'=>42,'wp_user_id'=>7]:null;
        }
        public function update(string $table,array $values,array $where):int {
            if($table!=='test_eh7_mobile_sessions'||!isset($values['last_used_at'])||$where['id']!==42) {
                throw new \RuntimeException('Unexpected fake DB mutation');
            }
            $this->updates++;
            return 1;
        }
    }
    final class WP_Error {
        public function __construct(public string $code,public string $message,public array $data=[]){}
        public function get_error_code():string{return $this->code;}
        public function get_error_data():array{return $this->data;}
    }
    $GLOBALS['fake_db']=new MockDb();
    $GLOBALS['filters']=[];
    $GLOBALS['current_uid']=-1;
    function add_filter(string $name,$callback,int $priority):void {
        $GLOBALS['filters'][$name]=['callback'=>$callback,'priority'=>$priority];
    }
    function wp_set_current_user(int $uid):void {$GLOBALS['current_uid']=$uid;}
    function checkAuth(bool $ok,string $detail):void {
        if(!$ok)throw new \RuntimeException('Auth parity regression: '.$detail);
    }
    define('REST_REQUEST',true);
    define('ARRAY_A','ARRAY_A');
    $wp=(object)['query_vars'=>['rest_route'=>'/excel-herbal-erp/v7/health']];
    require __DIR__.'/../src/Security/MobileAuth.php';
    $class=\ExcelHerbal\ERP7\Security\MobileAuth::class;
    $class::boot();
    checkAuth(($GLOBALS['filters']['rest_authentication_errors']['priority']??null)===90,
      'ERP REST gate filter priority changed');
    checkAuth(($GLOBALS['filters']['determine_current_user']['priority']??null)===20,
      'existing WordPress current user filter removed');

    unset($_SERVER['HTTP_AUTHORIZATION']);
    checkAuth($class::restAuthentication(null)===null,'cookie-only request was hijacked');
    $_SERVER['HTTP_AUTHORIZATION']='Bearer invalid-synthetic-token';
    $wp->query_vars['rest_route']='/wp/v2/users';
    checkAuth($class::restAuthentication(null)===null,'unrelated REST routes were touched');
    $wp->query_vars['rest_route']='/excel-herbal-erp/v7/health';
    $prior=new WP_Error('prior_error','Earlier security layer rejected this request',['status'=>403]);
    checkAuth($class::restAuthentication($prior)===$prior,'prior WP_Error overwritten');

    $bad=$class::restAuthentication(null);
    checkAuth($bad instanceof WP_Error && $bad->get_error_code()==='not_authenticated' &&
      ($bad->get_error_data()['status']??0)===401 && $GLOBALS['current_uid']===0,
      'invalid Bearer did not fail 401');
    checkAuth($GLOBALS['fake_db']->updates===0,'invalid Bearer wrote session data');

    $GLOBALS['fake_db']->allowAccess=true;
    $good=$class::restAuthentication(null);
    checkAuth($good===true && $GLOBALS['current_uid']===7 && $GLOBALS['fake_db']->updates===1,
      'valid Bearer did not resolve current WordPress session');
    checkAuth(str_contains($GLOBALS['fake_db']->lastQuery,'revoked_at IS NULL') &&
      str_contains($GLOBALS['fake_db']->lastQuery,'access_expires_at'),
      'live expiry/revocation guards were removed');

    echo "PASS legacy REST gate registered with WordPress filter priority 90\n";
    echo "PASS cookie-only and unrelated routes unchanged; prior authentication errors retained\n";
    echo "PASS invalid bearer denied 401; valid synthetic bearer resolves user; expired/revoked guards retained\n";
    echo "MOBILE REST AUTHORITY COMPATIBILITY CONTRACTS PASSED (NO REAL SESSION USED)\n";
}
