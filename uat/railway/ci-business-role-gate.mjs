/**
 * F16: Real WordPress REST permission gate on exact CI Git source.
 * Ephemeral CI WordPress/MariaDB only; never live/localhost personal UAT.
 * No business writes. The only POST calls are synthetic login/logout.
 */
const ROOT = 'http://127.0.0.1:18880/wp-json/excel-herbal-erp/v7';
const HOST = 'wordpress-uat-production.up.railway.app';
const EXPECTED_SHA = process.env.GITHUB_SHA || '';
const ALLOW_GET = new Set([
  '/health', '/bootstrap', '/workforce/attendance/today',
  '/inventory/stock', '/sales/orders', '/finance/bootstrap',
  '/payroll/runs', '/workforce/gps/team', '/organization/employees',
]);
const SCOPED = new Set(['/inventory/stock','/sales/orders','/organization/employees']);

export function validateTarget() {
  if (process.env.EH7_CI_ISOLATED !== '1' ||
    !/^[a-f0-9]{40}$/.test(EXPECTED_SHA) ||
    process.env.GITHUB_ACTIONS !== 'true') {
    throw new Error('Not exact-source ephemeral GitHub CI; refusing network requests');
  }
  if (new URL(ROOT).hostname !== '127.0.0.1' ||
    new URL(ROOT).port !== '18880' ||
    HOST !== 'wordpress-uat-production.up.railway.app') {
    throw new Error('Disallowed WordPress test host');
  }
}
function must(ok, why) { if (!ok) throw new Error(why); }

export function allowedRoute(route, method) {
  if (route.startsWith('http') || !route.startsWith('/')) {
    throw new Error('Unapproved test route');
  }
  const url = new URL(ROOT + route);
  if (url.origin !== new URL(ROOT).origin ||
    !url.pathname.startsWith('/wp-json/excel-herbal-erp/v7/')) {
    throw new Error('Disallowed ERP test path');
  }
  const relative = url.pathname.slice('/wp-json/excel-herbal-erp/v7'.length);
  if (method === 'POST') {
    if (!['/auth/login','/auth/logout'].includes(relative) || url.search) {
      throw new Error('Business mutations are forbidden in F16 HTTP tests');
    }
    return;
  }
  if (method !== 'GET' || !ALLOW_GET.has(relative)) {
    throw new Error('Unapproved read-only test endpoint');
  }
  if (SCOPED.has(relative)) {
    if (!/^\?branch_id=\d+$/.test(url.search)) {
      throw new Error('Branch-scoped request missing numeric branch_id');
    }
  } else if (url.search) {
    throw new Error('Unexpected query arguments');
  }
}
export function assertAccess(label, response, granted) {
  if (granted) {
    must(response.code === 200 && response.body?.ok === true,
      label + ': expected HTTP 200 JSON success; received '+response.code);
  } else {
    must(response.code === 403 && response.body?.ok === false,
      label + ': denied access did not return 403');
    must(!Object.hasOwn(response.body, 'data'),
      label + ': denied response leaked business data');
  }
}
async function api(route, {token, method = 'GET', payload} = {}) {
  allowedRoute(route, method);
  const response = await fetch(ROOT + route, {
    method, redirect:'manual', signal:AbortSignal.timeout(12000),
    headers:{
      Host:HOST, Accept:'application/json',
      ...(token ? {Authorization:'Bearer '+token} : {}),
      ...(payload ? {'Content-Type':'application/json'} : {}),
    },
    body: payload ? JSON.stringify(payload) : undefined,
  });
  if (!(response.headers.get('content-type')||'').toLowerCase().includes('application/json')) {
    throw new Error('Non-JSON response for expected ERP route: '+route);
  }
  return {code:response.status,body:await response.json()};
}

