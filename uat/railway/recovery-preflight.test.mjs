import test from 'node:test';
import assert from 'node:assert/strict';
import { checkRecovery } from './recovery-preflight.mjs';

function safeSnapshot() {
  const inventory = {
    project: {name:'Excel Herbal ERP - Isolated UAT'},
    environment: {id:'uat-env-id',name:'production'},
    staged:null,
    services:[
      {id:'wp',name:'WordPress-UAT',state:'live',
       source:{repo:'dvndrthakur64742-cpu/excel-herbal-erp-v7',branch:'feature/v7-v15-staging-source-ci-20261031'},
       latestDeployment:{status:'SUCCESS'}},
      {id:'db',name:'MariaDB',state:'live',volumeMounts:[{volumeId:'db-vol',mountPath:'/var/lib/mysql'}]}
    ]
  };
  const changes={staged:null,destructive:false,resources:[]};
  const health={environment:{id:'uat-env-id'},services:[
    {serviceId:'wp',state:'online'}, {serviceId:'db',state:'online'}
  ]};
  return {inventory,changes,health};
}
test('healthy separate UAT is eligible for next synthetic login UAT, not production',()=>{
  const x=safeSnapshot(), result=checkRecovery(x.inventory,x.changes,x.health);
  assert.equal(result.readyForLoginUat,true);
  assert.equal(result.errors.length,0);
  assert.ok(result.warnings.some((v)=>v.includes('source_sha')));
});
test('rejects wrong repository and branch, including old report-export branch',()=>{
  const x=safeSnapshot();
  x.inventory.services[0].source.branch='codex/reports-date-export-workflow';
  x.inventory.services[0].source.repo='another/public-repository';
  const r=checkRecovery(x.inventory,x.changes,x.health);
  assert.equal(r.readyForLoginUat,false);
  assert.ok(r.errors.includes('wrong_source_repo'));
  assert.ok(r.errors.includes('wrong_source_branch'));
});
test('rejects unrelated project even if same service names',()=>{
  const x=safeSnapshot();x.inventory.project.name='Excel Herbal ERP Production';
  assert.ok(checkRecovery(x.inventory,x.changes,x.health).errors.includes('wrong_project'));
});
test('rejects staged deletion rather than accepting destructive environment patch',()=>{
  const x=safeSnapshot();
  x.inventory.staged={status:'STAGED',changeCount:5};
  x.changes={staged:{status:'STAGED',changeCount:5},destructive:true,
    resources:[{kind:'service',name:'WordPress-UAT-Deploy',action:'delete'}]};
  const r=checkRecovery(x.inventory,x.changes,x.health);
  assert.ok(r.errors.includes('unreviewed_staged_patch'));
  assert.ok(r.errors.includes('destructive_staged_patch'));
  assert.equal(r.readyForLoginUat,false);
});
test('rejects offline WordPress and MariaDB, including volume loss',()=>{
  const x=safeSnapshot();
  x.health.services.forEach((v)=>{v.state='offline';});
  x.inventory.services[0].latestDeployment={status:'FAILED'};
  x.inventory.services[1].volumeMounts=[];
  const r=checkRecovery(x.inventory,x.changes,x.health);
  for(const code of ['wordpress_offline','database_offline','database_volume_not_mounted','wordpress_deployment_not_successful']) {
    assert.ok(r.errors.includes(code),code);
  }
});
test('rejects mismatched environment IDs',()=>{
  const x=safeSnapshot(); x.health.environment.id='different-environment';
  assert.ok(checkRecovery(x.inventory,x.changes,x.health).errors.includes('environment_mismatch'));
});
test('current observed UAT problem is blocked before any deployment',()=>{
  const x=safeSnapshot();
  x.inventory.staged={status:'STAGED',changeCount:5};
  x.inventory.services[0].state='live-with-staged-changes';
  x.inventory.services[0].source.branch='codex/reports-date-export-workflow';
  x.inventory.services[0].latestDeployment.status='FAILED';
  x.changes={staged:{status:'STAGED',changeCount:5},destructive:true,resources:[
    {name:'WordPress-UAT-Deploy',action:'delete'}
  ]};
  x.health.services.forEach((v)=>{v.state='offline';});
  const r=checkRecovery(x.inventory,x.changes,x.health);
  assert.equal(r.readyForLoginUat,false);
  for(const code of ['wrong_source_branch','destructive_staged_patch','wordpress_offline','database_offline']) {
    assert.ok(r.errors.includes(code));
  }
});
