import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {assertForbiddenReply} from './ci-role-denial-contract.mjs';

test('403 permission denied with no business data passes', () => {
  assert.doesNotThrow(() => assertForbiddenReply(
    {code: 403, body: {ok: false, error: {code: 'permission_denied'}}},
    'permission_denied', 'employee stock'));
  assert.doesNotThrow(() => assertForbiddenReply(
    {code: 403, body: {ok: false, error: {code: 'branch_forbidden'}}},
    'branch_forbidden', 'cross-branch orders'));
});

test('unintended 200 grant blocks even when no leaked details shown', () => {
  assert.throws(() => assertForbiddenReply(
    {code: 200, body: {ok: true, data: []}},
    'permission_denied', 'employee payroll'), /not denied safely/);
});

test('401 auth failure is not proof of correct role authorization', () => {
  assert.throws(() => assertForbiddenReply(
    {code: 401, body: {ok: false, error: {code: 'not_authenticated'}}},
    'permission_denied', 'employee finance'), /not denied safely/);
});

test('wrong 403 denial code and leaked data always fail', () => {
  assert.throws(() => assertForbiddenReply(
    {code: 403, body: {ok: false, error: {code: 'branch_forbidden'}}},
    'permission_denied', 'employee stock'), /not denied safely/);
  assert.throws(() => assertForbiddenReply(
    {code: 403, body: {ok: false, error: {code: 'permission_denied'}, data: []}},
    'permission_denied', 'employee HR'), /not denied safely/);
});

test('real WordPress UAT script uses only allowed local host and revokes both users', () => {
  const code = readFileSync(fileURLToPath(new URL('./ci-auth-smoke.mjs', import.meta.url)), 'utf8');
  assert.match(code, /const base = 'http:\/\/127\.0\.0\.1:18880\/wp-json/);
  assert.match(code, /const restrictedReads = \[/);
  assert.match(code, /assertForbiddenReply\(response, 'permission_denied'/);
  assert.match(code, /assertForbiddenReply\(foreignOrderAccess, 'branch_forbidden'/);
  assert.match(code, /active_mobile_sessions_zero === true/);
  assert.match(code, /'\/auth\/logout'/);
  assert.doesNotMatch(code, /console\.(?:log|error)\(\s*(?:token|initial|refresh|adminToken|secret)\b/i);
});
