<?php
/**
 * dbDelta requires one field or index on each line.
 * Pure formatter tests: no WordPress installation or database required.
 */
require_once __DIR__.'/../src/Database/Schema.php';

use ExcelHerbal\ERP7\Database\Schema;

function schemaFormatAssert(bool $valid,string $name):void {
    if(!$valid){fwrite(STDERR,"FAIL ".$name."\n");exit(1);}
}
$definitions=Schema::definitions();
schemaFormatAssert(count($definitions)>=70,'all ERP schema tables are included');
foreach($definitions as $name=>$body){
    $formatted=Schema::dbDeltaLines($body);
    schemaFormatAssert(str_contains($formatted,",\n"),
        'dbDelta has separate declarations for '.$name);
    schemaFormatAssert(str_replace(",\n",',',$formatted)===$body,
        'dbDelta formatting preserves exact SQL for '.$name);
    foreach(explode("\n",$formatted) as $line){
        schemaFormatAssert(trim($line)!=='',
            'dbDelta declarations are nonempty for '.$name);
    }
}
$complex="amount DECIMAL(14,2) NOT NULL DEFAULT 0,".
    "scope_key VARCHAR(90) NOT NULL DEFAULT 'north,west',".
    "KEY uq_scope(company_id,branch_id,amount),".
    "note VARCHAR(80) NOT NULL DEFAULT 'it''s valid'";
$expected="amount DECIMAL(14,2) NOT NULL DEFAULT 0,\n".
    "scope_key VARCHAR(90) NOT NULL DEFAULT 'north,west',\n".
    "KEY uq_scope(company_id,branch_id,amount),\n".
    "note VARCHAR(80) NOT NULL DEFAULT 'it''s valid'";
schemaFormatAssert(Schema::dbDeltaLines($complex)===$expected,
    'parser keeps decimal precision, composite index and quoted commas intact');
foreach(['id INT,','id INT,,name VARCHAR(5)','id INT,key(foo', "name VARCHAR(30) DEFAULT 'unclosed"] as $bad){
    $rejected=false;
    try{Schema::dbDeltaLines($bad);}catch(InvalidArgumentException $e){$rejected=true;}
    schemaFormatAssert($rejected,'reject malformed SQL definition');
}
echo "PASSED all ".count($definitions)." WordPress dbDelta migration definitions\n";
