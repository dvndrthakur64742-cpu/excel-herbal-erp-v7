#!/usr/bin/env node
/**
 * Read-only hosted-route acceptance gate for Excel Herbal ERP.
 *
 * Only public, anonymous GET requests are issued. No logins, credentials,
 * REST mutations, cache purges, WordPress settings, or file writes on the site.
 * Exit 2 = unsafe/incomplete for homepage cutover, 1 = probe/network problem.
 *
 * Usage:
 *   node ci/office-origin-preflight.mjs \
 *     --origin=https://office.excelherbal.in \
 *     --expected-sha=40-character-reviewed-Git-SHA \
 *     --output=dist/office-origin-preflight.json
 */
import { writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

function jsonContentType(value = '') {
  return /^application\/(?:[\w.-]+\+)?json(?:[;\s]|$)/i.test(value);
}
function htmlContentType(value = '') {
  return /^text\/html(?:[;\s]|$)/i.test(value);
}
function baseHref(html = '') {
  const match = String(html).match(/<base\s+[^>]*href\s*=\s*["']([^"']+)["']/i);
  return match?.[1] ?? null;
}
function isPluginWebBase(href) {
  return typeof href === 'string' &&
    href.includes('/wp-content/plugins/excel-herbal-erp-v7/web/');
}
function safeJSON(body) {
  try { return JSON.parse(body); } catch { return null; }
}
function rule(id, pass, observed, why) {
  return { id, pass, observed, why };
}

export function analyseOfficeRoutes(probes, expectedSha) {
  const root = probes.root ?? {};
  const preview = probes.preview ?? {};
  const pretty = probes.prettyApi ?? {};
  const query = probes.queryApi ?? {};
  const indexQuery = probes.indexQueryApi ?? {};
  const rootBase = baseHref(root.body);
  const previewBase = baseHref(preview.body);
  const prettyData = safeJSON(pretty.body);
  const queryData = safeJSON(query.body);
  const indexData = safeJSON(indexQuery.body);
  const jsonOk = (response, obj) => response.status === 200 &&
    jsonContentType(response.contentType) &&
    obj?.ok === true && typeof obj?.data === 'object';
  const prettyOk = jsonOk(pretty, prettyData);
  const queryOk = jsonOk(query, queryData);
  const indexQueryOk = jsonOk(indexQuery, indexData);
  const previewOk = preview.status === 200 &&
    htmlContentType(preview.contentType) && isPluginWebBase(previewBase);
  const source = prettyData?.data?.source_head ?? null;
  const shaOk = /^[a-f0-9]{40}$/.test(expectedSha) && source === expectedSha;
  const rootMatches = root.status === 200 &&
    htmlContentType(root.contentType) &&
    previewOk &&
    rootBase === previewBase;
  const legacyRoot = root.status === 200 &&
    typeof rootBase === 'string' &&
    /\/wp-content\/uploads\/eh7-web-[^/]+\//.test(rootBase);
  const rootStaticHint = legacyRoot &&
    Boolean(root.lastModified) && !root.xPoweredBy;
  const tests = [
    rule('reviewed_source', shaOk, source ?? 'unknown',
      'The public health endpoint must report the exact reviewed source SHA.'),
    rule('preview_wordpress_plugin', previewOk, previewBase ?? 'missing base',
      '/erp/ must return the one-plugin Flutter web asset base.'),
    rule('pretty_rest', prettyOk,
      { status: pretty.status ?? null, type: pretty.contentType ?? null },
      '/wp-json/excel-herbal-erp/v7/health must return valid JSON.'),
    rule('query_rest', queryOk,
      { status: query.status ?? null, type: query.contentType ?? null },
      '/?rest_route=/excel-herbal-erp/v7/health must reach WordPress, not an HTML homepage.'),
    rule('homepage_cutover', rootMatches, rootBase ?? 'missing base',
      'The root homepage must serve the same reviewed plugin assets as /erp/.'),
  ];
  const errors = Object.entries(probes)
    .filter(([, p]) => p?.error)
    .map(([key, p]) => ({ probe: key, error: String(p.error).slice(0, 180) }));
  const blockers = tests.filter(x => !x.pass).map(x => x.id);
  return {
    gate: tests.every(x => x.pass) ? 'PASS' : 'BLOCK',
    expectedSource: expectedSha,
    observedSource: source,
    rootBase,
    previewBase,
    rootLegacyAsset: legacyRoot,
    rootStaticInterceptionHint: rootStaticHint,
    queryRestReturnsHomepageHTML: query.status === 200 &&
      htmlContentType(query.contentType) && baseHref(query.body) === rootBase,
    indexPhpQueryWorks: indexQueryOk,
    // A 200 HTML response at /?rest_route= is proof of broken alternate
    // routing, but does not by itself prove the mechanism (cache vs rewrite).
    rootCauseProven: false,
    tests,
    blockers,
    errors,
    productionMutationPerformed: false,
    instructions: blockers.length
      ? 'STOP: no homepage cutover. Collect host document-root index priority, ' +
        'root rewrite rule and both REST formats; confirm backup/restore and ' +
        'role UAT before any host change.'
      : 'Routing and source preflight passed. Backup/restore and staff-role UAT ' +
        'are still separate mandatory gates.',
  };
}

function getArgs(argv) {
  const data = {};
  for (const item of argv) {
    const m = item.match(/^--([\w-]+)=(.*)$/);
    if (!m) throw new Error('Invalid option ' + item);
    data[m[1]] = m[2];
  }
  const origin = data.origin || 'https://office.excelherbal.in';
  const url = new URL(origin);
  if (url.protocol !== 'https:' || url.username || url.password ||
    url.search || url.hash || (url.pathname !== '/' && url.pathname !== '')) {
    throw new Error('Origin must be one HTTPS site root without credentials.');
  }
  if (!/^[a-f0-9]{40}$/.test(data['expected-sha'] ?? '')) {
    throw new Error('--expected-sha must be a reviewed 40-character Git SHA');
  }
  return { origin: url.origin, expectedSha: data['expected-sha'],
    output: data.output ?? null };
}
async function anonymousGet(origin, urlPath) {
  const url = new URL(urlPath, origin).toString();
  try {
    const response = await fetch(url, {
      method: 'GET', redirect: 'follow',
      signal: AbortSignal.timeout(15000),
      headers: { accept: 'application/json, text/html;q=0.9, */*;q=0.5' },
    });
    const body = (await response.text()).slice(0, 35000);
    return {
      status: response.status,
      contentType: response.headers.get('content-type'),
      lastModified: response.headers.get('last-modified'),
      xPoweredBy: response.headers.get('x-powered-by'),
      body,
    };
  } catch (error) {
    return { status: null, contentType: null, body: '',
      error: error instanceof Error ? error.message : 'request_failed' };
  }
}
function reportForStorage(result) {
  // Never persist full page bodies or backend payloads. Public metadata only.
  return { ...result, generatedAt: new Date().toISOString() };
}

async function main() {
  const { origin, expectedSha, output } = getArgs(process.argv.slice(2));
  const paths = {
    root: '/',
    preview: '/erp/',
    prettyApi: '/wp-json/excel-herbal-erp/v7/health',
    queryApi: '/?rest_route=/excel-herbal-erp/v7/health',
    indexQueryApi: '/index.php?rest_route=/excel-herbal-erp/v7/health',
  };
  const entries = await Promise.all(Object.entries(paths).map(async ([key, url]) =>
    [key, await anonymousGet(origin, url)]));
  const result = reportForStorage(analyseOfficeRoutes(
    Object.fromEntries(entries), expectedSha));
  const rendered = JSON.stringify({ origin, ...result }, null, 2) + '\n';
  if (output) {
    const outputPath = path.resolve(output);
    await mkdir(path.dirname(outputPath), { recursive: true });
    await writeFile(outputPath, rendered, { encoding: 'utf8', flag: 'w' });
  }
  process.stdout.write(rendered);
  process.exitCode = result.errors.length ? 1 : result.gate === 'PASS' ? 0 : 2;
}
const entry = process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);
if (entry) main().catch(e => {
  process.stderr.write(String(e?.message ?? e) + '\n');
  process.exitCode = 1;
});
