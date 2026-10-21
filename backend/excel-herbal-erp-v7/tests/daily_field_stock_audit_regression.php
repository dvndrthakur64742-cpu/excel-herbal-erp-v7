<?php
declare(strict_types=1);
require_once __DIR__.'/../src/Domain/DomainException.php';
require_once __DIR__.'/../src/Security/Actor.php';
require_once __DIR__.'/../src/Security/Capabilities.php';
require_once __DIR__.'/../src/Security/Guard.php';
require_once __DIR__.'/../src/DailyOrder/DailyFieldStockAudit.php';

use ExcelHerbal\ERP7\DailyOrder\{DailyFieldStockAudit as Audit,DailyFieldStockAuditReader as Source};
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities};
if(!defined('ARRAY_A'))define('ARRAY_A','ARRAY_A');
$checks=0;
function checkField(bool $yes,string $why):void{
    global $checks;
    if(!$yes)throw new RuntimeException('FAIL '.$why);
    $checks++;echo 'PASS '.$why."\n";
}
function blockedField(callable $fn,string $code):void{
    try{$fn();throw new RuntimeException('Expected '.$code);}
    catch(DomainException $e){checkField($e->codeKey===$code,'fail-closed '.$code);}
}
class MemoryFieldSource implements Source {
    public array $cycle=['id'=>'62','company_id'=>'11','branch_id'=>'31','employee_id'=>'52','status'=>'completed'];
    public array $issues=[
        ['id'=>'6','request_id'=>'7','request_status'=>'issued','product_id'=>'19','batch_id'=>null,'quantity'=>'6.000'],
    ];
    public array $closing=[[
        'daily_cycle_id'=>'62','status'=>'posted','expected_amount'=>'400.00',
        'cash_amount'=>'150.00','upi_amount'=>'250.00',
    ]];
    public array $closingLines=[[
        'issue_line_id'=>'6','product_id'=>'19','batch_id'=>null,
        'issued_quantity'=>'6.000','return_quantity'=>'2.000',
        'retail_quantity'=>'3.000','wholesale_quantity'=>'1.000',
    ]];
    public array $movements=[];
    public array $journals=[['id'=>'73','branch_id'=>'31','status'=>'posted']];
    public array $performance=[['id'=>'100','branch_id'=>'31','employee_id'=>'52']];
    public array $glLines=[
        ['id'=>'501','journal_entry_id'=>'73','account_id'=>'101','account_company_id'=>'11','account_code'=>'BR_CASH','account_type'=>'asset','account_subtype'=>'cash','debit'=>'150.00','credit'=>'0.00'],
        ['id'=>'502','journal_entry_id'=>'73','account_id'=>'102','account_company_id'=>'11','account_code'=>'BR_UPI','account_type'=>'asset','account_subtype'=>'upi','debit'=>'250.00','credit'=>'0.00'],
        ['id'=>'503','journal_entry_id'=>'73','account_id'=>'103','account_company_id'=>'11','account_code'=>'SALES','account_type'=>'income','account_subtype'=>null,'debit'=>'0.00','credit'=>'400.00'],
        ['id'=>'504','journal_entry_id'=>'73','account_id'=>'104','account_company_id'=>'11','account_code'=>'COGS','account_type'=>'expense','account_subtype'=>null,'debit'=>'200.00','credit'=>'0.00'],
        ['id'=>'505','journal_entry_id'=>'73','account_id'=>'105','account_company_id'=>'11','account_code'=>'INVENTORY','account_type'=>'asset','account_subtype'=>null,'debit'=>'0.00','credit'=>'200.00'],
    ];
    public function __construct(){
        $i=0;
        foreach([
            ['daily_issue',7,null,'OUT','6.000'],
            ['daily_issue',7,52,'IN','6.000'],
            ['daily_sale',62,52,'OUT','4.000'],
            ['daily_return',62,52,'OUT','2.000'],
            ['daily_return',62,null,'IN','2.000'],
        ] as [$type,$sid,$cust,$dir,$qty]){
            $this->movements[]=[
                'id'=>(string)(++$i),'company_id'=>'11','branch_id'=>'31',
                'product_id'=>'19','batch_id'=>null,'custodian_employee_id'=>$cust,
                'source_type'=>$type,'source_id'=>(string)$sid,'direction'=>$dir,'quantity'=>$qty,
            ];
        }
    }
    public function cycle(int $company,int $id):?array{return $this->cycle;}
    public function issues(int $company,int $id):array{return $this->issues;}
    public function closing(int $company,int $id):array{return $this->closing;}
    public function closingLines(int $company,int $id):array{return $this->closingLines;}
    public function movements(int $company,int $branch,int $cycle,array $requestIds):array{return $this->movements;}
    public function journalHeaders(int $company,int $id):array{return $this->journals;}
    public function journalLines(int $company,int $cycle,int $journalId):array{return $this->glLines;}
    public function performance(int $company,int $id):array{return $this->performance;}
}
$finance=new Actor(1,5,11,31,[31],[Capabilities::ACCOUNTING_VIEW],'RM');
$wrongCompany=new Actor(1,5,19,31,[31],[Capabilities::ACCOUNTING_VIEW],'RM');
$wrongBranch=new Actor(1,5,11,32,[32],[Capabilities::ACCOUNTING_VIEW],'RM');
$noFinance=new Actor(1,5,11,31,[31],[Capabilities::DAILY_OTHERS],'RM');
$source=new MemoryFieldSource();
$ok=Audit::inspect($finance,62,$source);
checkField($ok['stock_ledger_reconciled']&&$ok['state']==='posted_stock_reconciled_financial_proof_pending'
  &&$ok['issue_line_count']===1&&$ok['stock_movement_count']===5
  &&$ok['issued_milli']===6000&&$ok['sold_milli']===4000&&$ok['returned_milli']===2000,
  'canonical daily issue 6, sold 4, returned 2 double custody ledger read-only reconcile');
