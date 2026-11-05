import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const script=readFileSync(fileURLToPath(new URL('./restore-native-uat.ps1',import.meta.url)),'utf8');

test('restore strictly requires locally backed up synthetic WordPress',()=>{
  assert.match(script,/\$site='http:\/\/127\.0\.0\.1:18880\/erp-uat'/);
  assert.match(script,/eh7-synthetic-checkpoint-/);
  assert.match(script,/\$manifest\.database_name -ne 'eh7_local_uat'/);
  assert.match(script,/\$secret\.site_url -ne \$site/);
  assert.match(script,/\$health\.data\.uat_bootstrap\.synthetic_only -ne \$true/);
  assert.match(script,/\$health\.data\.staging_safety\.active_mobile_sessions_zero -ne \$true/);
  assert.match(script,/Get-NetTCPConnection -LocalPort 3306/);
  assert.match(script,/Get-NetTCPConnection -LocalPort 18880/);
});

test('backup hash and SQL database-switch are checked before creating anything',()=>{
  assert.match(script,/Get-FileHash -LiteralPath \$dump -Algorithm SHA256/);
  assert.match(script,/manifest\.sql_sha256/);
  assert.match(script,/if\(\$DryRun\)/);
  assert.match(script,/CREATE\|DROP/);
  assert.match(script,/USE\\s\+/);
  assert.ok(script.indexOf('if($DryRun)')<script.indexOf('CREATE DATABASE'));
});

test('restore uses unique new database only and never overwrites prior rehearsal',()=>{
  assert.match(script,/eh7_restore_.*NewGuid/);
  assert.match(script,/CREATE DATABASE/);
  assert.doesNotMatch(script,/CREATE DATABASE IF NOT EXISTS/);
  assert.match(script,/Refusing to overwrite previous restore rehearsal report/);
  assert.match(script,/--database="\+\$target/);
  assert.doesNotMatch(script,/^\s*(?:DROP DATABASE|TRUNCATE TABLE|DELETE FROM)\b/im);
});

test('real table counts, source health and private secrets cleanup are gated',()=>{
  assert.match(script,/CountRows \$sourceDb \$originalTables/);
  assert.match(script,/CountRows \$target \$restoredTables/);
  assert.match(script,/Compare-Object \$originalTables \$restoredTables/);
  assert.match(script,/Source or restored table counts differ/);
  assert.match(script,/Original WordPress ERP health\/source marker changed/);
  assert.match(script,/isolated_restore_verified=\$true/);
  assert.match(script,/production_restore_verified=\$false/);
  assert.match(script,/finally \{[\s\S]*Remove-Item -LiteralPath \$authFile/);
  assert.doesNotMatch(script,/Write-Output.*root_password/);
});
