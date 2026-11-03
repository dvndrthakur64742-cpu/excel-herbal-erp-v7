/**
 * Windows-only, localhost-only synthetic Branch Manager REST authorization UAT.
 * No real employee credentials, production URLs or token output.
 */
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';

if(process.platform!=='win32')throw Error('Candidate BM UAT is Windows-only');
const site='http://127.0.0.1:18880/erp-uat-candidate';
const api=site+'/wp-json/excel-herbal-erp/v7';
const credential='D:/ERP-Local-Secrets/candidate-uat-app.json';
const secret=JSON.parse(readFileSync(credential,'utf8').replace(/^\uFEFF/,''));
const gitSha=execFileSync('git',['-C','D:/ERP7-UAT-Candidate','rev-parse','HEAD'],{encoding:'utf8',timeout:5000}).trim();
function must(ok,msg){if(!ok)throw Error(msg);}
must(secret.website===site&&secret.source_sha===gitSha&&/^[a-f0-9]{40}$/i.test(gitSha),
  'Candidate website, private synthetic credentials and mounted Git source do not match');
must(secret.bm_mobile==='9000000003'&&secret.bm_employee_id===3&&
  String(secret.bm_password||'').length>=10,
  'Refusing non-synthetic or missing BM credential identity');
let token='';
async function request(path,method='GET',payload){
 const headers={};
 if(payload)headers['Content-Type']='application/json';
 if(token)headers.Authorization='Bearer '+token;
 const response=await fetch(api+path,{method,headers,
  body:payload?JSON.stringify(payload):undefined,redirect:'manual',
  signal:AbortSignal.timeout(15000)});
 let body;
 try{body=await response.json()}catch{throw Error('Non-JSON candidate API response at '+path)}
 return {status:response.status,body};
}
try {
 const health=await request('/health');
 must(health.status===200 && health.body.ok===true &&
  health.body.data.source_head===gitSha &&
  health.body.data.staging_safety?.sanitized===true &&
  health.body.data.staging_safety?.active_mobile_sessions_zero===true &&
  health.body.data.uat_bootstrap?.seeded===true &&
  health.body.data.uat_bootstrap?.synthetic_only===true,
  'Candidate is not source-verified, sanitized and idle');
 console.log('PASS candidate is isolated, sanitized and pinned to mounted Git source');
 const login=await request('/auth/login','POST',{
  mobile:secret.bm_mobile,password:secret.bm_password,
  device_id:'EH7-CANDIDATE-BM-REST',device:'Isolated synthetic BM role UAT'});
 must(login.status===200 && login.body?.ok===true &&
  login.body.data?.access_token,'Synthetic BM login failed');
 token=login.body.data.access_token;
 const bootstrap=await request('/bootstrap');
 must(bootstrap.status===200&&bootstrap.body?.ok===true,'BM bootstrap failed');
 const me=bootstrap.body.data?.me;
 must(Number(me?.employee?.id)===3&&me.employee?.designation_code==='BM'&&
   Number(me?.assigned_branch_id)===1&&
   Array.isArray(me?.branch_ids)&&me.branch_ids.map(Number).join(',')==='1',
   'BM role/branch identity mismatch');
 console.log('PASS BM login, role, source and exactly one authorized branch');
 const allowed=await request('/sales/orders?branch_id=1');
 must(allowed.status===200 && allowed.body?.ok===true,
  'BM denied legitimate branch orders');
 const denied=await request('/sales/orders?branch_id=999');
 must(denied.status===403,'BM foreign-branch access was not denied with HTTP 403');
 console.log('PASS branch 1 sales access; forbidden cross-branch access denied with HTTP 403');
} finally {
 if(token) {
  const loggedOut=await request('/auth/logout','POST');
  must(loggedOut.status===200&&loggedOut.body?.ok===true,'BM logout failed');
  const after=await request('/bootstrap');
  must([401,403].includes(after.status),'BM token was not revoked');
  console.log('PASS BM logout and token revocation');
 }
}
const cleanup=await request('/health');
must(cleanup.status===200&&cleanup.body.data?.staging_safety?.active_mobile_sessions_zero===true,
 'Synthetic BM session remained active');
console.log('CANDIDATE SYNTHETIC BM REST UAT PASSED');
