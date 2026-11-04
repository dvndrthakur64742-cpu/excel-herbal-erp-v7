import {readFileSync,writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {splitSqlTopLevel} from './compare-schema-columns.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url));
const SRC=root+'plugin/excel-herbal-erp-v7/src/Database/Schema.php';
const INPUT='D:/ERP7-Release-Candidates/live-index-signatures-20261104.json';
const OUT='D:/ERP7-Release-Candidates/live-schema-index-diff-20261104.json';
export function parseSourceIndexes(source) {
  const expected=new Map();
  const regex=/^\$c\['([a-z0-9_]+)'\]="((?:[^"\\]|\\.)*)";$/gm;
  for(const [,table,sql] of source.matchAll(regex)){
    const indexes=new Map();
    for(const part of splitSqlTopLevel(sql)){
      let name,unique,cols;
      const pk=part.match(/^PRIMARY\s+KEY\s*\(([^)]+)\)/i);
      if(pk){name='PRIMARY';unique=true;cols=pk[1];}
      else{
        const m=part.match(/^(UNIQUE\s+)?KEY\s+([a-z_][\w]*)\s*\(([^)]+)\)/i);
        if(!m)continue;
        name=m[2];unique=Boolean(m[1]);cols=m[3];
      }
      if(indexes.has(name))throw Error('Duplicate expected index '+table+'.'+name);
      indexes.set(name,{unique,columns:cols.split(',').map(x=>x.trim())});
    }
    expected.set(table,indexes);
  }
  return expected;
}
export function parseLiveIndexes(rows,prefix='wp_'){
  const actual=new Map();
  for(const row of rows){
    if(!row.TABLE_NAME.startsWith(prefix+'eh7_'))throw Error('Foreign table');
    const name=row.TABLE_NAME.slice((prefix+'eh7_').length);
    const indexes=new Map();
    const entries=row.index_sig.split('|');
    if(entries.length!==Number(row.index_entry_count))throw Error('Truncated live indexes on '+name);
    for(const entry of entries){
      const m=entry.match(/^([^:]+):([01]):(\d+):([a-z_][\w]*)$/i);
      if(!m)throw Error('Unexpected live index shape '+entry);
      const [,key,nonunique,position,column]=m;
      if(!indexes.has(key))indexes.set(key,{unique:nonunique==='0',columns:[]});
      const obj=indexes.get(key);
      if(obj.unique!==(nonunique==='0')||Number(position)!==obj.columns.length+1)
        throw Error('Unordered or nonuniform live index '+name+'.'+key);
      obj.columns.push(column);
    }
    actual.set(name,indexes);
  }
  return actual;
}
export function compareIndexes(expected,actual){
  const diffs=[],liveOnly=[],sourceOnly=[];
  for(const [table,idx] of expected){
    const live=actual.get(table);
    if(!live){sourceOnly.push(table);continue;}
    const missing=[],extra=[],changed=[];
    for(const [key,shape] of idx){
      const val=live.get(key);
      if(!val)missing.push(key);
      else if(shape.unique!==val.unique||shape.columns.join(',')!==val.columns.join(','))
        changed.push({name:key,source:shape,live:val});
    }
    for(const key of live.keys())if(!idx.has(key))extra.push(key);
    if(missing.length||extra.length||changed.length)diffs.push({table,missing,extra,changed});
  }
  for(const table of actual.keys())if(!expected.has(table))liveOnly.push(table);
  return {expected_tables:expected.size,live_tables:actual.size,shared_tables:expected.size-sourceOnly.length,
    source_only_tables:sourceOnly.sort(),live_only_tables:liveOnly.sort(),
    missing_live_indexes:diffs.reduce((sum,d)=>sum+d.missing.length,0),
    extra_live_indexes:diffs.reduce((sum,d)=>sum+d.extra.length,0),
    changed_indexes:diffs.reduce((sum,d)=>sum+d.changed.length,0),differences:diffs};
}
if(process.argv[1]&&fileURLToPath(import.meta.url).toLowerCase()===process.argv[1].toLowerCase()){
  const data=JSON.parse(readFileSync(INPUT,'utf8'));
  if(data.table_prefix!=='wp_'||data.rows.length!==83)throw Error('Live index inventory incomplete');
  const source=parseSourceIndexes(readFileSync(SRC,'utf8'));
  if(source.size!==85)throw Error('Source table count changed');
  const live=parseLiveIndexes(data.rows,data.table_prefix);
  const result=compareIndexes(source,live);
  writeFileSync(OUT,JSON.stringify({kind:'PRIVATE_READ_ONLY_INDEX_RECONCILIATION',...result},null,2)+'\n');
  console.log(JSON.stringify({...result,differences:result.differences.map(x=>({
    table:x.table,missing:x.missing,extra:x.extra,changed:x.changed.map(y=>y.name)})),
    private_report_path:OUT},null,2));
}
