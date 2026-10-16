const port = process.argv[2];
const zipPath = process.argv[3];

if (!port || !zipPath) {
  console.error('usage: node uat_web_upload_cdp.js <port> <zipPath>');
  process.exit(2);
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const pages = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
const page = pages.find((item) =>
  item.type === 'page' &&
  item.url.includes('office.excelherbal.in')
);

if (!page) {
  console.error('EH7 WordPress page not found in headless Chrome.');
  process.exit(3);
}

const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  ws.onopen = resolve;
  ws.onerror = reject;
});

let nextId = 1;
const pending = new Map();
ws.onmessage = (event) => {
  const message = JSON.parse(event.data);
  if (!message.id || !pending.has(message.id)) return;
  const { resolve, reject } = pending.get(message.id);
  pending.delete(message.id);
  if (message.error) reject(new Error(JSON.stringify(message.error)));
  else resolve(message.result || {});
};

function call(method, params = {}) {
  const id = nextId++;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params }));
  });
}

async function evaluate(expression) {
  const result = await call('Runtime.evaluate', {
    expression,
    awaitPromise: true,
    returnByValue: true,
  });
  if (result.exceptionDetails) {
    throw new Error('Browser evaluation failed.');
  }
  return result.result?.value;
}

await call('Page.enable');
await call('DOM.enable');

const before = await evaluate(`(() => ({
  href: location.href,
  path: location.pathname,
  title: document.title,
  fileInputs: document.querySelectorAll('input[type="file"]').length,
  text: (document.body?.innerText || '').slice(0, 3000)
}))()`);

if (!before || /wp-login\.php/i.test(before.path || '') || /log in/i.test(before.title || '')) {
  console.error('WORDPRESS_SESSION_MISSING');
  ws.close();
  process.exit(10);
}

if (!String(before.text || '').includes('Upload Flutter Web Bundle')) {
  console.error('SETUP_UPLOAD_SECTION_MISSING');
  ws.close();
  process.exit(11);
}

const documentNode = await call('DOM.getDocument', { depth: -1, pierce: true });
const fileQuery = await call('DOM.querySelector', {
  nodeId: documentNode.root.nodeId,
  selector: 'input[type="file"]',
});

if (!fileQuery.nodeId) {
  console.error('WEB_BUNDLE_FILE_INPUT_MISSING');
  ws.close();
  process.exit(12);
}

await call('DOM.setFileInputFiles', {
  nodeId: fileQuery.nodeId,
  files: [zipPath],
});

const submitted = await evaluate(`(() => {
  const controls = Array.from(document.querySelectorAll('button,input[type="submit"]'));
  const button = controls.find((el) => {
    const label = (el.textContent || el.value || '').trim();
    return label === 'Upload Web Bundle';
  });
  if (!button) return false;
  button.click();
  return true;
})()`);

if (!submitted) {
  console.error('UPLOAD_WEB_BUNDLE_BUTTON_MISSING');
  ws.close();
  process.exit(13);
}

await sleep(15000);

let after = null;
try {
  after = await evaluate(`(() => ({
    href: location.href,
    title: document.title,
    text: (document.body?.innerText || '').slice(0, 6000)
  }))()`);
} catch (_) {
  await sleep(5000);
  after = await evaluate(`(() => ({
    href: location.href,
    title: document.title,
    text: (document.body?.innerText || '').slice(0, 6000)
  }))()`);
}

const text = String(after?.text || '');
const obviousFailure = /fatal error|upload failed|invalid zip|unsafe zip|permission denied/i.test(text);
console.log(JSON.stringify({
  submitted: true,
  href: after?.href || null,
  title: after?.title || null,
  obviousFailure,
}));
ws.close();

if (obviousFailure) process.exit(14);
