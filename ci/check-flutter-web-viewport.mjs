#!/usr/bin/env node
/**
 * F13 Flutter Web runtime zoom gate. Local assets, headless Chrome, no users,
 * credentials, production HTTP requests, or WordPress mutations.
 *
 * node ci/check-flutter-web-viewport.mjs flutter-app/build/web
 * CHROME_PATH can override the executable name on CI/developer machines.
 */
import http from 'node:http';
import path from 'node:path';
import { readFile, mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import { spawn } from 'node:child_process';

const ROOT = path.resolve(process.argv[2] || 'flutter-app/build/web');
const BASE = '/wp-content/uploads/eh7-flutter-web/';
const MIME = {
  '.js': 'text/javascript',
  '.html': 'text/html',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.webp': 'image/webp',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.css': 'text/css',
};
const chrome = process.env.CHROME_PATH || (process.platform === 'win32'
  ? 'C:/Program Files/Google/Chrome/Application/chrome.exe'
  : 'google-chrome');

function htmlViewportTags(html) {
  return [...html.matchAll(/<meta\b[^>]*>/gi)]
    .map(hit => hit[0])
    .filter(tag => /\bname\s*=\s*["']viewport["']/i.test(tag));
}
function viewportConfig(tag) {
  const value = tag?.match(/\bcontent\s*=\s*["']([^"']+)["']/i)?.[1] || '';
  const maximum = value.match(/(?:^|,)\s*maximum-scale\s*=\s*([0-9.]+)/i);
  return {
    engineTagPresent: /\bflt-viewport(?:\s|=|>)/i.test(tag || ''),
    maximumScale: maximum ? Number(maximum[1]) : null,
    zoomDisabled: /\buser-scalable\s*=\s*(?:no|0)\b/i.test(value),
  };
}

async function staticServer() {
  const srv = http.createServer(async (req, res) => {
    const url = new URL(req.url || '/', 'http://127.0.0.1');
    let filename;
    if (url.pathname === '/') {
      filename = path.join(ROOT, 'index.html');
    } else if (url.pathname.startsWith(BASE)) {
      const relative = url.pathname.slice(BASE.length);
      filename = path.resolve(ROOT, relative);
      if (filename !== ROOT && !filename.startsWith(ROOT + path.sep)) {
        res.writeHead(403); res.end(); return;
      }
    } else {
      res.writeHead(404); res.end(); return;
    }
    try {
      const bytes = await readFile(filename);
      res.writeHead(200, { 'Content-Type': MIME[path.extname(filename)] || 'application/octet-stream',
        'Cache-Control': 'no-store' });
      res.end(bytes);
    } catch {
      res.writeHead(404); res.end();
    }
  });
  await new Promise(resolve => srv.listen(0, '127.0.0.1', resolve));
  return srv;
}
async function chromeDOM(url, profilePath) {
  const args = [
    '--headless=new', '--no-sandbox', '--disable-gpu',
    '--disable-dev-shm-usage', '--enable-unsafe-swiftshader',
    '--no-first-run', '--no-default-browser-check',
    '--user-data-dir=' + profilePath,
    // This explicitly disallows any request to the real Office API.
    '--host-resolver-rules=MAP office.excelherbal.in ~NOTFOUND',
    '--virtual-time-budget=18000', '--dump-dom',
    '--window-size=360,780', url,
  ];
  return await new Promise((resolve, reject) => {
    const proc = spawn(chrome, args, { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '', stderr = '';
    const timer = setTimeout(() => proc.kill('SIGKILL'), 55000);
    proc.stdout.on('data', chunk => { stdout += String(chunk).slice(0, 3_000_000); });
    proc.stderr.on('data', chunk => { stderr += String(chunk).slice(0, 1200); });
    proc.on('error', error => { clearTimeout(timer); reject(error); });
    proc.on('close', code => {
      clearTimeout(timer);
      if (code !== 0) reject(new Error('Chrome failed with exit code ' + code +
        ': ' + stderr.slice(0, 250)));
      else resolve(stdout);
    });
  });
}

async function main() {
  const html = await readFile(path.join(ROOT, 'index.html'), 'utf8');
  if (!html.includes('<base href="' + BASE + '">')) {
    throw new Error('Unexpected source base href: refusing to smoke-test unrelated build');
  }
  const server = await staticServer();
  const profile = await mkdtemp(path.join(os.tmpdir(), 'eh7-flutter-zoom-'));
  try {
    const addr = server.address();
    const output = await chromeDOM('http://127.0.0.1:' + addr.port + '/', profile);
    const tags = htmlViewportTags(output);
    const parsed = tags.map(viewportConfig);
    const engine = parsed.find(item => item.engineTagPresent);
    const result = {
      localOnly: true,
      flutterViewLoaded: output.includes('<flutter-view'),
      viewportTagCount: tags.length,
      generatedViewport: engine || null,
      browserZoomPass: !!engine && !engine.zoomDisabled &&
        (engine.maximumScale === null || engine.maximumScale >= 5),
    };
    console.log(JSON.stringify(result, null, 2));
    if (!result.flutterViewLoaded) {
      throw new Error('Flutter app did not initialize in headless Chrome');
    }
    if (!result.browserZoomPass) {
      throw new Error('Flutter engine disabled accessible mobile pinch zoom');
    }
  } finally {
    await new Promise(resolve => server.close(resolve));
    await rm(profile, { recursive: true, force: true });
  }
}
main().catch(error => {
  console.error('F13_WEB_ZOOM_GATE_FAILED: ' + error.message);
  process.exitCode = 1;
});
