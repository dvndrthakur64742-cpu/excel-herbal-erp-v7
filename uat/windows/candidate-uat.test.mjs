import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const read=name=>readFileSync(fileURLToPath(new URL('./'+name,import.meta.url)),'utf8');
const create=read('create-candidate-uat.ps1');
const certify=read('certify-candidate-uat.php');
const smoke=read('local-auth-smoke.mjs');

test('candidate is a new local-only WordPress site sourced from verified restore',()=>{
  assert.match(create,/\$dest='D:\\xampp\\htdocs\\erp-uat-candidate'/);
  assert.match(create,/\$repo='D:\\ERP7-UAT-Candidate'/);
  assert.match(create,/\$db='eh7_restore_5ec7b1894f7a'/);
  assert.match(create,/if\(\(Test-Path \$dest\) -or \(Test-Path \$repo\)\)/);
  assert.match(create,/isolated_restore_verified -ne \$true/);
  assert.match(create,/original_row_counts_unchanged -ne \$true/);
  assert.match(create,/Get-NetTCPConnection -State Listen -LocalPort \$port/);
});

test('candidate plugin uses a detached exact Git source with separate DB user',()=>{
  assert.match(create,/git clone --quiet --no-hardlinks --no-checkout \$dev \$repo/);
  assert.match(create,/git -C \$repo checkout --quiet --detach \$head/);
  assert.match(create,/New-Item -ItemType Junction/);
  assert.match(create,/eh7cand_/);
  assert.match(create,/GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP, REFERENCES ON/);
  assert.match(create,/Swap 'DB_NAME' \$db/);
  assert.match(create,/Swap 'EH7_SOURCE_HEAD' \$head/);
  assert.match(create,/DISABLE_WP_CRON/);
  assert.match(create,/finally \{[\s\S]*Remove-Item -LiteralPath \$adminFile/);
});

test('repin tool cannot run on old ERP, live office, another DB or web request',()=>{
  assert.match(certify,/PHP_SAPI !== 'cli'/);
  assert.match(certify,/D:\/xampp\/htdocs\/erp-uat-candidate/);
  assert.match(certify,/D:\/ERP7-UAT-Candidate\/plugin/);
  assert.match(certify,/eh7_restore_5ec7b1894f7a/);
  assert.match(certify,/http:\/\/127\.0\.0\.1:18880\/erp-uat-candidate/);
  assert.match(certify,/realpath\(\$mountedPlugin\) !== realpath\(\$gitPlugin\)/);
  assert.match(certify,/wp_get_environment_type\(\) !== 'staging'/);
  assert.match(certify,/eh7_schema_version/);
});

test('candidate certification requires synthetic source and edits only candidate markers',()=>{
  assert.match(certify,/uat\['synthetic_only'\]/);
  assert.match(certify,/active_mobile_sessions_zero/);
  assert.match(certify,/active_push_devices_zero/);
  assert.match(certify,/admin_employee_present/);
  assert.match(certify,/limited_employee_present/);
  assert.match(certify,/update_option\('eh7_uat_seed_source_head'/);
  assert.match(certify,/StagingSafety::sanitize\(\)/);
  assert.doesNotMatch(certify,/wp_set_password|DELETE FROM|DROP DATABASE|TRUNCATE/);
});

test('synthetic login tool has explicit allowed localhost sites and credential identity guard',()=>{
  assert.match(smoke,/LOCAL_SITES=\[/);
  assert.match(smoke,/127\.0\.0\.1:18880\/erp-uat-candidate/);
  assert.match(smoke,/if\(!LOCAL_SITES\.includes\(SITE\)\)throw/);
  assert.match(smoke,/secret\.website===SITE/);
  assert.match(smoke,/const pinnedCheckout=SITE===LOCAL_SITES\[1\]/);
  assert.match(smoke,/ERP7-UAT-Candidate/);
  assert.match(smoke,/cwd:pinnedCheckout/);
  assert.match(smoke,/assertLocalUatSourcePin/);
  assert.match(smoke,/9000000001/);
  assert.match(smoke,/9000000002/);
});
