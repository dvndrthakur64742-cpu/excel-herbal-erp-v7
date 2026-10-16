"""Source checks only. This is not a PHP parser, linter, or runtime test."""
import re,json,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
def balanced(path):
 s=path.read_text();stack=[];i=0
 while i<len(s):
  if s.startswith('//',i) or s[i]=='#':
   end=s.find('\n',i);i=len(s) if end<0 else end+1;continue
  if s.startswith('/*',i):
   end=s.find('*/',i+2);assert end>=0,(path,'unclosed comment');i=end+2;continue
  if s[i] in "'\"`":
   quote=s[i];i+=1
   while i<len(s):
    if s[i]=='\\':i+=2;continue
    if s[i]==quote:i+=1;break
    i+=1
   else:raise AssertionError((path,'unclosed string'))
   continue
  c=s[i]
  if c in '([{':stack.append(c)
  elif c in ')]}':assert stack and stack.pop()=={')':'(',']':'[','}':'{'}[c],(path,'unbalanced delimiter',i)
  i+=1
 assert not stack,(path,'unclosed delimiters')
files=list((root/'src').rglob('*.php'))+[root/'excel-herbal-erp-v7.php']+list((root/'tests').glob('*.php'))
for p in files:balanced(p)
print(f'PASS lexical delimiter scan: {len(files)} PHP files (NOT PHP lint)')
s=(root/'src/Http/RouteRegistry.php').read_text()
rows=re.findall(r"\['(GET|POST)','([^']+)','([^']+)',(true|false)\]",s)
assert len(rows)==len(set((r[0],r[1]) for r in rows)),'duplicate routes'
api=(root/'src/Http/Api.php').read_text()+(root/'src/Http/ApiDispatch.php').read_text()
assert all("'"+handler+"'=>" in api for _,_,handler,_ in rows),'missing dispatch handler'
dispatch=(root/'src/Http/ApiDispatch.php').read_text()
dispatch_defs=set(re.findall(r"function\s+([A-Za-z0-9_]+)\s*\(",dispatch))
dispatch_calls=set(re.findall(r"self::([A-Za-z0-9_]+)\s*\(",dispatch))
assert dispatch_calls<=dispatch_defs,('dispatcher self-call helper missing',sorted(dispatch_calls-dispatch_defs))
print(f'PASS {len(rows)} unique route definitions and dispatch mappings')
org_facade=(root/'src/Organization/OrganizationService.php').read_text()
fin_facade=(root/'src/Finance/FinanceService.php').read_text()
assert 'Db::' not in org_facade and 'Transaction::' not in org_facade,'Organization facade contains database/business implementation'
assert 'Db::' not in fin_facade and 'Transaction::' not in fin_facade,'Finance facade contains database/business implementation'
for rel in [
 'src/Organization/OrganizationBranchService.php',
 'src/Organization/OrganizationEmployeeService.php',
 'src/Organization/OrganizationProductService.php',
 'src/Organization/OrganizationMasterDataService.php',
 'src/Finance/FinanceAccountService.php',
 'src/Finance/FinanceExpenseService.php',
 'src/Finance/FinanceClosingService.php',
 'src/Finance/FinancePeriodService.php',
 'src/Finance/FinanceBankService.php',
 'src/Finance/FinanceReversalService.php',
 'src/Http/ApiDispatch.php',
]:
 assert (root/rel).is_file(),('missing extracted backend service',rel)
assert "return ApiDispatch::dispatch(" in (root/'src/Http/Api.php').read_text(),'Api transport does not delegate to ApiDispatch'
assert "return match($h)" in (root/'src/Http/ApiDispatch.php').read_text(),'ApiDispatch handler map missing'
print('PASS backend facade boundaries and extracted service files')
maintenance=(root/'src/Administration/MaintenanceService.php').read_text()
for metric in [
 'open_past_without_checkout',
 'stale_non_completed_cycles',
 'legacy_distribution_snapshot_mismatches',
 'legacy_draft_runs',
 'duplicate_active_role_names',
 'duplicate_active_designation_names',
]:
 assert metric in maintenance,('missing operational diagnostics metric',metric)
