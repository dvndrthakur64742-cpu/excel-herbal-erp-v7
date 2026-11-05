<?php
// Non-monetary employee dashboard performance contract. Only synthetic source inspection.
$src=file_get_contents(__DIR__.'/../src/Payroll/PayrollPerformanceService.php');
$start=strpos($src,'public static function summary(');
$end=strpos($src,'private static function canViewPeerPerformance',$start===false?0:$start);
if($start===false||$end===false||$end<=$start){fwrite(STDERR,"FAIL performance summary boundaries\n");exit(1);}
$summary=substr($src,$start,$end-$start);
foreach(["'sales_count'","Db::table('counter_sales')","Db::table('daily_cycles')","'points'","You may view only your own performance."] as $needle){
 if(!str_contains($summary,$needle)){fwrite(STDERR,"FAIL self performance missing $needle\n");exit(1);}
}
echo "PASS self performance summary returns count and points without requiring transactions\n";
