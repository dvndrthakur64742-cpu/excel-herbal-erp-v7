import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const load=(name)=>readFileSync(fileURLToPath(new URL(name,import.meta.url)),'utf8');
const fixture=load('./ci-live-shaped-fixture.php');
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
  assert.match(fixture,/ADD KEY branch_status/);
  assert.match(rehearsal,/Schema::maybeUpgrade\(\)/);
  assert.match(rehearsal,/Schema::install\(\)/);
  assert.match(rehearsal,/Missing required mobile session composite index after upgrade/);
  assert.match(rehearsal,/Live-only employee lookup index was dropped\/changed/);
  assert.match(rehearsal,/eh7_ci_assert_live_shape_upgraded\(\$prefix\)/);
});

test('Docker runner copies synthetic fixture only into temporary CI container',()=>{
  assert.match(ci,/docker cp uat\/railway\/ci-live-shaped-fixture\.php/);
  assert.match(ci,/\/tmp\/eh7-ci-live-shaped-fixture\.php/);
  assert.match(rehearsal,/require '\/tmp\/eh7-ci-live-shaped-fixture\.php'/);
  assert.match(ci,/docker rm -f "\$wp_container" "\$db_container"/);
  assert.match(ci,/docker network rm "\$network"/);
});