assert "($critical+$operational)===0?'healthy':'attention'" in maintenance,'operational anomalies do not affect diagnostics status'
print('PASS operational diagnostics anomaly coverage')
schema=(root/'src/Database/Schema.php').read_text()
assert "7.3.5-report-reviews-2" in schema,'schema version was not advanced for Accounts review snapshot storage'
for token in [
 "ensureIndex('employees','branch_status'",
 "ensureIndex('parties','branch_type_status'",
 "ensureIndex('counter_sales','branch_date'",
 "ensureIndex('counter_sales','branch_status_outstanding'",
 "ensureIndex('purchase_bills','branch_status_outstanding'",
 "ensureIndex('stock_transfers','source_status'",
 "ensureIndex('stock_transfers','destination_status'",
 "ensureIndex('journal_entries','company_status_date'",
 "ensureIndex('journal_entries','company_source'",
 "ensureIndex('tasks','employee_status_due'",
 "ensureIndex('notifications','employee_created'",
 "ensureIndex('holidays','scope_date'",
]:
 assert token in schema,('missing large-data performance index',token)
assert 'information_schema.statistics' in schema,'performance index migration is not idempotent'
print('PASS large-data hot-path index migration')
review_service=(root/'src/Reporting/ReportReviewService.php').read_text()
for token in [
 'Capabilities::REPORT_REVIEW',
 "'report_review_maker_checker'",
 "'report_snapshot_stale'",
 "ReportingService::trialBalance",
 "ReportingService::profitLoss",
 "ReportingService::balanceSheet",
 "ReportingService::stockReconciliation",
 "ReportingService::financeReconciliation",
]:
 assert token in review_service,('missing report review workflow invariant',token)
assert "'report_reviews'" in schema,'report review persistence table missing'
assert "finance.report.review" in (root/'src/Security/Capabilities.php').read_text(),'report review capability missing'
print('PASS Accounts report review capability, snapshot and maker-checker contracts')
for token in [
 'checkout_exception',
 'checkout_exception_reason',
 'checkout_exception_by',
 'checkout_exception_at',
]:
 assert token in schema,('missing attendance checkout exception schema field',token)
maintenance=(root/'src/Administration/MaintenanceService.php').read_text()
for token in [
 'resolve_uat_anomalies',
 'RESOLVE_UAT_ANOMALIES',
 'repair_daily_commercial_snapshots',
 'REPAIR_DAILY_COMMERCIAL_SNAPSHOTS',
 'maintenance.daily_commercial_snapshot_repair',
 'daily_cancel_return',
 'attendance.checkout_missing_acknowledged',
 'access.role_deactivate_duplicate',
 'organization.designation_deactivate_duplicate',
]:
 assert token in maintenance,('missing safe UAT cleanup invariant',token)
assert "checkout_exception=0" in maintenance,'acknowledged missing checkout still counted as unresolved'
dispatch=(root/'src/Http/ApiDispatch.php').read_text()
assert "MaintenanceService::cleanup($a,self::arrBody($r))" in dispatch,'maintenance cleanup payload is not dispatched'
api=(root/'src/Http/Api.php').read_text()
assert "['admin.transfer_accounting_repair','admin.cleanup']" in api,'admin cleanup body idempotency fallback is missing'
print('PASS safe UAT anomaly cleanup wiring')
admin_cleanup=(root/'src/Administration/UatCleanupAdmin.php').read_text()
for token in [
 "current_user_can('manage_options')",
 "check_admin_referer(self::ACTION)",
 "ActorResolver::current()",
 "MaintenanceService::cleanup($actor",
 "'confirmation'=>'RESOLVE_UAT_ANOMALIES'",
]:
 assert token in admin_cleanup,('unsafe or incomplete WordPress admin UAT cleanup bridge',token)
plugin=(root/'src/Core/Plugin.php').read_text()
assert 'UatCleanupAdmin::boot();' in plugin,'WordPress admin UAT cleanup bridge is not booted'
print('PASS nonce-protected WordPress admin UAT cleanup bridge')
web_deploy=(root/'src/Administration/UatWebDeployAdmin.php').read_text()
for token in [
 "current_user_can('manage_options')",
 "check_admin_referer(self::ACTION)",
 "ActorResolver::current()",
 "Guard::cap($actor,Capabilities::ACCESS_MANAGE)",
 "SHA256SUMS.txt",
 "hash_file('sha256'",
 "rename($target,$backup)",
 "Audit::add($actor,'administration.uat_web_deploy'",
]:
 assert token in web_deploy,('unsafe or incomplete UAT web deployment workflow',token)
assert 'UatWebDeployAdmin::boot();' in plugin,'UAT web deployment admin workflow is not booted'
print('PASS audited rollback-safe UAT web deployment workflow')
reversal=(root/'src/Finance/FinanceReversalService.php').read_text()
for token in [
 "self::sourceStatus($a,$type,$source)!==$required",
 "'reversal_source_state_changed'",
 "Audit::add($a,'reversal.'.($approve?'approve':'reject')",
]:
 assert token in reversal,('missing reversal lifecycle integrity guard',token)
