#!/usr/bin/env node
/* F19 synthetic Chrome->Flutter->actual isolated WordPress login smoke.
 * No Office traffic, no production credentials, no real customer/staff data.
 * Browser-visible UAT HTTPS requests are intercepted and answered only from
 * the ephemeral localhost WordPress used by GitHub's synthetic CI.
 */
'use strict';
const fs=require('node:fs/promises');
const path=require('node:path');
const http=require('node:http');
const puppeteer=require(process.env.EH7_PUPPETEER_MODULE ||
  '/tmp/eh7-f19-deps/node_modules/puppeteer-core');

const SHA=process.env.GITHUB_SHA||'';
const WEB=path.resolve(process.argv[2]||'flutter-app/build/web');
const API_HOST='wordpress-uat-production.up.railway.app';
const API_ROOT='/wp-json/excel-herbal-erp/v7';
const LOCAL_ORIGIN='http://127.0.0.1:18880';
const MAX_BODY=4*1024*1024;
const MIME={'.html':'text/html','.js':'text/javascript','.json':'application/json',
  '.wasm':'application/wasm','.css':'text/css','.png':'image/png',
  '.svg':'image/svg+xml','.webp':'image/webp','.woff2':'font/woff2',
  '.woff':'font/woff','.ttf':'font/ttf','.otf':'font/otf'};
function check(v,msg){if(!v)throw Error(msg);}

async function localApi(route,{method='GET',payload,token}={}){
  check(route.startsWith(API_ROOT+'/')&&!route.includes('..'),'Non-ERP local route denied');
  const response=await fetch(LOCAL_ORIGIN+route,{
    method,redirect:'manual',signal:AbortSignal.timeout(14000),
    headers:{Host:API_HOST,Accept:'application/json',
      ...(payload?{'Content-Type':'application/json'}:{}),
      ...(token?{Authorization:'Bearer '+token}:{}),
    },
    body:payload?JSON.stringify(payload):undefined,
  });
  const body=await response.json();
  return {status:response.status,body};
}

async function preflight(){
  check(process.env.GITHUB_ACTIONS==='true'&&
    process.env.EH7_CI_ISOLATED==='1'&&/^[0-9a-f]{40}$/.test(SHA),
    'F19 refuses execution outside exact-source ephemeral GitHub CI');
  const html=await fs.readFile(path.join(WEB,'index.html'),'utf8');
  const main=await fs.readFile(path.join(WEB,'main.dart.js'),'utf8');
  check(/<base href="\/">/.test(html),'F19 expects a localhost-only Flutter UAT root build');
  check(main.includes(API_HOST)&&!main.includes('eh7_live_credentials'),
    'F19 source bundle is not a reviewed synthetic UAT target');
  const health=await localApi(API_ROOT+'/health');
  const d=health.body?.data;
  check(health.status===200&&health.body?.ok===true &&
    d?.source_head===SHA&&d?.environment==='staging'&&
    d?.staging_safety?.sanitized===true&&
    d?.staging_safety?.source_head_match===true&&
    d?.staging_safety?.active_mobile_sessions_zero===true&&
    d?.uat_bootstrap?.seeded===true&&
    d?.uat_bootstrap?.synthetic_only===true&&
    d?.uat_bootstrap?.source_head_match===true,
    'F19 staging/source/active-session safety requirements not met');
}