async function withSyntheticActor({name,mobile,password,deviceId}, check) {
  let token = null;
  try {
    const login=await api('/auth/login',{method:'POST',payload:{
      mobile,password,device:'CI F16 isolated role gate',device_id:deviceId,
    }});
    must(login.code===200&&login.body?.ok===true&&
      typeof login.body.data?.access_token==='string',
      name+' synthetic login failed');
    token=login.body.data.access_token;
    const bootstrap=await api('/bootstrap',{token});
    must(bootstrap.code===200&&bootstrap.body?.ok===true&&
      bootstrap.body?.data?.me?.employee?.id,
      name+' bootstrap failed');
    await check(token,bootstrap.body.data);
  } finally {
    if (token) {
      const end=await api('/auth/logout',{method:'POST',token});
      must(end.code===200&&end.body?.ok===true,
        name+' token cleanup failed');
      const after=await api('/bootstrap',{token});
      must([401,403].includes(after.code)&&after.body?.ok!==true,
        name+' revoked token still works');
    }
  }
}
async function main() {
  validateTarget();
  const h=await api('/health');
  const data=h.body?.data;
  must(h.code===200&&h.body?.ok===true&&
    data?.source_head===EXPECTED_SHA&&data?.environment==='staging'&&
    data?.staging_safety?.sanitized===true&&
    data?.staging_safety?.source_head_match===true&&
    data?.staging_safety?.active_mobile_sessions_zero===true&&
    data?.uat_bootstrap?.seeded===true&&
    data?.uat_bootstrap?.synthetic_only===true&&
    data?.uat_bootstrap?.source_head_match===true,
    'Fail closed: source/idle/synthetic WordPress environment mismatch');

  await withSyntheticActor({
    name:'Employee',mobile:'9000000002',
    password:'eh7_ci_limited_password_only',deviceId:'EH7-CI-F16-EMP',
  },async(token,boot)=>{
    const branch=Number(boot.me.assigned_branch_id);
    must(Number.isInteger(branch)&&branch>0,'Employee has no assigned branch');
    const cases=[
      ['/workforce/attendance/today',true],
      ['/inventory/stock?branch_id='+branch,false],
      ['/sales/orders?branch_id='+branch,false],
      ['/finance/bootstrap',false],
      ['/payroll/runs',false],
      ['/workforce/gps/team',false],
      ['/organization/employees?branch_id='+branch,false],
    ];
    for(const [route,grant] of cases) {
      assertAccess('Employee '+route,await api(route,{token}),grant);
    }
    console.log('PASS F16 employee 7 real WordPress REST scoped reads');
  });
  await withSyntheticActor({
    name:'Head Office',mobile:'9000000001',
    password:'eh7_ci_admin_password_only',deviceId:'EH7-CI-F16-HO',
  },async(token,boot)=>{
    must(Array.isArray(boot.branches)&&boot.branches.length>0,
      'Synthetic Head Office has no authorized branches');
    const branch=Number(boot.branches[0].id);
    must(Number.isInteger(branch)&&branch>0,
      'Synthetic Head Office invalid branch');
    const cases=[
      ['/workforce/attendance/today',true],
      ['/inventory/stock?branch_id='+branch,true],
      ['/sales/orders?branch_id='+branch,true],
      ['/finance/bootstrap',true],
      ['/payroll/runs',true],
      ['/workforce/gps/team',true],
      ['/organization/employees?branch_id='+branch,true],
      ['/sales/orders?branch_id=999',false],
    ];
    for(const [route,grant] of cases) {
      assertAccess('HeadOffice '+route,await api(route,{token}),grant);
    }
    console.log('PASS F16 Head Office 8 real WordPress REST scoped reads');
  });
  console.log('PASS F16 source-pinned 15-route ephemeral WordPress role UAT; tokens revoked');
}

const {pathToFileURL}=await import('node:url');
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  main().catch(e=>{console.error('F16_WORDPRESS_UAT_BLOCKED: '+e.message);process.exitCode=1;});
}