purchase=(root/'src/Purchase/PurchaseService.php').read_text()
assert "Audit::add($a,'supplier_payment.post'" in purchase,'supplier payment is not audited'
expense=(root/'src/Finance/FinanceExpenseService.php').read_text()
assert "Audit::add($a,'expense.'.($approve?'approve':'reject')" in expense,'expense decision is not audited'
print('PASS financial lifecycle state recheck and audit coverage')
workforce=(root/'src/Workforce/WorkforceService.php').read_text()
for token in [
 "'field_visit_purpose_invalid'",
 "Audit::add($a,'leave.request'",
]:
 assert token in workforce,('missing workforce invariant/audit',token)
check_in = workforce.split("public static function checkIn(", 1)[1].split("public static function checkOut(", 1)[0]
for token in [
 "$lat===null||$lng===null",
 "'gps_location_required'",
]:
 assert token in check_in,('check-in must reject missing GPS coordinates before writing attendance',token)
assert check_in.index("Guard::branch") < check_in.index("'gps_location_required'"), 'check-in must enforce branch authority before location validation'
communication=(root/'src/Communication/CommunicationService.php').read_text()
for token in [
 "FOR UPDATE",
 "'task_state_invalid'",
 "Audit::add($a,'task.complete'",
]:
 assert token in communication,('missing task completion state control',token)
bank=(root/'src/Finance/FinanceBankService.php').read_text()
for token in [
 "Audit::add($a,'bank_reconciliation.import'",
 "Audit::add($a,'bank_line.match'",
 "Audit::add($a,'bank_reconciliation.finalize'",
]:
 assert token in bank,('missing bank reconciliation audit event',token)
closing=(root/'src/Finance/FinanceClosingService.php').read_text()
for token in [
 "Audit::add($a,'branch_closing.draft'",
 "Audit::add($a,'branch_closing.close'",
]:
 assert token in closing,('missing branch closing audit event',token)
print('PASS workforce, task, bank and branch-closing control coverage')
daily=(root/'src/DailyOrder/DailyOrderService.php').read_text()
for token in [
 "Audit::add($a,'daily_order.submit'",
 "Audit::add($a,'daily_order.approve'",
 "Audit::add($a,'daily_order.issue'",
 "Audit::add($a,'daily_order.evening_start'",
 "Audit::add($a,'daily_order.evening_save'",
 "Audit::add($a,'daily_order.evening_submit'",
]:
 assert token in daily,('missing Daily Order lifecycle audit event',token)
inventory=(root/'src/Inventory/InventoryService.php').read_text()
for token in [
 "stock_quarantine.'.$action",
 "'quarantine_state_invalid'",
 "FOR UPDATE",
]:
 assert token in inventory,('missing quarantine resolution control',token)
print('PASS Daily Order lifecycle audit and quarantine resolution controls')
quarantine=(root/'src/Inventory/InventoryService.php').read_text()
for token in [
 'function quarantineHold',
 "'stock_quarantine.hold'",
 "'stock_quarantine_writeoff'",
]:
 assert token in quarantine,('missing end-to-end quarantine workflow control',token)
accounting=(root/'src/Finance/AccountingService.php').read_text()
assert "'stock_quarantine_writeoff'=>'stock_quarantine'" in accounting,'quarantine write-off journal source missing'
reporting=(root/'src/Reporting/ReportingService.php').read_text()
assert "q.quantity*q.unit_cost_snapshot" in reporting,'open quarantine value missing from finance reconciliation'
for token in ["unit_cost_snapshot","journal_entry_id"]:
 assert token in schema,('missing quarantine valuation schema field',token)
print('PASS quarantine hold/release/write-off valuation workflow')
performance=(root/'src/Payroll/PayrollPerformanceService.php').read_text()
approve_target=performance[performance.index('public static function approveTarget'):performance.index('/** Query data separately')]
for token in ["Transaction::run","FOR UPDATE","'target_state_invalid'","'maker_checker_required'"]:
 assert token in approve_target,('performance target approval is not concurrency-safe',token)
periods=(root/'src/Finance/FinancePeriodService.php').read_text()
reopen=periods[periods.index('public static function reopenPeriod'):]
for token in ["Transaction::run","FOR UPDATE","'period_state_invalid'"]:
 assert token in reopen,('accounting period reopen is not concurrency-safe',token)
