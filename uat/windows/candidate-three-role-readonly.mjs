/**
 * Repeatable, source-pinned, synthetic-only ERP permission matrix for local UAT.
 *
 * Exactly three synthetic users; GET only on business endpoints. Only login
 * and logout may use POST. No real staff, production URLs, business writes,
 * token logs or secret material in GitHub/CI.
 *
 * Windows: node uat/windows/candidate-three-role-readonly.mjs
 * Linux CI: node --test uat/windows/candidate-three-role-readonly.test.mjs
 */
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

export const SITE = 'http://127.0.0.1:18880/erp-uat-candidate';
const BASE = SITE + '/wp-json/excel-herbal-erp/v7';
const CREDENTIAL_FILE = 'D:/ERP-Local-Secrets/candidate-uat-app.json';
const CANDIDATE_CHECKOUT = 'D:/ERP7-UAT-Candidate';

/** Expectations for the existing isolated UAT fixture, not general ERP RBAC policy. */
export const ROLE_CASES = Object.freeze({
  Employee: Object.freeze([
    ['/workforce/attendance/today', 200, null],
    ['/inventory/stock?branch_id=1', 403, 'permission_denied'],
    ['/sales/orders?branch_id=1', 403, 'permission_denied'],
    ['/finance/bootstrap', 403, 'permission_denied'],
    ['/payroll/runs', 403, 'permission_denied'],
    ['/workforce/gps/team', 403, 'permission_denied'],
    ['/organization/employees', 403, 'permission_denied'],
    ['/sales/orders?branch_id=999', 403, 'permission_denied'],
  ]),
  BranchManager: Object.freeze([
    ['/workforce/attendance/today', 200, null],
    ['/inventory/stock?branch_id=1', 200, null],
    ['/sales/orders?branch_id=1', 200, null],
    ['/finance/bootstrap', 200, null],
    ['/payroll/runs', 403, 'permission_denied'],
    ['/workforce/gps/team', 403, 'permission_denied'],
    ['/organization/employees', 200, null],
    ['/sales/orders?branch_id=999', 403, 'branch_forbidden'],
  ]),
  HeadOffice: Object.freeze([
    ['/workforce/attendance/today', 200, null],
    ['/inventory/stock?branch_id=1', 200, null],
    ['/sales/orders?branch_id=1', 200, null],
    ['/finance/bootstrap', 200, null],
    ['/payroll/runs', 200, null],
    ['/workforce/gps/team', 200, null],
    ['/organization/employees', 200, null],
    ['/sales/orders?branch_id=999', 403, 'branch_forbidden'],
  ]),
});
export const BUSINESS_PATHS = new Set(
  Object.values(ROLE_CASES).flatMap(cases => cases.map(([name]) => name)),
);

function must(condition, message) {
  if (!condition) throw new Error(message);
}

export function assertSyntheticCandidate({secret, actualSha, health}) {
  must(secret?.website === SITE, 'Not the allowlisted localhost candidate');
  must(typeof actualSha === 'string' && /^[0-9a-f]{40}$/i.test(actualSha),
    'Invalid git checkout SHA');
  must(secret?.source_sha === actualSha, 'Synthetic secret source pin mismatch');
  const data = health?.data;
  must(health?.ok === true && data?.source_head === actualSha,
    'Source-pinned candidate health does not match');
  must(data?.environment === 'staging' &&
    data?.staging_safety?.sanitized === true &&
    data?.staging_safety?.source_head_match === true &&
    data?.staging_safety?.active_mobile_sessions_zero === true &&
    data?.staging_safety?.active_push_devices_zero === true &&
    data?.uat_bootstrap?.seeded === true &&
    data?.uat_bootstrap?.synthetic_only === true &&
    data?.uat_bootstrap?.source_head_match === true,
    'Candidate is not an idle, sanitized, synthetic-only UAT');
}

export function assertRoleResult(role, endpoint, response) {
  const row = ROLE_CASES[role]?.find(([path]) => path === endpoint);
  must(!!row, 'Unapproved role or read-only endpoint: ' + role + ' ' + endpoint);
  const [, expectedHttp, expectedError] = row;
  must(response?.status === expectedHttp,
    role + ' ' + endpoint + ': expected HTTP ' + expectedHttp +
    ', received ' + String(response?.status));
  if (expectedHttp === 200) {
    must(response.body?.ok === true,
      role + ' ' + endpoint + ': successful GET must have ok=true');
  } else {
    must(response.body?.ok === false &&
      response.body?.error?.code === expectedError,
      role + ' ' + endpoint + ': denied GET must return ' + expectedError);
    must(!Object.hasOwn(response.body, 'data'),
      role + ' ' + endpoint + ': denied response must not contain business data');
  }
}

