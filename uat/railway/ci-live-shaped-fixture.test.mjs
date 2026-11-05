import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const load=(name)=>readFileSync(fileURLToPath(new URL(name,import.meta.url)),'utf8');
const fixture=load('./ci-live-shaped-fixture.php');
const historicIndexes=load('./ci-live-only-indexes.php');
const rehearsal=load('./ci-additive-upgrade-rehearsal.php');
const ci=load('./ci-wordpress-smoke.sh');

test('live-shaped dummy fixture is impossible to run on Office or persistent UAT',()=>{
  assert.match(fixture,/EH7_CI_ISOLATED/);
  assert.match(fixture,/wp_get_environment_type\(\)\s*!==\s*'staging'/);
  assert.match(fixture,/eh7_ci_synthetic/);
  assert.match(fixture,/eh7-ci-mariadb-/);
  assert.match(rehearsal,/source_head_match/);
  assert.match(rehearsal,/synthetic_only/);
  assert.doesNotMatch(fixture,/office\.excelherbal\.in|password|access_token|refresh_token/i);
});

test('three live-only reports have exact typed columns and are given synthetic rows',()=>{
  for(const t of ['report_reminder_drafts','report_submissions','report_submission_events']){
    assert.match(fixture,new RegExp("'"+t+"'\\s*=>"));
    assert.match(rehearsal,new RegExp("'"+t+"'"));
  }
  assert.match(fixture,/UNIQUE KEY uniq_draft_key/);
  assert.match(fixture,/UNIQUE KEY uniq_report/);
  assert.match(fixture,/UNIQUE KEY one_event/);
  assert.match(fixture,/Dummy test report/);
  assert.match(rehearsal,/eh7_ci_snapshot\(\$preservedTables\)/);
  assert.match(rehearsal,/Live-only synthetic report or its row lost/);
});

test('stock quarantine live extra columns and synthetic financial snapshot preserved',()=>{
  assert.match(fixture,/unit_cost_snapshot DECIMAL\(14,4\) NOT NULL DEFAULT 0\.0000/);
  assert.match(fixture,/journal_entry_id BIGINT UNSIGNED NULL/);
  assert.match(fixture,/12\.3400/);
  assert.match(rehearsal,/stock_quarantine/);
  assert.match(rehearsal,/Live-only stock quarantine columns\/data were not preserved/);
});

test('missing employee_device index added by real dbDelta, extra branch index survives',()=>{
  assert.match(fixture,/DROP INDEX employee_device/);
  assert.match(historicIndexes,/'branch_status'=>\['company_id','assigned_branch_id','status'\]/);
  assert.match(rehearsal,/Schema::maybeUpgrade\(\)/);
  assert.match(rehearsal,/Schema::install\(\)/);
  assert.match(rehearsal,/Missing required mobile session composite index after upgrade/);
  assert.match(rehearsal,/Live-only employee lookup index was dropped\/changed/);
  assert.match(rehearsal,/eh7_ci_assert_live_shape_upgraded\(\$prefix\)/);
  // MariaDB SHOW INDEX does not support an ORDER BY clause.
  assert.doesNotMatch(rehearsal,/SHOW INDEX[^"\n]*ORDER BY Seq_in_index/i);
  assert.match(rehearsal,/usort\(\$sessionIndex/);
  assert.match(rehearsal,/usort\(\$employeeIndex/);
});

test('Docker runner copies synthetic fixture only into temporary CI container',()=>{
  assert.match(ci,/docker cp uat\/railway\/ci-live-only-indexes\.php/);
  assert.match(ci,/docker cp uat\/railway\/ci-live-shaped-fixture\.php/);
  assert.match(ci,/\/tmp\/eh7-ci-live-shaped-fixture\.php/);
  assert.match(rehearsal,/require '\/tmp\/eh7-ci-live-shaped-fixture\.php'/);
  assert.match(ci,/docker rm -f "\$wp_container" "\$db_container"/);
  assert.match(ci,/docker network rm "\$network"/);
});

test('one active synthetic mobile session survives migration, authenticates, then is cleaned',()=>{
  assert.match(fixture,/CI-MIGRATION-DUMMY-ACCESS/);
  assert.match(fixture,/refresh_expires_at/);
  assert.match(fixture,/time\(\)\+86400/);
  assert.match(rehearsal,/Existing active synthetic session revoked or lost during migration/);
  assert.match(rehearsal,/MobileAuth::user\(0\)/);
  assert.match(rehearsal,/Synthetic active session not cleaned before follow-up REST tests/);
  assert.match(rehearsal,/\$wpdb->delete\(\$sessionTable/);
  assert.match(rehearsal,/eh7_ci_snapshot\(\$preservedTables\)/);
});

test('all 16 Office-only nonunique lookup indexes are simulated and preserved',()=>{
  // These are all observed, nonunique indexes; no passwords or data rows.
  const pairs=[...historicIndexes.matchAll(/'([a-z_]+)'=>\[/g)].map(x=>x[1]);
  assert.equal(pairs.length,16);
  for(const n of ['destination_status','source_status','branch_type_status',
    'branch_date','branch_status_outstanding','company_source',
    'company_status_date','employee_status_due','company_status_published',
    'employee_created']) {
    assert.ok(pairs.includes(n),n);
  }
  assert.match(fixture,/eh7_ci_live_only_index_map\(\)/);
  assert.match(fixture,/Refuse to overwrite source index/);
  assert.match(fixture,/ADD KEY '\.\$name/);
  assert.match(rehearsal,/Incomplete historical Office index preservation/);
  assert.match(rehearsal,/Historical Office lookup index changed/);
  assert.match(rehearsal,/NON_UNIQUE/);
});
