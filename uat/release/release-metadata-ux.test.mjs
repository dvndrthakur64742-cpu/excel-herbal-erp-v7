import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../../',import.meta.url));
const read=path=>readFileSync(root+path,'utf8');
const schema=read('plugin/excel-herbal-erp-v7/src/Database/Schema.php');
const entry=read('plugin/excel-herbal-erp-v7/excel-herbal-erp-v7.php');
const review=read('.github/workflows/erp-v7-plugin-review-package.yml');
const version=schema.match(/public const VERSION='([^']+)'/)?.[1];
const pluginVersion=entry.match(/\* Version: ([^\r\n]+)/)?.[1];

test('WP review ZIP describes the ACTUAL schema of the checkout',()=>{
 assert.ok(version,'schema constant missing');
 assert.equal(version,'7.3.12-reward-payroll-allocated-6');
 assert.ok(review.includes('Schema version: '+version));
 assert.ok(review.includes("'schema_version': '"+version+"'"));
 assert.ok(review.includes("expected_schema=\"VERSION='"+version+"'\""));
 assert.ok(!review.includes('Schema version: 7.3.12-prepaid-refund-evidence-1'));
});

test('manifest and header pin same reviewed plugin version',()=>{
 assert.equal(pluginVersion,'7.3.12-rc1');
 assert.ok(review.includes('Plugin version: '+pluginVersion));
 assert.ok(review.includes("'plugin_version': '"+pluginVersion+"'"));
 assert.ok(review.includes('STAGING REVIEW ONLY'));
 assert.ok(review.includes('DO NOT install over office.excelherbal.in'));
});

test('Flutter professional UX supports scrolling and accessible Retry at large text',()=>{
 const panel=read('flutter-app/lib/widgets/async_panel.dart');
 const tests=read('flutter-app/test/async_panel_small_phone_test.dart');
 assert.ok((panel.match(/SingleChildScrollView\(/g)||[]).length>=2);
 assert.ok((panel.match(/liveRegion: true/g)||[]).length>=3);
 assert.match(panel,/onPressed: onRetry/);
 assert.match(tests,/TextScaler\.linear\(2\.5\)/);
 assert.match(tests,/320, 480/);
 assert.match(tests,/ensureVisible\(find\.text\('Retry'\)\)/);
 assert.match(tests,/expect\(attempts, 2\)/);
 assert.match(tests,/320, 420/);
});
