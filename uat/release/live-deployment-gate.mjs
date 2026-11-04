import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

/**
 * Read-only Live ERP deployment gate.
 * Evidence is sanitized aggregate metadata collected using authenticated
 * WPVibe reads. It never contacts the live site or changes any database.
 * Release requires separately verified source, migrations, user sessions,
 * production restore and Flutter role UAT; synthetic CI is not enough.
 */
export function assessLiveDeployment(live, candidate, now=new Date()) {
  const blockers=[];
  const fail=(code,detail)=>blockers.push({code,detail});
  const expectedOrigin='https://office.excelherbal.in';
  if(live?.origin!==expectedOrigin) fail('wrong_site','Exact Office ERP host is required');
  const observed=new Date(live?.observed_utc||'');
  if(!Number.isFinite(observed.getTime())||now.getTime()-observed.getTime()>86400000||
      observed.getTime()>now.getTime()+300000) {
    fail('stale_evidence','Refresh live read-only preflight within 24 hours');
  }
  if(live?.plugin?.slug!=='excel-herbal-erp-v7'||live?.plugin?.active!==true)
    fail('live_plugin','Current V7 plugin identity is not established');
  if(live?.legacy?.active!==false)
    fail('legacy_plugin','Legacy V15 plugin must not run concurrently');
  if(live?.wordpress?.environment!=='production')
    fail('environment','Office host advertises a non-production ERP environment');
  if(live?.live_schema!==candidate?.schema)
    fail('schema_mismatch','Live database schema differs from tested plugin source; preserve existing columns and records');
  const liveOnly=live?.schema_diff?.live_only_tables;
  const candidateOnly=live?.schema_diff?.candidate_only_tables;
  if((!Array.isArray(liveOnly)||!Array.isArray(candidateOnly)||
      liveOnly.length>0||candidateOnly.length>0) &&
      live?.release_checks?.schema_table_ownership_verified!==true)
    fail('schema_table_delta','Live-only and candidate-only tables require explicit non-destructive ownership and migration mapping');
  if(!/^[a-f0-9]{40}$/i.test(String(candidate?.git_sha??'')))
    fail('unverified_candidate','Candidate must have an immutable verified Git SHA');
  if(!/^[a-f0-9]{40}$/i.test(String(live?.plugin?.source_head??''))||
      live?.live_health?.source_head_match!==true)
    fail('unverified_live_source','Live plugin source pin is unverified');
  if(live?.release_checks?.migration_forward_backward_tested!==true)
    fail('migration_rehearsal','Live-schema upgrade AND rollback rehearsal is required');
  if(live?.release_checks?.live_files_and_db_recovery_verified!==true)
    fail('recovery_unverified','A recoverable live DB+files checkpoint must be verified before write');
  if(live?.counts?.active_sessions>0 && live?.release_checks?.session_compatibility_verified!==true)
    fail('active_sessions','Active mobile sessions exist; token/role/session compatibility is unverified');
  if(live?.release_checks?.real_role_flutter_web_android_uat_passed!==true)
    fail('real_ui_uat','Role-based real-device Flutter/web UAT has not passed');
  if(live?.release_checks?.live_version_source_certified!==true)
    fail('live_release_certification','Candidate release identity is not certified for this live WordPress');
  if(!(Number.isInteger(live?.counts?.employees)&&live.counts.employees>=0))
    fail('missing_inventory','Live employee and schema counts must be measured');
  if(live?.counts?.employees>0 || live?.counts?.attendance>0 || live?.counts?.audit_log>0) {
    if(live?.release_checks?.live_files_and_db_recovery_verified!==true)
      fail('preserve_existing_records','Existing employee, attendance and audit records must not be overwritten');
  }
  return {
    status:blockers.length?'BLOCKED':'READY_FOR_SEPARATE_APPROVAL',
    origin:expectedOrigin,
    candidate_git_sha:candidate?.git_sha??null,
    candidate_schema:candidate?.schema??null,
    observed_utc:live?.observed_utc??null,
    blockers
  };
}
const here=fileURLToPath(new URL('.',import.meta.url));
if(process.argv[1] && fileURLToPath(import.meta.url).toLowerCase()===process.argv[1].toLowerCase()) {
  const live=JSON.parse(readFileSync(here+'live-observation-20261104.json','utf8'));
  const candidate={
    git_sha:process.env.EH7_RELEASE_SHA||'',
    schema:process.env.EH7_RELEASE_SCHEMA||'',
  };
  const result=assessLiveDeployment(live,candidate);
  console.log(JSON.stringify(result,null,2));
  if(result.status!=='READY_FOR_SEPARATE_APPROVAL')process.exitCode=2;
}
