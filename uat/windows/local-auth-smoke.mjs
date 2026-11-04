/**
 * Excel Herbal V7 localhost-only synthetic employee login smoke test.
 * Run on the authorized Windows development PC AFTER synthetic UAT bootstrap.
 * Requires Node 18+ and LOCAL-ONLY credentials outside Git; never prints tokens.
 * No production URLs, no uploads, no real employee identities.
 */
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { assertLocalUatSourcePin } from './source-pin-guard.mjs';
import { platform } from 'node:os';

const SITE='http://127.0.0.1:18880/erp-uat';
const API=SITE+'/wp-json/excel-herbal-erp/v7';
const FILE=process.env.EH7_LOCAL_AUTH_FILE ||
  (platform()==='win32' ? 'D:\\ERP-Local-Secrets\\local-uat-app.json' : '');
function must(ok,msg){if(!ok)throw new Error(msg);}
must(FILE.length>0,'Missing local UAT credential path');
let secret;
try{secret=JSON.parse(readFileSync(FILE,'utf8').replace(/^\uFEFF/,''));}
catch{throw new Error('Local synthetic credentials file missing or invalid; do not use production credentials');}
must(secret.website===SITE && /^[a-f0-9]{40}$/i.test(secret.source_sha||''),
  'Refusing non-localhost UAT credential file or invalid source commit');
must(secret.admin_mobile==='9000000001' && secret.limited_mobile==='9000000002',
  'Refusing non-synthetic employee mobile numbers');
must(String(secret.admin_password||'').length>=10 && String(secret.limited_password||'').length>=10,
  'Synthetic admin/employee passwords not populated');
// Confirm code actually checked out, not only a WordPress source marker.
const gitSha = execFileSync('git', ['rev-parse','HEAD'], {
  cwd: fileURLToPath(new URL('../../',import.meta.url)),
  encoding:'utf8', timeout:5000,
}).trim();

async function api(path,{method='GET',payload,token}={}){
  const headers={};
  if(payload)headers['Content-Type']='application/json';
  if(token)headers.Authorization='Bearer '+token;
  const res=await fetch(API+path,{
    method,headers,redirect:'manual',signal:AbortSignal.timeout(15000),
    body:payload?JSON.stringify(payload):undefined
  });
  let body;
  try{body=await res.json();}
  catch{throw new Error(path+' did not return JSON (HTTP '+res.status+')');}
  return {code:res.status,body};
}
function ok(res,msg){must(res.code===200&&res.body?.ok===true,msg+' HTTP '+res.code);}
async function login(mobile,password,deviceId){
  const res=await api('/auth/login',{method:'POST',payload:{
    mobile,password,device:'Local synthetic QA',device_id:deviceId
  }});
  ok(res,'Synthetic login failed');
  must(res.body.data?.access_token&&res.body.data?.refresh_token,
    'Login did not issue both tokens');
  return res.body.data;
}
async function logout(token){
  if(!token)return;
  const res=await api('/auth/logout',{method:'POST',token});
  ok(res,'Logout failed');
  must(res.body.data?.logged_out===true,'Logout response missing acknowledgment');
}
let fieldAccess;
let adminAccess;
try{
  const health=await api('/health');
  ok(health,'ERP health failed');
  const state=health.body.data;
  assertLocalUatSourcePin({credentialSha:secret.source_sha,gitSha,health:state});
  must(state.environment==='staging' &&
       state.uat_bootstrap?.seeded===true &&
       state.uat_bootstrap?.synthetic_only===true &&
       state.staging_safety?.sanitized===true &&
       state.uat_bootstrap?.source_head_match===true &&
       state.source_head===secret.source_sha,
    'UAT is not sanitized, synthetic-only or pinned to the expected source');
  console.log('PASS synthetic-only, source-verified localhost ERP health');

  const anonymous=await api('/bootstrap');
  must([401,403].includes(anonymous.code),'Anonymous employee bootstrap unexpectedly allowed');
  const incorrect=await api('/auth/login',{method:'POST',payload:{
    mobile:secret.limited_mobile,password:'definitely_not_the_synthetic_password',
    device:'Local synthetic QA',device_id:'EH7-LOCAL-WRONG'
  }});
  must(incorrect.code===401,'Incorrect synthetic employee password unexpectedly accepted');
  console.log('PASS anonymous access and invalid-password denial');

  const first=await login(secret.limited_mobile,secret.limited_password,'EH7-LOCAL-EMPLOYEE');
  fieldAccess=first.access_token;
  const bootstrap=await api('/bootstrap',{token:fieldAccess});
  ok(bootstrap,'Employee bootstrap failed');
  for(const key of ['me','company','navigation','business_date','business_timezone','api_contract']){
    must(Boolean(bootstrap.body.data?.[key]),'Employee bootstrap missing '+key);
  }
  console.log('PASS field employee login and Flutter bootstrap');
  const rotated=await api('/auth/refresh',{method:'POST',payload:{
    refresh_token:first.refresh_token,device:'Local synthetic QA',device_id:'EH7-LOCAL-EMPLOYEE'
  }});
  ok(rotated,'Refresh token failed');
  must(rotated.body.data?.access_token &&
       rotated.body.data.access_token!==first.access_token,
    'Refresh access token was not rotated');
  fieldAccess=rotated.body.data.access_token;
  const stale=await api('/bootstrap',{token:first.access_token});
  must([401,403].includes(stale.code),'Previous access token remained valid');
  const replay=await api('/auth/refresh',{method:'POST',payload:{
    refresh_token:first.refresh_token,device:'Local synthetic QA',device_id:'EH7-LOCAL-EMPLOYEE'
  }});
  must([401,403].includes(replay.code),'Old refresh token was replayable');
  console.log('PASS refresh rotation, old-token rejection and replay protection');
  await logout(fieldAccess);
  const after=await api('/bootstrap',{token:fieldAccess});
  must([401,403].includes(after.code),'Logged-out employee access token is valid');
  fieldAccess=undefined;
  console.log('PASS employee logout and token revocation');

  const admin=await login(secret.admin_mobile,secret.admin_password,'EH7-LOCAL-ADMIN');
  adminAccess=admin.access_token;
  const adminBoot=await api('/bootstrap',{token:adminAccess});
  ok(adminBoot,'Admin bootstrap failed');
  const branchId=adminBoot.body.data?.branches?.[0]?.id;
  must(Number(branchId)>0,'Administrator has no scoped synthetic branch');
  const orders=await api('/sales/orders?branch_id='+Number(branchId),{token:adminAccess});
  ok(orders,'Synthetic branch sales queue failed');
  must(Array.isArray(orders.body.data),'Synthetic order queue missing array');
  const payments=await api('/sales/payment-accounts?branch_id='+Number(branchId),
    {token:adminAccess});
  ok(payments,'Synthetic payment account lookup failed');
  must(Array.isArray(payments.body.data),'Payment accounts not an array');
  console.log('PASS administrator branch-scoped sales and Cash/UPI APIs');
  await logout(adminAccess);
  adminAccess=undefined;

  const final=await api('/health');
  ok(final,'Post-test health failed');
  must(final.body.data?.staging_safety?.active_mobile_sessions_zero===true,
       'Local synthetic sessions were not revoked');
  console.log('PASS cleanup: no active synthetic mobile sessions');
  console.log('LOCAL ERP SYNTHETIC LOGIN UAT PASSED');
}finally{
  // If the smoke check aborts midway, best-effort revoke any current token.
  for(const token of [fieldAccess,adminAccess]){
    if(token){try{await logout(token);}catch{/* Test failure remains authoritative */}}
  }
}
