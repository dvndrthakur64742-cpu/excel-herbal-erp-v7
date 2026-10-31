<?php
// Synthetic-only authority regression: no WordPress accounts or writes.
define('ARRAY_A','ARRAY_A');
require_once __DIR__.'/../src/Domain/DomainException.php';
require_once __DIR__.'/../src/Database/Db.php';
require_once __DIR__.'/../src/Security/Actor.php';
require_once __DIR__.'/../src/Security/Capabilities.php';
require_once __DIR__.'/../src/Security/Guard.php';
require_once __DIR__.'/../src/Security/BranchAuthority.php';
require_once __DIR__.'/../src/Security/HierarchyScope.php';
require_once __DIR__.'/../src/Security/AccessService.php';
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\AccessService;
use ExcelHerbal\ERP7\Domain\DomainException;
class SyntheticAuthDb {public string $prefix='wp_';public function prepare($q,...$args){return vsprintf($q,$args);}public function get_var($q){return 0;}}
$GLOBALS['wpdb']=new SyntheticAuthDb();
$manager=new Actor(5,5,10,20,[20],[Capabilities::ACCESS_MANAGE,Capabilities::EMP_VIEW],'BM');
$sysadmin=new Actor(1,1,10,20,[20],[Capabilities::ACCESS_MANAGE],'SYSADMIN');
function verifyAuthority(bool $condition,string $label):void{if(!$condition){fwrite(STDERR,"FAIL $label\n");exit(1);}echo "PASS $label\n";}
try{AccessService::assertCanDelegateCapabilities($manager,[Capabilities::SALARY_APPROVE]);fwrite(STDERR,"FAIL manager may grant salary approval\n");exit(1);}catch(DomainException $e){verifyAuthority($e->codeKey==='authority_escalation_forbidden','manager cannot grant foreign authority');}
AccessService::assertCanDelegateCapabilities($manager,[Capabilities::ACCESS_MANAGE]);
verifyAuthority(true,'manager can manage own capability');
AccessService::assertCanDelegateCapabilities($sysadmin,[Capabilities::SALARY_APPROVE]);
verifyAuthority(true,'company-wide system authority can delegate role capabilities');
$src=file_get_contents(__DIR__.'/../src/Security/AccessService.php');
foreach(['assertRoleWithinAuthority($a,$roleId)','array_merge($before,$wanted)','array_merge($currentRoleIds,$wanted)',"array_column($before,'capability')",'assertCanAdministerEmployeeIdentity'] as $needle){verifyAuthority(str_contains($src,$needle),'revocation and role mutation guard: '.$needle);}