print('PASS performance target and accounting period state-transition locking')
branches=(root/'src/Organization/OrganizationBranchService.php').read_text()
branch_status=branches[branches.index('public static function setBranchStatus'):]
for token in ["Transaction::run","FOR UPDATE","open_quarantine","pending_stock_adjustments","pending_expenses","pending_reversals","open_payroll"]:
 assert token in branch_status,('branch deactivation lifecycle guard missing',token)
print('PASS branch deactivation transactional lifecycle coverage')
branch_service=(root/'src/Organization/OrganizationBranchService.php').read_text()
authority=branch_service[branch_service.index('public static function setBranchAuthority'):branch_service.index('public static function updateBranch')]
for token in ["Transaction::run","FOR UPDATE","'employee_inactive'","'primary_branch_authority_inherent'","valid_until"]:
 assert token in authority,('branch authority mutation/semantics are not safe',token)
print('PASS branch authority grant/revoke locking and validity window')
products=(root/'src/Organization/OrganizationProductService.php').read_text()
update_product=products[products.index('public static function updateProduct'):products.index('public static function setProductStatus')]
for token in ["Transaction::run","FOR UPDATE","'product_structure_locked'"]:
 assert token in update_product,('product structure update is not transaction-safe',token)
stock_service=(root/'src/Inventory/StockService.php').read_text()
move=stock_service[stock_service.index('public static function move'):stock_service.index('public static function automaticCustodyAllocations')]
for token in ["FOR UPDATE","status='active'","validateBatch"]:
 assert token in move,('stock movement does not synchronize with product structure/status',token)
print('PASS product structure and stock movement lock symmetry')
employees=(root/'src/Organization/OrganizationEmployeeService.php').read_text()
for method,next_method in [
 ('public static function createEmployee','public static function setEmployeeCredentials'),
 ('public static function reactivateEmployee','public static function setReportingManager'),
 ('public static function offboardEmployee','private static function offboardingBlockers'),
]:
 section=employees[employees.index(method):employees.index(next_method)]
 assert 'SalaryService::lockCompany' in section,('employee/payroll lifecycle mutation lacks company lock',method)
for token in ["'employee_create_payroll_conflict'","'employee_reactivate_payroll_conflict'","'payroll_period_conflict'"]:
 assert token in employees,('missing workforce/payroll period conflict guard',token)
print('PASS workforce lifecycle and payroll scope synchronization')
employee_service=(root/'src/Organization/OrganizationEmployeeService.php').read_text()
reporting=employee_service[employee_service.index('public static function setReportingManager'):employee_service.index('public static function offboardingPreflight')]
for token in ["SalaryService::lockCompany","FOR UPDATE","'reporting_cycle'"]:
 assert token in reporting,('reporting hierarchy mutation is not concurrency-safe',token)
print('PASS reporting hierarchy concurrency serialization')
branch_service=(root/'src/Organization/OrganizationBranchService.php').read_text()
create_branch=branch_service[branch_service.index('public static function createBranch'):branch_service.index('public static function setBranchAuthority')]
for token in ["Transaction::run","Db::table('companies')","FOR UPDATE","'head_office_exists'"]:
 assert token in create_branch,('single Head Office invariant is not concurrency-safe',token)
print('PASS single Head Office branch concurrency guard')
employees=(root/'src/Organization/OrganizationEmployeeService.php').read_text()
credentials=employees[employees.index('public static function setEmployeeCredentials'):employees.index('public static function employeeLoginStatus')]
for token in ["Transaction::run","FOR UPDATE","status='active'","employee.login_credentials_reset"]:
 assert token in credentials,('employee credential reset is not offboarding-safe',token)
print('PASS employee credential reset/offboarding serialization')
hr=(root/'src/Organization/HrLifecycleService.php').read_text()
candidate_credentials=hr[hr.index('public static function issueCandidateCredentials'):hr.index('public static function markNoShow')]
for token in ["Transaction::run","FOR UPDATE","'candidate_credentials_already_issued'","OrganizationService::setEmployeeCredentials"]:
 assert token in candidate_credentials,('candidate credential issuance is not concurrency-safe',token)
print('PASS candidate credential issuance locking')
access_service=(root/'src/Security/AccessService.php').read_text()
overrides=access_service[access_service.index('public static function setEmployeeOverrides'):]
for token in ["Capabilities::ACCESS,Capabilities::ACCESS_MANAGE","'self_access_lockout'"]:
 assert token in overrides,('self access override lockout guard incomplete',token)
