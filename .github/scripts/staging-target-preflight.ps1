param(
    [Parameter(Mandatory=$true)][string]$ApiBase,
    [Parameter(Mandatory=$true)][string]$ExpectedSourceHead,
    [string]$EvidencePath = 'dist/staging-target-preflight/EVIDENCE.json'
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Net.Http
$ApiBase=$ApiBase.TrimEnd('/')
$uri=[Uri]$ApiBase
if($uri.Scheme -ne 'https'){throw 'Staging API must use HTTPS.'}
if($uri.Host -ieq 'office.excelherbal.in'){throw 'Production office host is never a valid staging target.'}
if(-not $uri.AbsolutePath.TrimEnd('/').EndsWith('/wp-json/excel-herbal-erp/v7')){throw 'API base must end with /wp-json/excel-herbal-erp/v7.'}
if($ExpectedSourceHead -notmatch '^[0-9a-fA-F]{40}$'){throw 'ExpectedSourceHead must be a 40-character Git commit SHA.'}
$client=[Net.Http.HttpClient]::new()
$client.Timeout=[TimeSpan]::FromSeconds(30)
function Get-Eh7Json {
    param([string]$Path)
    $resp=$client.GetAsync($ApiBase+$Path).GetAwaiter().GetResult()
    try{
        $text=$resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if([int]$resp.StatusCode -ne 200){throw "$Path returned HTTP $([int]$resp.StatusCode)."}
        $json=$text|ConvertFrom-Json
        if(-not $json.ok){throw "$Path returned ok=false."}
        return $json.data
    } finally {$resp.Dispose()}
}
$evidence=[ordered]@{
    schema_version=1;gate='controlled_staging_preflight';target_host=$uri.Host;api_base=$ApiBase;
    expected_source_head=$ExpectedSourceHead.ToLowerInvariant();tested_at_utc=[DateTime]::UtcNow.ToString('o');
    workflow_source_head=$env:GITHUB_SHA;run_id=$env:GITHUB_RUN_ID;checks=[ordered]@{}
}
try{
    $health=Get-Eh7Json '/health'
    $setup=Get-Eh7Json '/setup/status'
    $contract=Get-Eh7Json '/app/capabilities'
    if([string]$health.environment -ne 'staging'){throw "Target environment must report staging; got '$($health.environment)'."}
    $evidence.checks['environment_staging']='passed'
    if(([string]$health.source_head).ToLowerInvariant() -ne $ExpectedSourceHead.ToLowerInvariant()){throw "Installed source_head '$($health.source_head)' does not match expected '$ExpectedSourceHead'."}
    $evidence.checks['exact_source_head']='passed'
    if($health.staging_safety.required -ne $true){throw 'Health does not require staging safety on this target.'}
    if($health.staging_safety.sanitized -ne $true){throw 'Staging clone has not been sanitized.'}
    if($health.staging_safety.source_head_match -ne $true){throw 'Staging sanitizer marker does not match installed source head.'}
    if($health.staging_safety.active_mobile_sessions_zero -ne $true){throw 'Cloned active mobile sessions remain on staging.'}
    if($health.staging_safety.active_push_devices_zero -ne $true){throw 'Cloned active push devices remain on staging.'}
    if($health.staging_safety.search_indexing_disabled -ne $true){throw 'Staging search indexing is not disabled.'}
    $evidence.checks['staging_clone_sanitized']='passed'
    if($health.schema_installed -ne $true){throw 'Health reports schema_installed=false.'}
    if($setup.schema_installed -ne $true -or $setup.initialized -ne $true){throw 'Setup is not installed and initialized.'}
    if([string]$health.schema -ne [string]$setup.schema_version){throw 'Health/setup schema versions differ.'}
    $evidence.checks['schema_initialized']='passed'
    if([string]$contract.contract_version -ne [string]$health.api_contract){throw 'API contract version mismatch.'}
    if([string]$health.version -eq ''){throw 'ERP version missing from health response.'}
    $evidence.checks['api_contract_consistent']='passed'
    $evidence['reported_version']=[string]$health.version
    $evidence['reported_schema']=[string]$health.schema
    $evidence['reported_contract']=[string]$health.api_contract
    $evidence['reported_source_head']=[string]$health.source_head
    $evidence['reported_environment']=[string]$health.environment
    $evidence['status']='passed'
    Write-Host 'PASS staging_environment'
    Write-Host 'PASS exact_source_head'
    Write-Host 'PASS staging_clone_sanitized'
    Write-Host 'PASS schema_initialized'
    Write-Host 'PASS api_contract_consistent'
} finally {
    $dir=Split-Path -Parent $EvidencePath
    if($dir){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $evidence|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $EvidencePath -Encoding utf8
    $client.Dispose()
}
Write-Host 'PASSED controlled staging target preflight'