checkField($ok['canonical_gl_line_totals_match']===true
    &&$ok['journal_line_count']===5
    &&$ok['canonical_gl_totals_paise']['cash_debit_paise']===15000
    &&$ok['canonical_gl_totals_paise']['upi_debit_paise']===25000
    &&$ok['canonical_gl_totals_paise']['sales_credit_paise']===40000,
    'posted cash/UPI debit, sales credit, COGS and inventory equal canonical GL amounts');
checkField($ok['ready_for_production_financial_signoff']===false
    &&$ok['journal_amounts_independently_verified']===false
    &&$ok['physical_employee_cash_handover_verified']===false
    &&$ok['upi_bank_settlement_verified']===false,
    'no physical cash, independent bank, GL-line or production-readiness claims');
blockedField(fn()=>Audit::inspect($wrongCompany,62,$source),'daily_not_found');
blockedField(fn()=>Audit::inspect($wrongBranch,62,$source),'branch_forbidden');
blockedField(fn()=>Audit::inspect($noFinance,62,$source),'permission_denied');
blockedField(fn()=>Audit::inspect($finance,0,$source),'daily_cycle_invalid');

$a=clone $source;$a->movements[2]['quantity']='5.000';
$r=Audit::inspect($finance,62,$a);
checkField($r['state']==='blocked_integrity_exception'
    &&in_array('stock_ledger_quantity_mismatch',$r['exceptions'],true)
    &&count($r['movement_differences'])===1,
    'sale OUT movement overstates actual sold stock and blocks whole cycle');
$a=clone $source;$a->movements[]=$a->movements[3];$a->movements[5]['id']='88';
checkField(Audit::inspect($finance,62,$a)['state']==='blocked_integrity_exception',
    'second duplicate stock-return OUT movement cannot be silently netted');
$a=clone $source;$a->movements[0]['custodian_employee_id']=99;
checkField(Audit::inspect($finance,62,$a)['state']==='blocked_integrity_exception',
    'issue movement to foreign custodian is a discrepancy');
$a=clone $source;$a->movements[0]['branch_id']='32';
blockedField(fn()=>Audit::inspect($finance,62,$a),'field_audit_source_invalid');
$a=clone $source;$a->movements[1]['id']='1';
blockedField(fn()=>Audit::inspect($finance,62,$a),'field_audit_source_invalid');
$a=clone $source;$a->closingLines[0]['wholesale_quantity']='1.001';
checkField(in_array('closing_quantity_mismatch',Audit::inspect($finance,62,$a)['exceptions'],true),
    '1 milli-unit over allocated closing exposes tampered return/sales reconciliation');
$a=clone $source;$a->closingLines[0]['batch_id']=19;
checkField(in_array('closing_product_batch_mismatch',Audit::inspect($finance,62,$a)['exceptions'],true),
    'cross-batch return cannot masquerade as original issued stock');
