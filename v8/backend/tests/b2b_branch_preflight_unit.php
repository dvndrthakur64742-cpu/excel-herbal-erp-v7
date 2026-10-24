<?php
declare(strict_types=1);
/** Pure contract regression: no WordPress bootstrap, network or database writes. */

namespace ExcelHerbal\ERP7\Core {
    final class Input {
        public static function date(string $raw,string $label):string {
            if(!preg_match('/^\d{4}-\d\d-\d\d$/D',$raw)||!checkdate((int)substr($raw,5,2),
                (int)substr($raw,8,2),(int)substr($raw,0,4)))
                throw new \RuntimeException('Invalid '.$label);
            return $raw;
        }
    }
}
namespace ExcelHerbal\ERP7\Security {
    final class Capabilities {public const ACCOUNTING_VIEW='accounting.view';}
    final class Actor {
        public function __construct(
            public int $companyId,public array $branchIds,public array $capabilities
        ){}
    }
    final class Guard {
        public static function branch(Actor $a,int $branch,string $cap):void {
            if(!in_array($branch,$a->branchIds,true)||!in_array($cap,$a->capabilities,true))
                throw new \RuntimeException('Access denied');
        }
    }
}
namespace ExcelHerbal\ERP7\Database {
    final class Db {
        public static ?object $conn=null;
        public static function wpdb():object {return self::$conn??throw new \RuntimeException('No fake');}
        public static function table(string $table):string{return 'wp_eh7_'.$table;}
    }
}
namespace ExcelHerbal\ERP8\B2B {
    final class RetailerSaleError extends \RuntimeException {}
    final class V7CanonicalPostingSinkUat {
        public static function assertNonProductionEnvironment(object $db):void {
            if($db->production)throw new RetailerSaleError('Not disposable v8_test.');
        }
    }
    final class V7B2BCrossLedgerAuditUat {
        public static array $audits=[];
        public static function inspect(\ExcelHerbal\ERP7\Security\Actor $a,int $branch,int $id):array {
            $record=self::$audits[$id]??throw new RetailerSaleError('Missing independent source.');
            return array_replace([
                'read_only'=>true,'scope'=>'disposable_v8_test_canonical_v7_only',
                'company_id'=>$a->companyId,'branch_id'=>$branch,
                'sale_id'=>$id,'production_posting_allowed'=>false,
                'cross_ledger_consistent'=>true,'mismatch_codes'=>[],
                'invoice_total_paise'=>20000,
                'cash_custody_state'=>'not_employee_cash_custody'
            ],$record);
        }
    }
}
namespace {
    use ExcelHerbal\ERP8\B2B\{V7B2BBranchDayPreflightUat as Preflight,V7B2BCrossLedgerAuditUat as Ledger};
    use ExcelHerbal\ERP7\Database\Db;
    use ExcelHerbal\ERP7\Security\{Actor,Capabilities};
    if(!defined('ARRAY_A'))define('ARRAY_A','ARRAY_A');
    require_once __DIR__.'/../src/B2B/V7B2BBranchDayPreflightUat.php';

    $checks=0;
    function verify(bool $yes,string $reason):void{
        global $checks;
        if(!$yes)throw new \RuntimeException('FAIL '.$reason);
        $checks++;echo 'PASS '.$reason."\n";
    }
    function denied(callable $action,string $reason):void {
        $blocked=false;
        try{$action();}catch(\Throwable){$blocked=true;}
        verify($blocked,$reason);
    }
    $fake=new class {
        public bool $production=false;
        public string $last_error='';
        public array $rows=[];
        public array $prepared=[];
        public bool $fail=false;
        public function prepare(string $sql,mixed ...$args):string {
            if(!str_contains($sql,'LIMIT 251'))throw new \RuntimeException('Query omitted overflow sentinel');
            $this->prepared=$args;
            return $sql;
        }
        public function get_results(string $sql,string $fmt):?array {
            if($this->fail){$this->last_error='Database error';return null;}
            return array_slice($this->rows,0,251);
        }
    };
    Db::$conn=$fake;
    $actor=new Actor(8,[23],[Capabilities::ACCOUNTING_VIEW]);
    $day='2026-10-19';
    $make=static fn(int $id,string $channel,string $mode):array=>[
        'id'=>(string)$id,'company_id'=>'8','branch_id'=>'23',
        'business_date'=>'2026-10-19','status'=>'posted',
        'channel'=>$channel,'payment_mode'=>$mode
    ];
    $empty=Preflight::inspect($actor,23,$day);
    verify($empty['state']==='no_sales_to_assess'
        &&!$empty['uat_reconciliation_complete']
        &&!$empty['production_release_authorized'],
        'empty date cannot become green or obtain deployment authority');
    verify($fake->prepared===[8,23,$day],
        'all source rows filtered with authenticated company branch and requested date');