export function allowRequest(endpoint, method) {
  const business = BUSINESS_PATHS.has(endpoint);
  const publicRead = endpoint === '/health' || endpoint === '/bootstrap';
  const authAction = endpoint === '/auth/login' || endpoint === '/auth/logout';
  must(
    (method === 'GET' && (business || publicRead)) ||
    (method === 'POST' && authAction),
    'Refusing anything except allowlisted GETs and synthetic login/logout',
  );
}

async function main() {
  must(process.platform === 'win32', 'Windows localhost candidate only');
  const secret = JSON.parse(readFileSync(CREDENTIAL_FILE, 'utf8')
    .replace(/^\uFEFF/, ''));
  const actualSha = execFileSync('git',
    ['-C', CANDIDATE_CHECKOUT, 'rev-parse', 'HEAD'],
    { encoding: 'utf8', timeout: 5000 }).trim();

  async function call(endpoint, token = '', method = 'GET', payload) {
    allowRequest(endpoint, method);
    const response = await fetch(BASE + endpoint, {
      method,
      headers: {
        ...(token ? { Authorization: 'Bearer ' + token } : {}),
        ...(payload ? { 'Content-Type': 'application/json' } : {}),
      },
      body: payload ? JSON.stringify(payload) : undefined,
      redirect: 'manual',
      signal: AbortSignal.timeout(15000),
    });
    const type = response.headers.get('content-type') || '';
    must(type.toLowerCase().includes('application/json'),
      'Candidate did not return JSON for allowlisted endpoint: ' + endpoint);
    return { status: response.status, body: await response.json() };
  }

  const initial = await call('/health');
  assertSyntheticCandidate({ secret, actualSha, health: initial.body });
  console.log('PASS synthetic candidate staging/source/safety and no active sessions');

  const identities = [
    ['Employee', secret.limited_mobile, secret.limited_password, 2],
    ['BranchManager', secret.bm_mobile, secret.bm_password, 3],
    ['HeadOffice', secret.admin_mobile, secret.admin_password, 1],
  ];

  for (const [role, mobile, password, employeeId] of identities) {
    must(mobile === '900000000' + employeeId &&
      String(password || '').length >= 10,
      'Refusing non-synthetic identity for ' + role);
    let token = '';
    try {
      const login = await call('/auth/login', '', 'POST', {
        mobile, password, device: 'Local synthetic role QA',
        device_id: 'EH7-ROLE-MATRIX-' + employeeId,
      });
      must(login.status === 200 && login.body?.ok === true &&
        typeof login.body?.data?.access_token === 'string',
        'Synthetic role login failed: ' + role);
      token = login.body.data.access_token;
      const bootstrap = await call('/bootstrap', token);
      must(bootstrap.status === 200 && bootstrap.body?.ok === true &&
        Number(bootstrap.body?.data?.me?.employee?.id) === employeeId,
        'Unexpected synthetic actor: ' + role);
      for (const [endpoint] of ROLE_CASES[role]) {
        assertRoleResult(role, endpoint, await call(endpoint, token));
      }
      console.log('PASS ' + role + ': 8 read-only API permissions match synthetic fixture');
    } finally {
      if (token) {
        const end = await call('/auth/logout', token, 'POST');
        must(end.status === 200 && end.body?.ok === true,
          'Synthetic logout failed: ' + role);
        const revoked = await call('/bootstrap', token);
        must([401, 403].includes(revoked.status),
          'Revoked synthetic token is still active: ' + role);
      }
    }
  }

  const final = await call('/health');
  must(final.status === 200 &&
    final.body?.data?.staging_safety?.active_mobile_sessions_zero === true,
    'Synthetic UAT still has active mobile sessions');
  console.log('PASS no remaining synthetic sessions; all 24 role checks certified');
}

const direct = process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (direct) main().catch(e => {
  // Error messages deliberately contain no URL tokens, passwords or API data.
  console.error('SYNTHETIC_ROLE_MATRIX_BLOCKED: ' + e.message);
  process.exitCode = 1;
});
