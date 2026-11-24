import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  SITE, ROLE_CASES, BUSINESS_PATHS, assertSyntheticCandidate,
  assertRoleResult, allowRequest,
} from './candidate-three-role-readonly.mjs';

const sha = '479ed9d9482a373441af0b9e312134c89ad756d8';
const secret = { website: SITE, source_sha: sha };
const healthy = {
  ok: true, data: {
    source_head: sha, environment: 'staging',
    staging_safety: {
      sanitized: true, source_head_match: true,
      active_mobile_sessions_zero: true, active_push_devices_zero: true,
    },
    uat_bootstrap: {
      seeded: true, synthetic_only: true, source_head_match: true,
    },
  },
};

test('all 24 least-privilege expectations remain stable and unique', () => {
  assert.equal(Object.values(ROLE_CASES).reduce((n, x) => n + x.length, 0), 24);
  assert.equal(BUSINESS_PATHS.size, 8);
  for (const [role, cases] of Object.entries(ROLE_CASES)) {
    assert.equal(cases.length, 8, role);
    for (const [endpoint, status, code] of cases) {
      const body = status === 200 ? { ok: true, data: [] }
        : { ok: false, error: { code } };
      assert.doesNotThrow(() => assertRoleResult(role, endpoint, { status, body }));
    }
  }
});

test('unexpected grant, withheld permission and data leak always fail', () => {
  assert.throws(() => assertRoleResult('Employee', '/payroll/runs',
    { status: 200, body: { ok: true, data: [] } }), /expected HTTP 403/);
  assert.throws(() => assertRoleResult('HeadOffice', '/payroll/runs',
    { status: 403, body: { ok: false, error: { code: 'permission_denied' } } }),
  /expected HTTP 200/);
  assert.throws(() => assertRoleResult('BranchManager',
    '/sales/orders?branch_id=999',
    { status: 403, body: { ok: false, error: { code: 'branch_forbidden' }, data: [] } }),
  /must not contain business data/);
  assert.throws(() => assertRoleResult('Employee', '/inventory/stock?branch_id=1',
    { status: 403, body: { ok: false, error: { code: 'internal_error' } } }),
  /permission_denied/);
  assert.throws(() => assertRoleResult('MadeUpRole', '/sales/orders?branch_id=1',
    { status: 200, body: { ok: true } }), /Unapproved role/);
});

test('every business route is GET only, and only login/logout POST is permitted', () => {
  for (const endpoint of BUSINESS_PATHS) {
    assert.doesNotThrow(() => allowRequest(endpoint, 'GET'));
    assert.throws(() => allowRequest(endpoint, 'POST'), /Refusing/);
  }
  assert.doesNotThrow(() => allowRequest('/auth/login', 'POST'));
  assert.doesNotThrow(() => allowRequest('/auth/logout', 'POST'));
  assert.doesNotThrow(() => allowRequest('/health', 'GET'));
  assert.doesNotThrow(() => allowRequest('/bootstrap', 'GET'));
  assert.throws(() => allowRequest('/auth/login', 'GET'), /Refusing/);
  assert.throws(() => allowRequest('/workforce/attendance/check-in', 'POST'), /Refusing/);
  assert.throws(() => allowRequest('/finance/periods/close', 'POST'), /Refusing/);
  assert.throws(() => allowRequest('https://office.excelherbal.in/', 'GET'), /Refusing/);
});

test('synthetic candidate must match exact checkout and sanitized idle state', () => {
  assert.doesNotThrow(() => assertSyntheticCandidate({
    secret, actualSha: sha, health: healthy,
  }));
  assert.throws(() => assertSyntheticCandidate({
    secret: { ...secret, website: 'https://office.excelherbal.in' },
    actualSha: sha, health: healthy,
  }), /Not the allowlisted/);
  assert.throws(() => assertSyntheticCandidate({
    secret, actualSha: 'a'.repeat(40), health: healthy,
  }), /source pin mismatch/);
  assert.throws(() => assertSyntheticCandidate({
    secret, actualSha: sha, health: {
      ...healthy, data: {
        ...healthy.data, staging_safety: {
          ...healthy.data.staging_safety, active_mobile_sessions_zero: false,
        },
      },
    },
  }), /idle, sanitized/);
  assert.throws(() => assertSyntheticCandidate({
    secret, actualSha: sha, health: {
      ...healthy, data: { ...healthy.data, environment: 'production' },
    },
  }), /idle, sanitized/);
});

test('runner does not use production endpoints or log credential-bearing material', () => {
  const content = readFileSync(fileURLToPath(new URL(
    './candidate-three-role-readonly.mjs', import.meta.url,
  )), 'utf8');
  assert.doesNotMatch(content, /fetch\(['"]https?:\/\/office\./);
  assert.doesNotMatch(content, /console\.(?:log|error)\([^\n]*(?:password|access_token|refresh_token|secret\.)/i);
  assert.match(content, /process\.platform === 'win32'/);
  assert.match(content, /active_mobile_sessions_zero === true/);
  assert.match(content, /CANDIDATE_CHECKOUT/);
  assert.match(content, /finally \{/);
});
