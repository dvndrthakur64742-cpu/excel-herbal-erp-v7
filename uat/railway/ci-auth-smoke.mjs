// All requests use the ephemeral localhost CI WordPress container and synthetic identity.
// This test never prints passwords or session tokens.
const base = 'http://127.0.0.1:18880/wp-json/excel-herbal-erp/v7';
const host = 'wordpress-uat-production.up.railway.app';
async function api(route, { method='GET', payload, token } = {}) {
  const headers = { Host: host };
  if (payload) headers['Content-Type'] = 'application/json';
  if (token) headers.Authorization = 'Bearer ' + token;
  const response = await fetch(base + route, {
    method, headers, body: payload ? JSON.stringify(payload) : undefined,
    redirect: 'manual', signal: AbortSignal.timeout(10000),
  });
  let body;
  try { body = await response.json(); }
  catch { throw new Error(route + ' returned non-JSON HTTP ' + response.status); }
  return { code: response.status, body };
}
function must(condition, message) { if (!condition) throw new Error(message); }
// Access controls must fail closed before we exercise a real synthetic identity.
const anonymous = await api('/bootstrap');
must([401,403].includes(anonymous.code),
  'Unauthenticated employee bootstrap unexpectedly allowed: ' + anonymous.code);
const wrongPassword = await api('/auth/login', {
  method: 'POST',
  payload: {
    mobile: '9000000002',
    password: 'incorrect_synthetic_password',
    device: 'CI Wrong Password Probe',
    device_id: 'CI-NEGATIVE-1',
  },
});
must(wrongPassword.code === 401 && wrongPassword.body.ok !== true,
  'Invalid synthetic employee password unexpectedly accepted: ' + wrongPassword.code);
console.log('PASS anonymous bootstrap and wrong-password login fail closed');

const login = await api('/auth/login', {
  method: 'POST',
  payload: {
    mobile: '9000000002',
    password: 'eh7_ci_limited_password_only',
    device: 'CI Flutter UAT',
    device_id: 'CI-MOBILE-1',
  },
});
must(login.code === 200 && login.body.ok === true, 'Synthetic employee login rejected: ' + login.code);
const initial = login.body.data;
must(initial?.access_token && initial?.refresh_token, 'Token pair missing');
const bootstrap = await api('/bootstrap', { token: initial.access_token });
must(bootstrap.code === 200 && bootstrap.body.ok === true, 'Mobile bootstrap failed: ' + bootstrap.code);
for (const field of ['me','company','navigation','business_date','business_timezone','server_timestamp','api_contract']) {
  must(Boolean(bootstrap.body.data?.[field]), 'Flutter startup contract missing ' + field);
}
console.log('PASS synthetic employee HTTP login and Flutter bootstrap contract');
// Assert the *actual logged-in* navigation contract, not only that a
// bootstrap API exists. A malformed/empty role projection must fail UAT.
const fieldUi = bootstrap.body.data;
const fieldIdentity = fieldUi.me;
const fieldBranchIds = fieldIdentity?.branch_ids;
const fieldEmployeeId = Number(fieldIdentity?.employee?.id);
const assignedBranchId = Number(fieldIdentity?.assigned_branch_id);
must(Number.isInteger(fieldEmployeeId) && fieldEmployeeId > 0,
  'Field employee bootstrap omitted an actual identity');
must(Array.isArray(fieldBranchIds) && fieldBranchIds.some(
  (id) => Number(id) === assignedBranchId),
  'Assigned employee branch not included in branch authority');
must(fieldUi.features?.api_contract === fieldUi.api_contract &&
     /^\\d{4}-\\d{2}-\\d{2}$/.test(fieldUi.business_date) &&
     Date.parse(fieldUi.server_timestamp) > 0 &&
     typeof fieldUi.business_timezone === 'string' &&
     fieldUi.business_timezone.trim().length > 0,
  'Flutter startup date/timezone/contract metadata inconsistent');
must(Array.isArray(fieldUi.navigation?.sections) &&
     Array.isArray(fieldUi.navigation?.bottom_nav) &&
     fieldUi.navigation.sections.some((section) => section.id === 'home'),
  'Flutter navigation has no Home or bottom-navigation projection');
must(Array.isArray(fieldIdentity.capabilities) &&
     fieldIdentity.capabilities.includes('erp.access'),
  'Synthetic employee lacks fundamental ERP access');
must(!fieldIdentity.capabilities.includes('administration.access.manage'),
  'Limited employee unexpectedly has administration access');

