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
    $restored=preg_replace('/\bPRIMARY KEY  \(/','PRIMARY KEY(',$formatted);
    $restored=preg_replace(
        '/\b((?:UNIQUE|FULLTEXT|SPATIAL)\s+KEY|KEY)\s+([a-zA-Z0-9_$-]+) \(/i',
        '$1 $2(',$restored
    );
    schemaFormatAssert(str_replace(",\n",',',$restored)===$body,
        'dbDelta formatting preserves the original field/index semantics for '.$name);
    foreach(explode("\n",$formatted) as $line){
        schemaFormatAssert(trim($line)!=='',
            'dbDelta declarations are nonempty for '.$name);
        if(str_starts_with($line,'PRIMARY KEY')){
            schemaFormatAssert((bool)preg_match('/^PRIMARY KEY  \(/',$line),
                'WordPress recognizes primary key syntax for '.$name);
        }elseif(preg_match('/^(?:UNIQUE KEY|KEY|FULLTEXT KEY|SPATIAL KEY) /',$line)){
            schemaFormatAssert((bool)preg_match(
                '/^(?:UNIQUE KEY|KEY|FULLTEXT KEY|SPATIAL KEY) [a-zA-Z0-9_$-]+ \(/',
                $line
            ),'WordPress recognizes named index syntax for '.$name);
        }
    }
}
$complex="amount DECIMAL(14,2) NOT NULL DEFAULT 0,".
    "scope_key VARCHAR(90) NOT NULL DEFAULT 'north,west',".
    "KEY uq_scope(company_id,branch_id,amount),".
    "note VARCHAR(80) NOT NULL DEFAULT 'it''s valid'";
$expected="amount DECIMAL(14,2) NOT NULL DEFAULT 0,\n".
    "scope_key VARCHAR(90) NOT NULL DEFAULT 'north,west',\n".
    "KEY uq_scope (company_id,branch_id,amount),\n".
    "note VARCHAR(80) NOT NULL DEFAULT 'it''s valid'";
schemaFormatAssert(Schema::dbDeltaLines($complex)===$expected,
    'parser keeps decimal precision, composite index and quoted commas intact');
foreach(['id INT,','id INT,,name VARCHAR(5)','id INT,key(foo', "name VARCHAR(30) DEFAULT 'unclosed"] as $bad){
    $rejected=false;
    try{Schema::dbDeltaLines($bad);}catch(InvalidArgumentException $e){$rejected=true;}
    schemaFormatAssert($rejected,'reject malformed SQL definition');
}
echo "PASSED all ".count($definitions)." WordPress dbDelta migration definitions\n";