async function staticServer(){
  const server=http.createServer(async(req,res)=>{
    if(req.method!=='GET'){res.writeHead(405);res.end();return;}
    const u=new URL(req.url||'/',LOCAL_ORIGIN);
    let resource=u.pathname==='/'?'index.html':decodeURIComponent(u.pathname.slice(1));
    let filename=path.resolve(WEB,resource);
    if(!filename.startsWith(WEB+path.sep)){res.writeHead(403);res.end();return;}
    try {
      const bytes=await fs.readFile(filename);
      res.writeHead(200,{'Content-Type':MIME[path.extname(filename)]||'application/octet-stream',
        'Cache-Control':'no-store'});
      res.end(bytes);
    }catch{res.writeHead(404);res.end();}
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  return server;
}
function corsHeaders(){return {
  'Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Methods':'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers':'authorization,x-eh7-authorization,content-type,accept,x-idempotency-key',
  'Access-Control-Max-Age':'0',
  'Cache-Control':'no-store'
};}

async function browserRequest(request,stats,origin){
  try {
    const u=new URL(request.url());
    if(u.origin===origin&&request.method()==='GET') {
      await request.continue();return;
    }
    if(u.protocol!=='https:'||u.host!==API_HOST||
      !u.pathname.startsWith(API_ROOT+'/')||
      u.username||u.password){
      stats.blockedExternal++;
      await request.abort('blockedbyclient');return;
    }
    const relative=u.pathname.slice(API_ROOT.length);
    const method=request.method();
    if(!['GET','OPTIONS'].includes(method)&&
      !(method==='POST'&&['/auth/login','/auth/logout','/auth/refresh'].includes(relative))){
      throw Error('F19 attempted non-auth business mutation: '+relative);
    }
    if(method==='OPTIONS') {
      await request.respond({status:204,headers:corsHeaders(),body:''});
      return;
    }
    const rawBody=request.postData();
    check(!rawBody||Buffer.byteLength(rawBody)<=MAX_BODY,'Oversized synthetic request');
    const h=request.headers();
    const headers={Host:API_HOST,Accept:'application/json'};
    for(const key of ['authorization','x-eh7-authorization','content-type','x-idempotency-key']){
      if(h[key])headers[key]=h[key];
    }
    const response=await fetch(LOCAL_ORIGIN+u.pathname+u.search,{
      method,redirect:'manual',signal:AbortSignal.timeout(14000),
      headers,body:method==='POST'?rawBody:undefined,
    });
    const b=Buffer.from(await response.arrayBuffer());
    check(b.byteLength<=MAX_BODY,'Oversized synthetic backend response');
    const type=response.headers.get('content-type')||'application/json';
    if(relative==='/auth/login'&&response.status===200){
      const data=JSON.parse(b.toString('utf8'));
      if(data?.data?.access_token)stats.tokens.add(data.data.access_token);
      stats.login200++;
    }
    if(relative==='/bootstrap'&&response.status===200){
      const data=JSON.parse(b.toString('utf8'));
      stats.bootstrap200++;
      stats.employeeId=Number(data?.data?.me?.employee?.id)||0;
      stats.navigationCount=data?.data?.navigation?.sections?.length||0;
    }
    if(response.status>=400)stats.failures.push(relative+':'+response.status);
    const replyHeaders={...corsHeaders(),'Content-Type':type};
    await request.respond({status:response.status,headers:replyHeaders,body:b});
  } catch(error) {
    stats.errors.push('Proxy request failed: '+String(error.message).slice(0,150));
    try{await request.abort('failed');}catch{}
  }
}

async function deepSemantics(page) {
  return await page.evaluate(()=>{
    const out=[];
    const visit=(n)=>{
      if(!n)return;
      if(n.nodeType===1){
        const e=n;
        const label=e.getAttribute('aria-label')||e.getAttribute('placeholder')||'';
        if(label)out.push({
          label:label.slice(0,160),
          tag:e.tagName.toLowerCase(),
          role:e.getAttribute('role')||'',
          x:e.getBoundingClientRect().x,y:e.getBoundingClientRect().y,
          w:e.getBoundingClientRect().width,h:e.getBoundingClientRect().height,
        });
        if(e.shadowRoot)visit(e.shadowRoot);
      }
      for(const child of n.children||[])visit(child);
    };
    visit(document.body);
    return out;
  });
}
async function enableSemantics(page) {
  const button=await page.evaluate(()=>{
    function find(n){
      if(!n)return null;
      if(n.nodeType===1){
        if(n.tagName.toLowerCase()==='flt-semantics-placeholder') {
          const r=n.getBoundingClientRect();
          return {x:r.x+r.width/2,y:r.y+r.height/2};
        }
        if(n.shadowRoot){const result=find(n.shadowRoot);if(result)return result;}
      }
      for(const child of n.children||[]){const r=find(child);if(r)return r;}
      return null;
    }
    return find(document.body);
  });
  if(button&&button.x>0&&button.y>0){
    await page.mouse.click(button.x,button.y);
    await new Promise(resolve=>setTimeout(resolve,900));
  }
}
async function clickSemantic(page,pattern) {
  const nodes=await deepSemantics(page);
  const match=nodes.filter(n=>pattern.test(n.label)&&n.w>6&&n.h>6)
    .sort((a,b)=>a.label.length-b.label.length)[0];
  if(!match)throw Error('Missing Flutter accessible control '+pattern+
    '; labels='+nodes.map(x=>x.label).slice(0,24).join('|').slice(0,500));
  await page.mouse.click(match.x+Math.min(match.w/2,45),
    match.y+Math.min(match.h/2,20));
}

async function smokeActor(browser,origin,actor){
  const page=await browser.newPage();
  const stats={login200:0,bootstrap200:0,navigationCount:0,
    employeeId:0,blockedExternal:0,failures:[],errors:[],tokens:new Set()};
  try{
    await page.setViewport({width:actor.width,height:actor.height,
      isMobile:actor.width<600,hasTouch:actor.width<600,deviceScaleFactor:1});
    page.on('pageerror',e=>stats.errors.push('Flutter JS: '+String(e.message).slice(0,150)));
    await page.setRequestInterception(true);
    page.on('request',req=>{void browserRequest(req,stats,origin);});
    const response=await page.goto(origin+'/',{waitUntil:'domcontentloaded',timeout:30000});
    check(response?.status()===200,'Local Flutter root HTTP failure');
    await page.waitForFunction(()=>!!document.querySelector('flutter-view'),{timeout:35000});
    await new Promise(resolve=>setTimeout(resolve,2200));
    await enableSemantics(page);
    const labels=await deepSemantics(page);
    check(labels.some(x=>/mobile number/i.test(x.label))&&
      labels.some(x=>/password/i.test(x.label))&&
      labels.some(x=>/sign in/i.test(x.label)),
      'Flutter accessible Login Screen incomplete: '+
      labels.map(x=>x.label).slice(0,25).join('|').slice(0,500));
    await clickSemantic(page,/mobile number/i);
    await page.keyboard.type(actor.mobile,{delay:15});
    await clickSemantic(page,/password/i);
    await page.keyboard.type(actor.password,{delay:12});
    await clickSemantic(page,/sign in/i);
    await page.waitForFunction(
      ()=>document.querySelector('flutter-view')!==null,
      {timeout:15000}
    );
    // Real auth/identity assertions use the intercepted WordPress JSON
    // responses, NOT static Flutter mocks or a success-looking screenshot.
    for(let i=0;i<28&&stats.bootstrap200===0;i++){
      await new Promise(resolve=>setTimeout(resolve,500));
    }
    check(stats.login200===1,'Flutter UI did not complete synthetic HTTP login');
    check(stats.bootstrap200>=1,'Flutter UI did not fetch authenticated WordPress bootstrap');
    check(stats.employeeId===actor.employeeId,
      'Wrong synthetic employee identity after browser sign-in');
    check(stats.navigationCount>0,'Authenticated Flutter navigation is empty');
    check(stats.errors.length===0,'Flutter/proxy exceptions: '+stats.errors.join(';'));
    console.log('PASS F19 '+actor.label+
      ': real Flutter Chrome login -> isolated WP authenticated bootstrap, navigation='+
      stats.navigationCount+', blockedExternal='+stats.blockedExternal);
  }finally{
    await page.close().catch(()=>{});
    for(const token of stats.tokens){
      const out=await localApi(API_ROOT+'/auth/logout',{method:'POST',token});
      check(out.status===200,'F19 synthetic logout failed');
      const after=await localApi(API_ROOT+'/bootstrap',{token});
      check([401,403].includes(after.status),'F19 revoked synthetic token still active');
    }
  }
}
async function main(){
  await preflight();
  const server=await staticServer();
  const origin='http://127.0.0.1:'+server.address().port;
  const browser=await puppeteer.launch({headless:true,
    executablePath:process.env.CHROME_PATH||'/usr/bin/google-chrome',
    args:['--no-sandbox','--disable-dev-shm-usage','--disable-gpu',
      '--enable-unsafe-swiftshader','--no-first-run',
      '--host-resolver-rules=MAP office.excelherbal.in ~NOTFOUND, MAP wordpress-uat-production.up.railway.app ~NOTFOUND']});
  try{
    await smokeActor(browser,origin,{label:'Employee Mobile',width:390,height:844,
      mobile:'9000000002',password:'eh7_ci_limited_password_only',employeeId:2});
    await smokeActor(browser,origin,{label:'Head Office Desktop',width:1366,height:768,
      mobile:'9000000001',password:'eh7_ci_admin_password_only',employeeId:1});
    console.log('PASS F19 browser-integrated synthetic Employee/Head Office UAT; no production network or business writes');
  }finally{
    await browser.close();
    await new Promise(resolve=>server.close(resolve));
  }
}
main().catch(e=>{console.error('F19_BROWSER_UAT_BLOCKED: '+e.message);process.exitCode=1;});
