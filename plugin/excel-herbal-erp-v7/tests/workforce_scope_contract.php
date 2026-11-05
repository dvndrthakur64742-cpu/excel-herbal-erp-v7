<?php
// Fail closed on manager-only attendance and pending leave reports.
$src=file_get_contents(__DIR__.'/../src/Workforce/WorkforceService.php');
if(!is_string($src)){fwrite(STDERR,"FAIL workforce service missing\n");exit(1);}
foreach(['a.employee_id IN ({$visible})','lr.employee_id IN ({$visible})',"'mode']==='permanent'",'HierarchyScope::visibleEmployeeIds($a,$branch)'] as $text){
 if(!str_contains($src,$text)){fwrite(STDERR,"FAIL missing workforce hierarchy policy: ".$text."\n");exit(1);}
}
echo "PASS attendance, leave and permanent leave decisions follow reporting hierarchy\n";