    $fake->rows=[$make(17,'counter','cash')];
    Ledger::$audits=[17=>[]];
    $first=Preflight::inspect($actor,23,$day);
    verify($first['state']==='uat_books_consistent_not_production_certified'
        &&$first['counts']['sales_checked']===1
        &&$first['counts']['counter_cash']===1
        &&$first['counts']['ledger_mismatches']===0
        &&count($first['production_release_blockers'])===5,
        'single consistent counter sale is UAT-consistent only, with explicit release blockers');
    verify($first['physical_cash_verified_in_live_erp']===false
        &&$first['upi_bank_provider_verified_in_live_erp']===false
        &&$first['snapshot_isolation_guaranteed']===false,
        'no actual cashier, bank-provider or transactional snapshot claim');

    $fake->rows[]=$make(22,'field','cash');
    Ledger::$audits[22]=['cash_custody_state'=>'pending_cashier_handover'];
    $pending=Preflight::inspect($actor,23,$day);
    verify($pending['state']==='blocked_unremitted_field_cash'
        &&$pending['counts']['field_cash']===1
        &&$pending['counts']['cashier_handover_pending']===1
        &&!$pending['uat_reconciliation_complete'],
        'unremitted employee Cash is an operational gate, not an accounting mismatch');

    Ledger::$audits[22]=['cash_custody_state'=>'cashier_handover_reconciled_uat'];
    $cleared=Preflight::inspect($actor,23,$day);
    verify($cleared['uat_reconciliation_complete']
        &&$cleared['counts']['cashier_handover_reconciled_uat']===1,
        'independent cashier posting clears outstanding field Cash gate');

    $fake->rows[]=$make(31,'counter','upi');
    Ledger::$audits[31]=[];
    $mixed=Preflight::inspect($actor,23,$day);
    verify($mixed['counts']['upi']===1&&$mixed['counts']['sales_checked']===3
        &&$mixed['uat_reconciliation_complete']===true,
        'mixed cash UPI and field cash are counted exactly once');

    Ledger::$audits[31]=['cross_ledger_consistent'=>false,
        'mismatch_codes'=>['trusted_payment_intent_evidence_mismatch']];
    $broken=Preflight::inspect($actor,23,$day);
    verify($broken['state']==='blocked_ledger_mismatch'
        &&$broken['counts']['ledger_mismatches']===1
        &&$broken['entries'][2]['ledger_consistent']===false,
        'one forged UPI source stops whole branch signoff');
    Ledger::$audits[31]=[];

    $fake->rows[0]['status']='pending';
    $badHeader=Preflight::inspect($actor,23,$day);
    verify($badHeader['state']==='blocked_ledger_mismatch'
        &&in_array('invalid_source_header',$badHeader['entries'][0]['mismatch_codes'],true),
        'unposted sale cannot be disguised by a falsely clean per-sale audit');
    $fake->rows[0]['status']='posted';

    $fake->rows[1]['branch_id']='24';
    denied(fn()=>Preflight::inspect($actor,23,$day),
        'cross-branch sale row fails closed despite apparently valid per-sale metadata');
    $fake->rows[1]['branch_id']='23';

    $fake->rows[1]['id']='17';
    denied(fn()=>Preflight::inspect($actor,23,$day),
        'duplicate or unsorted canonical IDs abort preflight');
    $fake->rows[1]['id']='22';

    $fake->rows=array_fill(0,251,$make(17,'counter','cash'));
    denied(fn()=>Preflight::inspect($actor,23,$day),
        'branch batch greater than 250 aborts instead of returning a partial green');
    $fake->rows=[$make(17,'counter','cash')];

    denied(fn()=>Preflight::inspect(new Actor(8,[23],[]),23,$day),
        'sales-only actor cannot inspect financial preflight');
    denied(fn()=>Preflight::inspect(new Actor(9,[23],[Capabilities::ACCOUNTING_VIEW]),24,$day),
        'different branch is blocked before reading');
    denied(fn()=>Preflight::inspect($actor,23,'2026-02-30'),
        'invalid date is rejected');
    $fake->production=true;
    denied(fn()=>Preflight::inspect($actor,23,$day),
        'production database gate is checked before query');
    $fake->production=false;
    $fake->fail=true;
    denied(fn()=>Preflight::inspect($actor,23,$day),
        'query failure cannot produce a successful partial report');
    echo "B2B BRANCH-DAY PREFLIGHT CONTRACT {$checks}/{$checks} PASS\n";
}
