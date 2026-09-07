<?php
require __DIR__.'/../backend/excel-herbal-erp-v7/src/Policy/BusinessPolicy.php';
require __DIR__.'/../backend/excel-herbal-erp-v7/src/Security/BranchScope.php';
use ExcelHerbal\ERP7\Policy\BusinessPolicy;
use ExcelHerbal\ERP7\Security\BranchScope;
$assert=function($ok,$m){if(!$ok){fwrite(STDERR,"FAIL $m\n");exit(1);}echo "PASS $m\n";};
$assert(BusinessPolicy::BATCH_MODE==='optional','batch optional');
$assert(!BusinessPolicy::enabled('supplier_return'),'supplier return owner decision');
$assert(!BusinessPolicy::enabled('supplier_advance'),'supplier advance owner decision');
foreach(['treasury_transfer','employee_advance_loan','bad_debt_writeoff','half_day_late_overtime','direct_nonstock_supplier_invoice'] as $feature){$assert(!BusinessPolicy::enabled($feature),$feature.' owner decision');}
$p=BranchScope::projection(5,[5]);$assert($p['selector_visible']===false,'single branch selector hidden');
$p=BranchScope::projection(5,[5,8]);$assert($p['selector_visible']===true,'multi branch selector visible');
$assert($p['branch_ids']===[5,8],'only effective branches projected');
