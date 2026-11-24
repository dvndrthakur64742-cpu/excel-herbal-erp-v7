import test from 'node:test';
import assert from 'node:assert/strict';
import {allowedRoute,assertAccess,validateTarget} from './ci-business-role-gate.mjs';

test('F16 permits only GET business reads and POST synthetic auth cleanup',()=>{
  for(const p of ['/workforce/attendance/today','/finance/bootstrap','/payroll/runs','/workforce/gps/team',
    '/inventory/stock?branch_id=1','/sales/orders?branch_id=999','/organization/employees?branch_id=2',
    '/health','/bootstrap']) {
    assert.doesNotThrow(()=>allowedRoute(p,'GET'));
  }
  for(const p of ['/auth/login','/auth/logout']) assert.doesNotThrow(()=>allowedRoute(p,'POST'));
  for(const [p,m] of [
    ['/sales/orders?branch_id=1','POST'],['/inventory/transfers','POST'],
    ['/workforce/attendance/check-in','POST'],['/payroll/runs','DELETE'],
    ['/sales/orders','GET'],['/inventory/stock?branch_id=foo','GET'],
    ['/finance/bootstrap?secret=1','GET'],['/auth/login','GET'],
    ['https://office.excelherbal.in/wp-json/excel-herbal-erp/v7/health','GET'],
    ['/../../wp-json/wp/v2/users','GET']]) {
    assert.throws(()=>allowedRoute(p,m));
  }
});

test('F16 server permission assertions fail on 401, 404, 500, unexpected grant and leaked data',()=>{
  assert.doesNotThrow(()=>assertAccess('attendance',{code:200,body:{ok:true,data:[]}},true));
  assert.doesNotThrow(()=>assertAccess('denied',{code:403,body:{ok:false,error:{code:'permission_denied'}}},false));
  assert.throws(()=>assertAccess('unexpected grant',{code:200,body:{ok:true,data:[]}},false));
  assert.throws(()=>assertAccess('server issue',{code:500,body:{ok:false}},false));
  assert.throws(()=>assertAccess('not found',{code:404,body:{ok:false}},false));
  assert.throws(()=>assertAccess('session expired',{code:401,body:{ok:false}},false));
  assert.throws(()=>assertAccess('denial leaked',{code:403,body:{ok:false,data:[{id:1}]}},false));
});

test('F16 refuses ordinary local execution without ephemeral CI flags',()=>{
  const prior={...process.env};
  try {
    delete process.env.EH7_CI_ISOLATED;
    assert.throws(()=>validateTarget(),/ephemeral GitHub CI/);
  }finally{
    if(prior.EH7_CI_ISOLATED===undefined)delete process.env.EH7_CI_ISOLATED;
    else process.env.EH7_CI_ISOLATED=prior.EH7_CI_ISOLATED;
  }
});