const fieldReadOnly = [
  ['/workforce/attendance/today', 'employee attendance widget'],
  ['/workforce/leave/mine', 'employee leave widget'],
  ['/daily/cycles?branch_id=' + assignedBranchId, 'employee daily-stock widget'],
];
for (const [route, label] of fieldReadOnly) {
  const response = await api(route, { token: initial.access_token });
  must(response.code === 200 && response.body?.ok === true,
    'Authenticated ' + label + ' read failed: HTTP ' + response.code);
}
console.log('PASS field dashboard: scoped identity, navigation, attendance, leave and daily stock reads');
const refresh = await api('/auth/refresh', {
  method: 'POST',
  payload: {
    refresh_token: initial.refresh_token,
    device: 'CI Flutter UAT',
    device_id: 'CI-MOBILE-1',
  },
});
must(refresh.code === 200 && refresh.body.ok === true, 'Refresh token rejected: ' + refresh.code);
must(refresh.body.data?.access_token && refresh.body.data.access_token !== initial.access_token,
  'Refresh did not rotate access token');
const bootstrapAfter = await api('/bootstrap', { token: refresh.body.data.access_token });
must(bootstrapAfter.code === 200 && bootstrapAfter.body.data?.business_date,
  'Bootstrap failed after refresh');
const oldToken = await api('/bootstrap', { token: initial.access_token });
must([401,403].includes(oldToken.code), 'Rotated old access token was still accepted: ' + oldToken.code);
const replay = await api('/auth/refresh', {
  method: 'POST',
  payload: {
    refresh_token: initial.refresh_token,
    device: 'CI Flutter UAT',
    device_id: 'CI-MOBILE-1',
  },
});
must([401,403].includes(replay.code) && replay.body.ok !== true,
  'Already rotated refresh token was replayable: ' + replay.code);
console.log('PASS mobile token refresh, old-token revocation and refresh replay denial');


const adminLogin = await api('/auth/login', {
  method: 'POST',
  payload: {
    mobile: '9000000001',
    password: 'eh7_ci_admin_password_only',
    device: 'CI Flutter UAT Admin',
    device_id: 'CI-ADMIN-1',
  },
});
must(adminLogin.code === 200 && adminLogin.body.data?.access_token,
  'Synthetic administrator login rejected');
const adminToken = adminLogin.body.data.access_token;
const adminBootstrap = await api('/bootstrap', { token: adminToken });
must(adminBootstrap.code === 200 && Array.isArray(adminBootstrap.body.data?.branches),
  'Synthetic administrator bootstrap missing branches');
const activeBranch = adminBootstrap.body.data.branches[0]?.id;
must(Number(activeBranch) > 0, 'Synthetic administrator has no scoped branch');
const orders = await api('/sales/orders?branch_id=' + activeBranch, { token: adminToken });
must(orders.code === 200 && orders.body.ok && Array.isArray(orders.body.data),
  'Prepaid sales order queue REST contract failed');
const accounts = await api('/sales/payment-accounts?branch_id=' + activeBranch,
  { token: adminToken });
must(accounts.code === 200 && accounts.body.ok && Array.isArray(accounts.body.data),
  'Minimal prepaid Cash/UPI account REST contract failed');
for (const row of accounts.body.data) {
  must(['cash', 'upi'].includes(row.subtype), 'Unexpected collection account subtype');
  must(!Object.hasOwn(row, 'bank_account_number') &&
      !Object.hasOwn(row, 'private_credentials'),
      'Collection lookup leaked sensitive account metadata');
}
console.log('PASS admin branch-scoped prepaid order and Cash/UPI account REST APIs');
// Exercise actual read-only module APIs that populate the desktop ERP,
// rather than counting only registered routes or screenshots.
const adminReadOnly = [
  ['/organization/branches', 'branch manager selector'],
  ['/organization/employees?branch_id=' + Number(activeBranch), 'HR employee list'],
  ['/inventory/stock?branch_id=' + Number(activeBranch), 'inventory stock list'],
  ['/daily/cycles?branch_id=' + Number(activeBranch), 'daily stock list'],
  ['/sales/customers?branch_id=' + Number(activeBranch), 'sales customer list'],
];
for (const [route, label] of adminReadOnly) {
  const response = await api(route, { token: adminToken });
  must(response.code === 200 && response.body?.ok === true,
    'Authenticated admin ' + label + ' read failed: HTTP ' + response.code);
}
must(adminBootstrap.body.data?.navigation?.sections?.some(
  (item) => item.id === 'home'),
  'Administrator desktop dashboard not reachable');
console.log('PASS admin dashboard: five real scoped module GET workflows');
