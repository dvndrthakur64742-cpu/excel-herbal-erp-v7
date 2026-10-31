<?php
// HR reviewer/manager lifecycle reads are independent of employee-view capability.
$src=file_get_contents(__DIR__.'/../src/Organization/HrLifecycleService.php');
$master=file_get_contents(__DIR__.'/../src/Organization/OrganizationMasterDataService.php');
if(!is_string($src)||!is_string($master))exit(1);
$needs=[
  'Guard::any($a,[Capabilities::HR_VIEW,Capabilities::HR_MANAGE,Capabilities::HR_REVIEW])',
  'Guard::branchAny($a,$branchId,[Capabilities::HR_VIEW,Capabilities::HR_MANAGE,Capabilities::HR_REVIEW])',
  'candidateRowAny($a,$candidateId,[Capabilities::HR_VIEW,Capabilities::HR_MANAGE,Capabilities::HR_REVIEW])',
  '!is_numeric($salaryRaw)||!is_finite((float)$salaryRaw)||(float)$salaryRaw<0',
];
foreach($needs as $needle){if(!str_contains($src,$needle)){fwrite(STDERR,"FAIL HR guard: $needle\n");exit(1);}}
if(!str_contains($master,'Guard::any($a,[Capabilities::EMP_VIEW,Capabilities::EMP_MANAGE,Capabilities::HR_MANAGE])')){fwrite(STDERR,"FAIL HR designation lookup guard\n");exit(1);}
echo "PASS HR manage/review read prerequisites, designation lookup and finite salary validation\n";