$a=clone $source;$a->closingLines[]=$a->closingLines[0];
blockedField(fn()=>Audit::inspect($finance,62,$a),'field_audit_source_invalid');
$a=clone $source;$a->issues[0]['quantity']='6.0001';
blockedField(fn()=>Audit::inspect($finance,62,$a),'field_audit_source_invalid');
$a=clone $source;$a->closing[0]['cash_amount']='250.00';
checkField(in_array('cash_upi_reported_totals_mismatch',Audit::inspect($finance,62,$a)['exceptions'],true),
    'Cash + UPI reported settlement mismatch is blocked without claiming cashier verification');
$a=clone $source;$a->journals=[];
checkField(in_array('canonical_journal_header_missing_or_duplicate',Audit::inspect($finance,62,$a)['exceptions'],true),
    'completed cycle without canonical journal header fails');
$a=clone $source;$a->performance=[];
checkField(in_array('employee_performance_record_missing_or_duplicate',Audit::inspect($finance,62,$a)['exceptions'],true),
    'completed cycle without linked employee points/performance fails');
$a=clone $source;$a->journals[]=$a->journals[0];
checkField(in_array('canonical_journal_header_missing_or_duplicate',Audit::inspect($finance,62,$a)['exceptions'],true),
    'duplicate posted canonical GL headers fail closed');
$a=clone $source;$a->glLines[0]['debit']='149.00';
checkField(in_array('gl_cash_debit_mismatch',Audit::inspect($finance,62,$a)['exceptions'],true)
    &&!Audit::inspect($finance,62,$a)['canonical_gl_line_totals_match'],
    'reported cash differs by one rupee from canonical GL Cash debit');
$a=clone $source;$a->glLines[1]['debit']='249.00';
checkField(in_array('gl_upi_debit_mismatch',Audit::inspect($finance,62,$a)['exceptions'],true),
    'posted UPI debit is not proof when GL amount is short');
$a=clone $source;$a->glLines[2]['credit']='399.00';
checkField(in_array('gl_sales_credit_mismatch',Audit::inspect($finance,62,$a)['exceptions'],true),
    'short Sales credit cannot be accepted even if stock movements reconcile');
$a=clone $source;$a->glLines[3]['debit']='199.00';
checkField(in_array('gl_cogs_inventory_mismatch',Audit::inspect($finance,62,$a)['exceptions'],true),
    'COGS debit and Inventory credit cannot differ');
$a=clone $source;$a->glLines[0]['account_company_id']='99';
checkField(in_array('gl_foreign_or_duplicate_line',Audit::inspect($finance,62,$a)['exceptions'],true),
    'cross-company cash ledger account cannot satisfy journal reconciliation');
$a=clone $source;$a->glLines[]=$a->glLines[1];$a->glLines[5]['id']='999';
checkField(in_array('gl_unknown_or_duplicate_account_role',Audit::inspect($finance,62,$a)['exceptions'],true),
    'extra UPI debit line cannot be double counted');
$a=clone $source;$a->glLines[1]['credit']='1.00';
checkField(in_array('gl_invalid_debit_credit_direction',Audit::inspect($finance,62,$a)['exceptions'],true),
    'journal line with simultaneous debit and credit is rejected');
$a=clone $source;$a->glLines=[];
checkField(in_array('gl_lines_missing',Audit::inspect($finance,62,$a)['exceptions'],true),
    'posted journal header without journal lines fails closed');
$a=clone $source;$a->glLines=array_fill(0,21,$a->glLines[0]);
blockedField(fn()=>Audit::inspect($finance,62,$a),'field_audit_incomplete');
$a=clone $source;$a->cycle['status']='issued';$a->closing=[];$a->closingLines=[];$a->journals=[];$a->performance=[];
$a->movements=array_slice($a->movements,0,2);
$r=Audit::inspect($finance,62,$a);
checkField($r['state']==='open_cycle_not_finalized'&&$r['stock_ledger_reconciled']===true
    &&$r['ready_for_production_financial_signoff']===false,
    'issued stock reconciles but open cycle is never treated as posted sales or finance signoff');
$a=clone $source;$a->cycle['status']='issued';$a->closing=[];$a->closingLines=[];$a->journals=[];$a->performance=[];
checkField(in_array('stock_ledger_quantity_mismatch',Audit::inspect($finance,62,$a)['exceptions'],true),
    'ledger sale OUT before completion explicitly blocked');
$a=clone $source;$a->issues=array_fill(0,251,$a->issues[0]);
blockedField(fn()=>Audit::inspect($finance,62,$a),'field_audit_incomplete');
$a=clone $source;$a->movements=array_fill(0,3001,$a->movements[0]);
blockedField(fn()=>Audit::inspect($finance,62,$a),'field_audit_incomplete');
echo "DAILY FIELD STOCK AUDIT: {$checks}/{$checks} PASS\n";
