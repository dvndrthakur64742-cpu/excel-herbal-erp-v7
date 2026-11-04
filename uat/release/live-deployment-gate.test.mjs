import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {assessLiveDeployment} from './live-deployment-gate.mjs';

const actual=JSON.parse(readFileSync(fileURLToPath(
  new URL('./live-observation-20261104.json',import.meta.url)),'utf8'));
const candidate={
  git_sha:'39c8b0a1dd845d48a670901ec4b5ed012fed7b8a',
  schema:'7.3.12-reward-payroll-allocated-6',
};
const now=new Date('2026-11-04T07:45:00Z');

test('authenticated Office production observations BLOCK unreviewed replacement',()=>{
 const result=assessLiveDeployment(actual,candidate,now);
 assert.equal(result.status,'BLOCKED');
 const blockers=new Set(result.blockers.map(x=>x.code));
 for(const key of ['environment','schema_mismatch','unverified_live_source',
   'migration_rehearsal','recovery_unverified','active_sessions','real_ui_uat',
   'live_release_certification','preserve_existing_records']) {
   assert.ok(blockers.has(key),key+' was not blocked');
 }
 assert.equal(actual.counts.employees,27);
 assert.equal(actual.counts.active_sessions,24);
 assert.equal(actual.counts.attendance,441);
});

test('wrong origin, wrong plugin or active legacy runtime are always rejected',()=>{
 const fake=structuredClone(actual);
 fake.origin='https://excelherbal.in';
 fake.plugin.active=false;
 fake.legacy.active=true;
 const ids=assessLiveDeployment(fake,candidate,now).blockers.map(b=>b.code);
 assert.ok(ids.includes('wrong_site'));
 assert.ok(ids.includes('live_plugin'));
 assert.ok(ids.includes('legacy_plugin'));
});

test('stale observations and invalid candidate source cannot become deployment approval',()=>{
 const x=structuredClone(actual);
 x.observed_utc='2026-10-31T00:00:00Z';
 const result=assessLiveDeployment(x,{git_sha:'unverified',schema:actual.live_schema},now);
 assert.equal(result.status,'BLOCKED');
 assert.ok(result.blockers.some(b=>b.code==='stale_evidence'));
 assert.ok(result.blockers.some(b=>b.code==='unverified_candidate'));
});

test('a future hypothetical fully verified release can advance ONLY to separate approval',()=>{
 const ready=structuredClone(actual);
 ready.wordpress.environment='production';
 ready.live_schema=candidate.schema;
 ready.plugin.source_head=candidate.git_sha;
 ready.live_health.source_head_match=true;
 ready.release_checks={
   live_files_and_db_recovery_verified:true,
   migration_forward_backward_tested:true,
   session_compatibility_verified:true,
   real_role_flutter_web_android_uat_passed:true,
   live_version_source_certified:true
 };
 const result=assessLiveDeployment(ready,candidate,now);
 assert.equal(result.status,'READY_FOR_SEPARATE_APPROVAL');
 assert.deepEqual(result.blockers,[]);
});

test('release gate code contains no network calls or live database mutations',()=>{
 const source=readFileSync(fileURLToPath(new URL('./live-deployment-gate.mjs',import.meta.url)),'utf8');
 assert.doesNotMatch(source,/\b(?:fetch|https\.request|XMLHttpRequest|execFileSync|spawnSync|run_wp_cli)\s*\(/);
 assert.doesNotMatch(source,/\b(?:DROP|DELETE|TRUNCATE|UPDATE)\s+(?:TABLE|FROM|wp_)/i);
 assert.match(source,/process\.exitCode=2/);
});
