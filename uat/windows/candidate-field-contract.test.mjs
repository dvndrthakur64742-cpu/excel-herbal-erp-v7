import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const read=name=>readFileSync(fileURLToPath(new URL('./'+name,import.meta.url)),'utf8');
const morning=read('candidate-field-current-day.php');
const receipt=read('candidate-field-issue-receive.php');
const evening=read('candidate-field-evening.php');
const audit=read('candidate-field-audit.php');
const status=read('candidate-field-status.php');

test('field scripts fail closed to one synthetic candidate source and business date',()=>{
 for(const script of [morning,receipt,evening,audit,status]){
  assert.match(script,/PHP_SAPI\s*!==\s*'cli'/);
  assert.match(script,/EH7_CANDIDATE_SOURCE_SHA/);
  assert.match(script,/erp-uat-candidate/);
  assert.match(script,/eh7_restore_5ec7b1894f7a/);
  assert.match(script,/StagingSafety::status\(\)\['sanitized'\]/);
  assert.match(script,/active_mobile_sessions_zero/);
  assert.doesNotMatch(script,/https?:\/\/office\.excelherbal\.in/);
 }
 assert.match(morning,/gmdate\('Y-m-d',time\(\)\+19800\)/);
 for(const script of [receipt,evening,audit]){
  assert.match(script,/2026-11-04/);
 }
});

test('morning GPS gate and 10:30–17:00 duty slot are explicit',()=>{
 assert.match(morning,/current_time\('H:i:s'\)/);
 assert.match(morning,/\$at>='10:30:00'\s*&&\s*\$at<'17:00:00'/);
 assert.match(morning,/AttendanceGpsEvidence::hasVerifiedMorningPoint/);
 assert.match(morning,/daily_attendance_required/);
 assert.match(morning,/RecoveryService::gpsPoint/);
 assert.match(morning,/DailyOrderService::create/);
 assert.match(morning,/DailyOrderService::submit/);
 assert.match(morning,/permission_denied/);
});

test('independent reviewer, BM, receipt, and stock custody boundaries are explicit',()=>{
 assert.match(receipt,/DailyOrderService::review\(\$reviewer,2\)/);
 assert.match(receipt,/DailyOrderService::approve\(\$manager,2\)/);
 assert.match(receipt,/DailyOrderService::issue\(\$manager,2/);
 assert.match(receipt,/DailyOrderService::receive\(\$field,2\)/);
 assert.match(receipt,/maker_checker_required/);
 assert.match(receipt,/daily_receipt_forbidden/);
 assert.match(receipt,/daily_request_state_invalid/);
 assert.match(receipt,/source_type='daily_issue'/);
 assert.match(receipt,/issued'&&abs\(\$wh\(\)\)/);
});

test('evening only posts after reconciled amount and maker checker separation',()=>{
 assert.match(evening,/DailyOrderService::eveningStart/);
 assert.match(evening,/evening_reconciliation_required/);
 assert.match(evening,/DailyOrderService::eveningSave/);
 assert.match(evening,/DailyOrderService::eveningSubmit/);
 assert.match(evening,/0\.0,50\.0,101\.0/);
 assert.match(evening,/payment_mismatch/);
 assert.match(evening,/maker_checker_required/);
 assert.match(evening,/DailyOrderService::finalPost\(\$bm,2,100\.0,0\.0\)/);
 assert.match(evening,/source_type='daily_sale'/);
 assert.match(evening,/Duplicate final posting/);
});

test('read-only audit verifies authority provenance, stock, journals and old invoices',()=>{
 assert.match(audit,/req\['reviewed_by'\]===1/);
 assert.match(audit,/req\['approved_by'\]===3/);
 assert.match(audit,/settled\['reviewed_by'\]===3/);
 assert.match(audit,/AttendanceGpsEvidence::hasVerifiedMorningPoint/);
 assert.match(audit,/return_quantity/);
 assert.match(audit,/source_type='daily_issue'/);
 assert.match(audit,/source_type='daily_sale'/);
 assert.match(audit,/COUNT\(\*\) FROM .*counter_sales/);
 assert.match(audit,/COALESCE\(SUM\(l\.debit\),0\)/);
 assert.doesNotMatch(audit,/\b(?:update_option|Db::mustInsert|Db::mustUpdate|DROP DATABASE|TRUNCATE TABLE|DELETE FROM)\b/i);
});

test('original customer, Live ERP and Windows time services are never modified',()=>{
 for(const script of [morning,receipt,evening,audit,status]){
  assert.doesNotMatch(script,/(?:https?:\/\/office\.excelherbal\.in|D:\/xampp\/htdocs\/erp-uat\/wp-load\.php)/i);
  assert.doesNotMatch(script,/(?:Set-Date|Start-Service|w32tm\s+\/resync|DROP DATABASE|TRUNCATE TABLE)/i);
 }
 assert.match(morning,/count\(\$cycles\)===1/);
 assert.match(receipt,/Wrong.*submitted stock request|Candidate not at exactly expected submitted stock request/);
 assert.match(evening,/Wrong candidate pre-settlement baseline/);
});
