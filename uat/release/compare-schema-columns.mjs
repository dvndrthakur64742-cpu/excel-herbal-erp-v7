import {readFileSync,writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const sourcePath=fileURLToPath(new URL('../../plugin/excel-herbal-erp-v7/src/Database/Schema.php',import.meta.url));
const LIVE='D:/ERP7-Release-Candidates/live-column-signatures-20261104.json';
const REPORT='D:/ERP7-Release-Candidates/live-schema-column-diff-20261104.json';

// Split schema columns without splitting DECIMAL(14,2) or index (a,b) arguments.
export function splitSqlTopLevel(input) {
  const parts=[];let nesting=0,buffer='';
  for(const ch of input){
    if(ch==='(')nesting++;
    if(ch===')')nesting--;
    if(ch===','&&nesting===0){parts.push(buffer.trim());buffer='';continue;}
    buffer+=ch;
  }
  if(buffer.trim())parts.push(buffer.trim());
  if(nesting!==0)throw Error('Unbalanced SQL column declaration');
  return parts;
}

function normalizeType(raw) {
  return raw.trim().toLowerCase()
    .replace(/\b(bigint|int|smallint|mediumint)\(\d+\)/g,'$1')
    .replace(/\s+/g,'');
}

export function parseExpected(source) {
  const tables=new Map();
  const regex=/^\$c\['([a-z0-9_]+)'\]="((?:[^"\\]|\\.)*)";$/gm;
  for(const match of source.matchAll(regex)){
    const [,table,definition]=match;
    const cols=new Map();
    for(const part of splitSqlTopLevel(definition)){
      if(/^(?:PRIMARY\s+KEY|UNIQUE\s+KEY|KEY|INDEX|CONSTRAINT|FOREIGN\s+KEY)\b/i.test(part))continue;
      const p=part.match(/^([a-z_][a-z0-9_]*)\s+([a-z]+(?:\([^)]*\))?)(?:\s|$)/i);
      if(!p)throw Error('Unparsed '+table+' declaration segment: '+part.slice(0,120));
      cols.set(p[1],{
        type:normalizeType(p[2]+(/\bUNSIGNED\b/i.test(part)?' unsigned':'')),
        nullable:/\bNOT\s+NULL\b/i.test(part)?false:/\bNULL\b/i.test(part)?true:null
      });
    }
    if(tables.has(table))throw Error('Duplicate source table '+table);
    tables.set(table,cols);
  }
  return tables;
}

export function parseLive(rows,prefix='wp_') {
  const tables=new Map();
  for(const row of rows) {
    if(!row.TABLE_NAME?.startsWith(prefix+'eh7_'))
      throw Error('Unexpected live table name '+row.TABLE_NAME);
    const name=row.TABLE_NAME.slice((prefix+'eh7_').length);
    const cols=new Map();
    for(const item of splitSqlTopLevel(row.columns_sig)){
      const p=item.match(/^([a-z_][a-z0-9_]*):([^:]+):(YES|NO)$/i);
      if(!p)throw Error('Truncated/unparseable live metadata for '+name+': '+item.slice(0,120));
      cols.set(p[1],{type:normalizeType(p[2]),nullable:p[3]==='YES'});
    }
    if(cols.size!==Number(row.column_count))throw Error('Live metadata incomplete for '+name);
    if(tables.has(name))throw Error('Duplicate live table');
    tables.set(name,cols);
  }
  return tables;
}

export function compare(expected,live){
  const differences=[];
  const sourceOnly=[];
  const liveOnly=[];
  for(const [table,columns] of expected){
    const actual=live.get(table);
    if(!actual){sourceOnly.push(table);continue;}
    const missing=[...columns.keys()].filter(k=>!actual.has(k));
    const extra=[...actual.keys()].filter(k=>!columns.has(k));
    const changed=[];
    for(const [name,expect] of columns){
      const got=actual.get(name);
      if(!got)continue;
      if(expect.type!==got.type|| (expect.nullable!==null&&expect.nullable!==got.nullable)) {
        changed.push({column:name,expected:expect,actual:got});
      }
    }
    if(missing.length||extra.length||changed.length){
      differences.push({table,missing,extra,changed});
    }
  }
  for(const table of live.keys()){if(!expected.has(table))liveOnly.push(table);}
  return {
    source_tables:expected.size,live_tables:live.size,
    common_tables:expected.size-sourceOnly.length,
    missing_tables_on_live:sourceOnly.sort(),
    live_only_tables:liveOnly.sort(),
    differing_common_tables:differences.length,
    missing_live_columns:differences.reduce((sum,d)=>sum+d.missing.length,0),
    extra_live_columns:differences.reduce((sum,d)=>sum+d.extra.length,0),
    changed_live_column_definitions:differences.reduce((sum,d)=>sum+d.changed.length,0),
    differences
  };
}

if(process.argv[1] && fileURLToPath(import.meta.url).toLowerCase()===process.argv[1].toLowerCase()){
  const liveData=JSON.parse(readFileSync(LIVE,'utf8'));
  if(liveData.table_prefix!=='wp_'||liveData.rows.length!==83)
    throw Error('Refusing unverified or incomplete live 83-table metadata inventory');
  const expected=parseExpected(readFileSync(sourcePath,'utf8'));
  if(expected.size!==85)throw Error('Expected exact 85 canonical source tables; schema changed');
  const actual=parseLive(liveData.rows,liveData.table_prefix);
  const result=compare(expected,actual);
  writeFileSync(REPORT,JSON.stringify({kind:'PRIVATE_READ_ONLY_COLUMN_RECONCILIATION',source_git_schema_version:'7.3.12-reward-payroll-allocated-6',...result},null,2)+'\n');
  console.log(JSON.stringify({
    source_tables:result.source_tables,live_tables:result.live_tables,
    common_tables:result.common_tables,
    missing_tables_on_live:result.missing_tables_on_live,
    live_only_tables:result.live_only_tables,
    differing_common_tables:result.differing_common_tables,
    missing_live_columns:result.missing_live_columns,
    extra_live_columns:result.extra_live_columns,
    changed_live_column_definitions:result.changed_live_column_definitions,
    changed_table_names:result.differences.map(x=>x.table),
    private_report_path:REPORT
  },null,2));
}
