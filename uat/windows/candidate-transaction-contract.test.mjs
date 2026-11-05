import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const load=name=>readFileSync(fileURLToPath(new URL('./'+name,import.meta.url)),'utf8');
const preflight=load('candidate-sales-preflight.php');
const tx=load('candidate-prepaid-transactions.php');
const audit=load('candidate-sales-audit.php');
const original=load('original-uat-readonly.php');

test('all candidate financial scripts require CLI, exact candidate DB and Git source',()=>{
  for(const source of [preflight,tx,audit]){
    assert.match(source,/PHP_SAPI\s*!==\s*'cli'/);
    assert.match(source,/D:\/xampp\/htdocs\/erp-uat-candidate\/wp-load\.php/);
    assert.match(source,/eh7_restore_5ec7b1894f7a/);
    assert.match(source,/EH7_CANDIDATE_SOURCE_SHA/);
    assert.match(source,/source|sha/i);
    assert.match(source,/StagingSafety::status\(\)\['sanitized'\]/);
    assert.match(source,/active_mobile_sessions_zero/);
    assert.doesNotMatch(source,/https?:\/\/office\.excelherbal\.in/i);
  }
});

test('one-time B2C candidate test fails closed if baseline changed',()=>{
  assert.match(tx,/oldOrders===5\s*&&\s*\$oldSales===5/);
  assert.match(tx,/oldJournals===7/);
  assert.match(tx,/oldWarehouse-3\.0/);
  assert.match(tx,/business day closed; do not bypass guard/);
  assert.match(tx,/UAT-ADMIN/);
  assert.match(tx,/UAT-BM/);
  assert.match(tx,/cid===1\s*&&\s*\$branch===1/);
});

test('full prepayment Cash and independent UPI verification are tested',()=>{
  assert.match(tx,/full_prepayment_required/);
  assert.match(tx,/40\.00/);
  assert.match(tx,/60\.00/);
  assert.match(tx,/payment_overpaid/);
  assert.match(tx,/upi_verification_required/);
  assert.match(tx,/maker_checker_required/);
  assert.match(tx,/verifyUpi\(\$verifier/);
  assert.match(tx,/upi_payment_state_invalid/);
  assert.match(tx,/idempotent/);
});

test('counter-sales reconcile stock and general ledger and original cycle',()=>{
  assert.match(tx,/getCount\(\$salesTable\)===\$oldSales\+2/);
  assert.match(tx,/getCount\(\$journalTable\)===\$oldJournals\+2/);
  assert.match(tx,/oldWarehouse-2/);
  assert.match(tx,/abs\(\(float\)\$row\['debit'\]-\(float\)\$row\['credit'\]\)/);
  assert.match(audit,/bank_evidence_ref/);
  assert.match(audit,/received_by/);
  assert.match(audit,/verified_by/);
  assert.match(audit,/cycle==='completed'/);
  assert.match(audit,/Warehouse balance did not decrease by 2 units/);
});

test('original localhost audit is read-only and checks preexisting numbers',()=>{
  assert.match(original,/D:\/xampp\/htdocs\/erp-uat\/wp-load\.php/);
  assert.match(original,/eh7_local_uat/);
  assert.match(original,/orders!==5\s*\|\|\s*\$sales!==5\s*\|\|\s*\$journals!==7/);
  assert.match(original,/warehouse-3\.0/);
  assert.doesNotMatch(original,/^\s*(?:update_option|wp_set_password|DROP DATABASE|DELETE FROM|UPDATE\s+wp_|TRUNCATE TABLE)\b/im);
});

test('read-only Windows clock diagnostic blocks excessive skew without changing time',()=>{
  const clock=load('clock-health.ps1');
  assert.match(clock,/Invoke-WebRequest -Uri \$uri -Method Head/);
  assert.match(clock,/https:\/\/api\.github\.com/);
  assert.match(clock,/MaxSkewMinutes=5/);
  assert.match(clock,/DateTimeOffset/);
  assert.match(clock,/if\(\$skewMinutes -gt \$MaxSkewMinutes\)/);
  assert.match(clock,/Attendance\/GPS\/business-date\/settlement UAT/);
  assert.doesNotMatch(clock,/\b(?:Set-Date|Set-TimeZone|Start-Service|Stop-Service|Set-Service|w32tm\s+\/resync|Set-ItemProperty)\b/i);
});
