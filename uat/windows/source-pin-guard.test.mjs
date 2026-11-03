import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {assertLocalUatSourcePin} from './source-pin-guard.mjs';

const old='2e40eba61d97ef26b543c631682d0701af75b3bd';
const newer='842c6b4c21d2ca631202e5c24875125f2c7e49eb';
const state=(sha=old)=>({
  source_head:sha,
  environment:'staging',
  uat_bootstrap:{
    seeded:true,synthetic_only:true,source_head_match:true,
  },
  staging_safety:{
    sanitized:true,source_head_match:true,
  },
});

test('accepts actual checkout, source marker and synthetic pin equality',()=>{
  assert.doesNotThrow(()=>assertLocalUatSourcePin({
    credentialSha:old,gitSha:old,health:state(),
  }));
});

test('rejects stale source pin after fast-forward even with green WordPress health',()=>{
  assert.throws(()=>assertLocalUatSourcePin({
    credentialSha:old,gitSha:newer,health:state(),
  }),/source mismatch/);
});

test('rejects manually edited marker without matching synthetic identity',()=>{
  assert.throws(()=>assertLocalUatSourcePin({
    credentialSha:old,gitSha:newer,health:state(newer),
  }),/source mismatch/);
});

test('rejects invalid source hashes, missing marker, unsanitized and fake UAT',()=>{
  const bad=[
    {...state(),source_head:'not-a-commit'},
    {...state(),staging_safety:{...state().staging_safety,sanitized:false}},
    {...state(),uat_bootstrap:{...state().uat_bootstrap,synthetic_only:false}},
    {...state(),environment:'production'},
  ];
  for(const health of bad){
    assert.throws(()=>assertLocalUatSourcePin({
      credentialSha:old,gitSha:old,health,
    }));
  }
});

test('local launcher distinguishes healthy pinned UAT from latest-source certification',()=>{
  const launcher=readFileSync(fileURLToPath(new URL('./start-native-uat.ps1',import.meta.url)),'utf8');
  assert.match(launcher,/\$head\s*-ine\s*\$uatHead/i);
  assert.match(launcher,/Latest-source UAT is NOT verified/);
  assert.match(launcher,/back up, review migrations, repin and test/i);
  assert.match(launcher,/\[switch\]\$NoBrowser/);
});

test('local launcher fails closed if mounted plugin commit differs from WordPress health marker',()=>{
  const launcher=readFileSync(fileURLToPath(new URL('./start-native-uat.ps1',import.meta.url)),'utf8');
  assert.match(launcher,/\$mount\.LinkType -ne 'Junction'/);
  assert.match(launcher,/git -C \$mountedPath rev-parse HEAD/);
  assert.match(launcher,/\$mountedHead -ine \$uatHead/);
  assert.match(launcher,/BLOCKED: mounted ERP source is/);
});
