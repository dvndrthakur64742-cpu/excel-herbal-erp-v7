// Deterministic API snapshot updater. Run: node tools/sync-contract-snapshot.mjs
// Never silently skip missing routes; the PHP ApiContract runtime is authoritative.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root=path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const routeSrc=fs.readFileSync(path.join(root,'src/Http/RouteRegistry.php'),'utf8');
const apiSrc=fs.readFileSync(path.join(root,'src/Http/ApiContract.php'),'utf8');
const snapshotPath=path.join(root,'API-CONTRACT-7.3.6.json');
const snapshot=JSON.parse(fs.readFileSync(snapshotPath,'utf8'));
const routes=[...routeSrc.matchAll(/\['(GET|POST)','([^']+)','([^']+)',(true|false)\]/g)]
  .map((m)=>({method:m[1],path:m[2].replaceAll('\\\\','\\'),handler:m[3],auth:m[4]==='true'}));
const expectedVersion=apiSrc.match(/public const VERSION='([^']+)'/);
if(!expectedVersion)throw Error('ApiContract::VERSION not found');

const reqStart=apiSrc.indexOf('private static function required()');
const reqEnd=apiSrc.indexOf('public static function describe()',reqStart);
if(reqStart<0||reqEnd<0)throw Error('Missing required-param declaration');
const reqText=apiSrc.slice(reqStart,reqEnd);
const required=new Map();
for(const match of reqText.matchAll(/'([^']+)'=>\[([^\]]*)\]/g)){
  const values=[...match[2].matchAll(/'([^']+)'/g)].map((m)=>m[1]);
  required.set(match[1],values);
}
const existing=new Map(snapshot.routes.map((r)=>[r.method+' '+r.path,r]));
const result=[];const known=new Set();
for(const r of routes){
  const key=r.method+' '+r.path;
  if(known.has(key))throw Error('Duplicate route '+key);
  known.add(key);
  const old=existing.get(key);
  const needs=required.get(r.handler)||[];
  const idempotencyRequired=r.auth&&r.method!=='GET'&&!r.handler.startsWith('auth.');
  if(old&&(old.auth!==r.auth||old.idempotency_required!==idempotencyRequired)){
    throw Error('Review route authorization change: '+key);
  }
  result.push({method:r.method,path:r.path,auth:r.auth,idempotency_required:idempotencyRequired,required_params:needs});
}
const removed=[...existing.keys()].filter((key)=>!known.has(key));
if(removed.length)throw Error('Routes disappeared from code: '+removed.join(', '));
snapshot.contract_version=expectedVersion[1];
snapshot.routes=result;
const generated=JSON.stringify(snapshot,null,2)+'\n';
if(process.argv.includes('--check')){
  const current=fs.readFileSync(snapshotPath,'utf8');
  if(current!==generated){console.error('Stale API snapshot: run node tools/sync-contract-snapshot.mjs');process.exit(1);}
  console.log('PASS API snapshot matches '+result.length+' routes, contract '+snapshot.contract_version);
}else{
  fs.writeFileSync(snapshotPath,generated);
  console.log('Synced '+result.length+' routes, API contract '+snapshot.contract_version);
}
