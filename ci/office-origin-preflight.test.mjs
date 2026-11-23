import test from 'node:test';
import assert from 'node:assert/strict';
import { analyseOfficeRoutes } from './office-origin-preflight.mjs';

const sha = 'da45867ac0db3e4219fcf229f971986d0067acc7';
const pluginBase = 'https://office.excelherbal.in/wp-content/plugins/excel-herbal-erp-v7/web/';
const oldBase = '/wp-content/uploads/eh7-web-e7ede3d/';
const html = base => ({
  status: 200, contentType: 'text/html; charset=utf-8',
  body: '<html><head><base href="' + base + '"></head></html>',
});
const json = source => ({
  status: 200, contentType: 'application/json; charset=utf-8',
  body: JSON.stringify({ ok: true, data: { source_head: source } }),
});
const good = () => ({
  root: html(pluginBase),
  preview: html(pluginBase),
  prettyApi: json(sha),
  queryApi: json(sha),
  indexQueryApi: json(sha),
});
test('healthy source, same frontend and both WordPress REST formats pass', () => {
  const report = analyseOfficeRoutes(good(), sha);
  assert.equal(report.gate, 'PASS');
  assert.deepEqual(report.blockers, []);
  assert.equal(report.productionMutationPerformed, false);
});
test('legacy static homepage and query-rest HTML are hard cutover blockers', () => {
  const cases = good();
  cases.root = { ...html(oldBase),
    lastModified: 'Thu, 05 Nov 2026 11:32:41 GMT', xPoweredBy: null };
  cases.queryApi = html(oldBase);
  const report = analyseOfficeRoutes(cases, sha);
  assert.equal(report.gate, 'BLOCK');
  assert.equal(report.rootLegacyAsset, true);
  assert.equal(report.rootStaticInterceptionHint, true);
  assert.equal(report.queryRestReturnsHomepageHTML, true);
  assert.equal(report.indexPhpQueryWorks, true);
  assert.equal(report.rootCauseProven, false);
  assert.deepEqual(report.blockers, ['query_rest', 'homepage_cutover']);
});
test('wrong PHP source blocks rollout even if route and asset URLs work', () => {
  const cases = good();
  cases.prettyApi = json('1'.repeat(40));
  const report = analyseOfficeRoutes(cases, sha);
  assert.equal(report.gate, 'BLOCK');
  assert.ok(report.blockers.includes('reviewed_source'));
});
test('HTTP 403 or missing hosted preview never masquerades as passing', () => {
  const cases = good();
  cases.preview = { status: 403, contentType: 'text/html',
    body: 'Access forbidden' };
  const report = analyseOfficeRoutes(cases, sha);
  assert.equal(report.gate, 'BLOCK');
  assert.ok(report.blockers.includes('preview_wordpress_plugin'));
  assert.ok(report.blockers.includes('homepage_cutover'));
});
test('unavailable API remains blocked, not assumed to be a rewrite issue', () => {
  const cases = good();
  cases.prettyApi = { status: null, contentType: null, body: '',
    error: 'Timeout' };
  const report = analyseOfficeRoutes(cases, sha);
  assert.equal(report.gate, 'BLOCK');
  assert.ok(report.blockers.includes('pretty_rest'));
  assert.equal(report.errors.length, 1);
});
