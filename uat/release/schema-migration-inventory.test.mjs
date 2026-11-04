import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {splitSqlTopLevel,parseExpected,parseLive,compare} from './compare-schema-columns.mjs';
import {parseSourceIndexes,parseLiveIndexes,compareIndexes} from './compare-schema-indexes.mjs';
const base=fileURLToPath(new URL('../../',import.meta.url));
const schema=readFileSync(base+'plugin/excel-herbal-erp-v7/src/Database/Schema.php','utf8');

test('SQL lexer preserves numeric DECIMAL(14,2) and composite indexes',()=>{
 const parts=splitSqlTopLevel('id BIGINT UNSIGNED NOT NULL,price DECIMAL(14,2) NOT NULL,UNIQUE KEY uq(a,b),extra VARCHAR(50) NULL');
 assert.equal(parts.length,4);
 assert.equal(parts[1],'price DECIMAL(14,2) NOT NULL');
 assert.equal(parts[2],'UNIQUE KEY uq(a,b)');
});

test('source PHP schema parses 85 tables and preserves signedness + nullability',()=>{
 const tables=parseExpected(schema);
 assert.equal(tables.size,85);
 assert.deepEqual(tables.get('employees').get('id'),{type:'bigintunsigned',nullable:false});
 assert.deepEqual(tables.get('employees').get('reporting_employee_id'),{type:'bigintunsigned',nullable:true});
 assert.deepEqual(tables.get('employees').get('monthly_salary'),{type:'decimal(14,2)',nullable:false});
 assert.ok(tables.get('mobile_sessions').has('device_key'));
});

test('live column mapper catches missing, extra, changed types and nullable constraints',()=>{
 const expected=new Map([['employees',new Map([
  ['id',{type:'bigintunsigned',nullable:false}],
  ['full_name',{type:'varchar(190)',nullable:false}],
  ['mobile',{type:'varchar(30)',nullable:true}]
 ])]]);
 const data=[{TABLE_NAME:'wp_eh7_employees',column_count:'3',
  columns_sig:'id:bigint(20) unsigned:NO,full_name:varchar(120):NO,legacy_flag:tinyint(1):YES'}];
 const result=compare(expected,parseLive(data));
 assert.equal(result.common_tables,1);
 assert.deepEqual(result.differences[0].missing,['mobile']);
 assert.deepEqual(result.differences[0].extra,['legacy_flag']);
 assert.equal(result.differences[0].changed[0].column,'full_name');
 assert.equal(result.changed_live_column_definitions,1);
});

test('incomplete live information_schema cannot silently count as verified',()=>{
 assert.throws(()=>parseLive([{TABLE_NAME:'wp_eh7_employees',column_count:'2',columns_sig:'id:bigint(20) unsigned:NO'}]),
  /incomplete/);
 assert.throws(()=>parseLive([{TABLE_NAME:'wp_wp_users',column_count:'1',columns_sig:'id:bigint:NO'}]),
  /Unexpected live table/);
});

test('index migration detects missing nonunique index but preserves existing ones',()=>{
 const source=parseSourceIndexes(schema);
 assert.equal(source.size,85);
 const mobile=source.get('mobile_sessions');
 assert.deepEqual(mobile.get('employee_device'),{
  unique:false,columns:['employee_id','wp_user_id','device_key']
 });
 const live=parseLiveIndexes([{TABLE_NAME:'wp_eh7_mobile_sessions',index_entry_count:'3',
  index_sig:'PRIMARY:0:1:id|uq_access:0:1:access_hash|uq_refresh:0:1:refresh_hash'}]);
 const comparison=compareIndexes(new Map([['mobile_sessions',mobile]]),live);
 assert.ok(comparison.differences[0].missing.includes('employee_device'));
 assert.equal(comparison.changed_indexes,0);
});

test('schema migration includes data writes and needs rehearsal on a separate copy',()=>{
 assert.match(schema,/dbDelta\(/);
 assert.match(schema,/ensureInterBranchClearingAccounts\(\)/);
 assert.match(schema,/backfillEmployeeBranchHistory\(\)/);
 assert.match(schema,/INSERT INTO \{\$salaryTable\}/);
 assert.match(schema,/DocumentVault::provisionKey\(\)/);
 assert.doesNotMatch(schema,/DROP\s+TABLE|TRUNCATE\s+TABLE/i);
});

test('live snapshot is an inventory only; every write gate remains BLOCKED',()=>{
 const evidence=JSON.parse(readFileSync(base+'uat/release/live-observation-20261104.json','utf8'));
 assert.equal(evidence.counts.employees,27);
 assert.equal(evidence.counts.unexpired_sessions,18);
 assert.equal(evidence.counts.legacy_eoe_tables,190);
 assert.equal(evidence.release_checks.migration_forward_backward_tested,false);
 assert.equal(evidence.release_checks.live_files_and_db_recovery_verified,false);
 assert.equal(evidence.release_checks.session_compatibility_verified,false);
});
