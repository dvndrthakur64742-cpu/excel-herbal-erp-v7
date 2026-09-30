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
 'legacy_draft_runs',
 'duplicate_active_role_names',
 'duplicate_active_designation_names',
]:
 assert metric in maintenance,('missing operational diagnostics metric',metric)
assert "($critical+$operational)===0?'healthy':'attention'" in maintenance,'operational anomalies do not affect diagnostics status'
print('PASS operational diagnostics anomaly coverage')
schema=(root/'src/Database/Schema.php').read_text()
assert "7.3.5-business-fixes-2" in schema,'schema version was not advanced for checkout exception migration'
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
 'daily_cancel_return',
 'attendance.checkout_missing_acknowledged',
 'access.role_deactivate_duplicate',
 'organization.designation_deactivate_duplicate',
]:
 assert token in maintenance,('missing safe UAT cleanup invariant',token)
assert "checkout_exception=0" in maintenance,'acknowledged missing checkout still counted as unresolved'
dispatch=(root/'src/Http/ApiDispatch.php').read_text()
assert "MaintenanceService::cleanup($a,self::arrBody($r))" in dispatch,'maintenance cleanup payload is not dispatched'
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
contract=json.loads((root/'API-CONTRACT-7.3.5.json').read_text())
assert len(contract['routes'])==len(rows)
print('PASS generated contract count and JSON')
fixtures=json.loads((root/'tests/payroll-fixtures.json').read_text());assert len(fixtures)==21
print('PASS 21 fixture records parse; PHP execution NOT performed by this script')
if len(sys.argv)>1:
 base=Path(sys.argv[1]);old=set(re.findall(r"\['(GET|POST)','([^']+)','([^']+)',(true|false)\]",(base/'src/Http/RouteRegistry.php').read_text()))
 assert old<=set(rows),'existing route lost';print(f'PASS all {len(old)} original routes retained')
if len(sys.argv)>2:balanced(Path(sys.argv[2]));print('PASS setup assistant lexical delimiter scan (NOT PHP lint)')