print('PASS self access/access-management override lockout coverage')
hierarchy_scope=(root/'src/Security/HierarchyScope.php').read_text()
branch_authority=(root/'src/Security/BranchAuthority.php').read_text()
access_service=(root/'src/Security/AccessService.php').read_text()
branch_service=(root/'src/Organization/OrganizationBranchService.php').read_text()
employee_service=(root/'src/Organization/OrganizationEmployeeService.php').read_text()
for token in ["manageableEmployeeIds","assertCanManageEmployeeAccess","hasCompanyWideSystemAuthority","'employee_access_scope_forbidden'"]:
 assert token in hierarchy_scope,('missing central hierarchy access-management guard',token)
for token in ["isCompanyWideAdmin","Capabilities::ACCESS_MANAGE","role_capabilities"]:
 assert token in branch_authority,('company-wide system authority is not centrally constrained',token)
for token in ["assertCanDelegateCapabilities","assertRoleWithinAuthority","assertCanAdministerEmployeeIdentity","'reserved_system_role_forbidden'","'role_scope_forbidden'","'authority_escalation_forbidden'"]:
 assert token in access_service,('missing anti-escalation access guard',token)
for token in ["assertCanManageEmployeeAccess($a,$employeeId)","hasCompanyWideSystemAuthority($a)"]:
 assert token in branch_service,('branch authority mutation is not hierarchy/system scoped',token)
for token in ["AccessService::assertCanDelegateCapabilities","AccessService::assertCanAdministerEmployeeIdentity","HierarchyScope::assertCanManageEmployeeAccess"]:
 assert token in employee_service,('employee mutation is not authority scoped',token)
print('PASS hierarchy-scoped authority hardening and reserved-role controls')
employee_service=(root/'src/Organization/OrganizationEmployeeService.php').read_text()
designation_off=employee_service[employee_service.index('public static function deactivateEmployeeDesignation'):]
for token in ["Transaction::run","FOR UPDATE","'unchanged'=>true"]:
 assert token in designation_off,('designation deactivation is not idempotent/locked',token)
hr_service=(root/'src/Organization/HrLifecycleService.php').read_text()
candidate_doc_off=hr_service[hr_service.index('public static function deactivateCandidateDocument'):hr_service.index('public static function separations')]
for token in ["Transaction::run","FOR UPDATE","'unchanged'=>true"]:
 assert token in candidate_doc_off,('candidate document deactivation is not idempotent/locked',token)
print('PASS idempotent locked deactivation transitions')
documents=(root/'src/Organization/DocumentService.php').read_text()
deactivate_doc=documents[documents.index('public static function deactivate'):]
for token in ["Transaction::run","FOR UPDATE","'unchanged'=>true"]:
 assert token in deactivate_doc,('employee document deactivation is not idempotent/locked',token)
print('PASS employee document deactivation locking')
closing=(root/'src/Finance/FinanceClosingService.php').read_text()
reopen=closing[closing.index('public static function reopenBranch'):]
for token in ["Transaction::run","FOR UPDATE","'closing_state_invalid'"]:
 assert token in reopen,('branch closing reopen is not concurrency-safe',token)
print('PASS branch closing reopen state locking')
holidays=(root/'src/Workforce/HolidayService.php').read_text()
for token in ["SalaryService::lockCompany","'holiday_payroll_conflict'","Transaction::run","FOR UPDATE","'unchanged'=>true","self::companyWide($a)"]:
 assert token in holidays,('holiday/payroll calendar or scope guard missing',token)
print('PASS holiday calendar/payroll synchronization')
contract=json.loads((root/'API-CONTRACT-7.3.5.json').read_text())
assert len(contract['routes'])==len(rows)
print('PASS generated contract count and JSON')
fixtures=json.loads((root/'tests/payroll-fixtures.json').read_text());assert len(fixtures)==21
print('PASS 21 fixture records parse; PHP execution NOT performed by this script')
if len(sys.argv)>1:
 base=Path(sys.argv[1]);old=set(re.findall(r"\['(GET|POST)','([^']+)','([^']+)',(true|false)\]",(base/'src/Http/RouteRegistry.php').read_text()))
 assert old<=set(rows),'existing route lost';print(f'PASS all {len(old)} original routes retained')
if len(sys.argv)>2:balanced(Path(sys.argv[2]));print('PASS setup assistant lexical delimiter scan (NOT PHP lint)')