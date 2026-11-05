import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const script=readFileSync(fileURLToPath(new URL('./backup-native-uat.ps1',import.meta.url)),'utf8');

test('backup is strictly localhost and synthetic-only',()=>{
  assert.match(script,/\$site='http:\/\/127\.0\.0\.1:18880\/erp-uat'/);
  assert.ok(script.includes(String.raw`$wp='D:\xampp\htdocs\erp-uat'`));
  assert.ok(script.includes(String.raw`$backupRoot='E:\ERP-Backups'`));
  assert.match(script,/\$state\.uat_bootstrap\.synthetic_only -ne \$true/);
  assert.match(script,/\$state\.staging_safety\.sanitized -ne \$true/);
  assert.match(script,/\$state\.staging_safety\.active_mobile_sessions_zero -ne \$true/);
  assert.match(script,/\$dbName -notmatch 'eh7\|uat\|local'/);
  assert.match(script,/\$dbHost -notin/);
});

test('backup captures real mounted Git provenance separately from PHP marker',()=>{
  assert.match(script,/\$mount\.LinkType -ne 'Junction'/);
  assert.match(script,/git -C \$mountedPlugin rev-parse HEAD/);
  assert.match(script,/mounted_git_sha=\$mountedSha/);
  assert.match(script,/wordpress_health_source_sha=\$healthSha/);
  assert.match(script,/source_matches_health=/);
  assert.match(script,/restore_rehearsal_verified=\$false/);
  assert.match(script,/production_ready=\$false/);
});

test('backup remains nondestructive, with genuine dry run and credential cleanup',()=>{
  assert.match(script,/param\(\[switch\]\$DryRun\)/);
  assert.ok(script.indexOf('if($DryRun)')<script.indexOf('New-Item -ItemType Directory'));
  assert.match(script,/--single-transaction --quick --skip-lock-tables/);
  assert.match(script,/Get-FileHash -LiteralPath \$dump -Algorithm SHA256/);
  assert.match(script,/finally \{[\s\S]*Remove-Item -LiteralPath \$tempOptions/);
  assert.doesNotMatch(script,/^\s*(?:DROP DATABASE|TRUNCATE TABLE|DELETE FROM|git reset|git checkout|UPDATE\s+wp_)\b/im);
});

test('backup cannot silently pass as a production or restore-ready release',()=>{
  assert.match(script,/NOT RESTORE-VERIFIED; NOT RELEASE-APPROVED/);
  assert.match(script,/Source mismatch preserved in snapshot metadata/);
  assert.match(script,/wp-config contains local secrets/);
});
