param(
    [Parameter(Mandatory=$true)][string]$ApiBase,
    [Parameter(Mandatory=$true)][string]$ExpectedSourceHead,
    [Parameter(Mandatory=$true)][int]$AuthorizedBranchId,
    [Parameter(Mandatory=$true)][int]$ForbiddenBranchId,
    [Parameter(Mandatory=$true)][string]$FinanceMobile,
    [Parameter(Mandatory=$true)][string]$FinancePassword,
    [Parameter(Mandatory=$true)][string]$LimitedMobile,
    [Parameter(Mandatory=$true)][string]$LimitedPassword,
    [switch]$ConfirmedDisposableV8Test,
    [string]$EvidencePath='dist/v8-b2b-dev-http-role-uat/EVIDENCE.json'
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Net.Http
if(-not $ConfirmedDisposableV8Test){throw 'Explicit -ConfirmedDisposableV8Test required; never probe real WordPress.'}
if($AuthorizedBranchId -le 0 -or $ForbiddenBranchId -le 0 -or $AuthorizedBranchId -eq $ForbiddenBranchId){
    throw 'Two different positive branch IDs are required.'
}
if($ExpectedSourceHead -notmatch '^[a-fA-F0-9]{40}$'){throw 'ExpectedSourceHead requires 40 hex characters.'}
$ApiBase=$ApiBase.TrimEnd('/')
$u=[Uri]$ApiBase
if($u.Scheme -ne 'https' -or
   $u.Query -ne '' -or
   $u.Fragment -ne '' -or
   (-not $u.AbsolutePath.TrimEnd('/').EndsWith('/wp-json/excel-herbal-erp/v7'))){
    throw 'Use an HTTPS WordPress ERP V7 API base with no query or fragment.'
}
if($u.Host -in @('office.excelherbal.in','excelherbal.in','www.excelherbal.in')){
    throw 'Live Excel Herbal hosts are explicitly excluded from V8 dev-UAT.'
}
$client=[System.Net.Http.HttpClient]::new()
$client.Timeout=[TimeSpan]::FromSeconds(20)
$financeToken='';$limitedToken=''
$results=[ordered]@{}
function Request-ERP {
    param([string]$Method,[string]$Path,[object]$Body=$null,[string]$Bearer='')
    $req=[System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method),$ApiBase+$Path)
    try{
        $req.Headers.Accept.ParseAdd('application/json')
        if($Bearer){$req.Headers.Authorization=[System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$Bearer)}
        if($null -ne $Body){
            $json=$Body|ConvertTo-Json -Compress -Depth 5
            $req.Content=[System.Net.Http.StringContent]::new($json,[Text.Encoding]::UTF8,'application/json')
        }
        $resp=$client.SendAsync($req).GetAwaiter().GetResult()
        try{
            $text=$resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $data=$null
            try {$data=$text|ConvertFrom-Json}catch{}
            return [pscustomobject]@{Status=[int]$resp.StatusCode;Json=$data}
        }finally{$resp.Dispose()}
    }finally{$req.Dispose()}
}
function Assert-ERP {
    param($Value,[int]$Code,[string]$Label,[string]$ErrorCode='')
    $actualCode=if($Value.Json -and $Value.Json.error){[string]$Value.Json.error.code}else{''}
    if($Value.Status -ne $Code -or ($ErrorCode -and $actualCode -ne $ErrorCode)){
        throw "$($Label): expected HTTP $Code error=$ErrorCode but got $($Value.Status) error=$actualCode"
    }
    $results[$Label]='passed'
    Write-Host "PASS $Label HTTP=$Code"
}
$evidence=[ordered]@{
    schema_version=1;scope='disposable_development_only';endpoint_host=$u.Host;
    tested_at_utc=[DateTime]::UtcNow.ToString('o');
    expected_source_head=$ExpectedSourceHead.ToLowerInvariant();
    finance_branch_id=$AuthorizedBranchId;forbidden_branch_id=$ForbiddenBranchId;
    financial_posting_enabled=$false;external_bank_or_cash_verified=$false;
    checks=$results;status='incomplete'
}
try{
    $health=Request-ERP 'GET' '/health'
    Assert-ERP $health 200 'development_health'
    if([string]$health.Json.data.environment -ne 'development'){throw 'Health must explicitly identify development; staging and production are blocked.'}
    if([string]$health.Json.data.source_head -ne $ExpectedSourceHead){throw 'Source-head mismatch; do not use a different deployment.'}
    if($health.Json.data.schema_installed -ne $true){throw 'Backend reports incomplete schema installation.'}
    $results['exact_development_source_and_schema']='passed'

    $path='/development/b2b-staging-readiness?branch_id='+$AuthorizedBranchId
    Assert-ERP (Request-ERP 'GET' $path) 401 'unauthenticated_probe' 'not_authenticated'

    $financeLogin=Request-ERP 'POST' '/auth/login' @{
        mobile=$FinanceMobile;password=$FinancePassword;
        device='B2B isolated dev-UAT finance';device_id=('b2b-uat-'+[Guid]::NewGuid().ToString('N'))
    }
    Assert-ERP $financeLogin 200 'finance_login'
    $financeToken=[string]$financeLogin.Json.data.access_token
    if(-not $financeToken){throw 'Finance login did not return a bearer token.'}

    $limitedLogin=Request-ERP 'POST' '/auth/login' @{
        mobile=$LimitedMobile;password=$LimitedPassword;
        device='B2B isolated dev-UAT limited';device_id=('b2b-uat-'+[Guid]::NewGuid().ToString('N'))
    }
    Assert-ERP $limitedLogin 200 'limited_login'
    $limitedToken=[string]$limitedLogin.Json.data.access_token
    if(-not $limitedToken){throw 'Limited user login did not return a bearer token.'}

    Assert-ERP (Request-ERP 'GET' $path -Bearer $limitedToken) 403 'limited_user_denied' 'permission_denied'
    Assert-ERP (Request-ERP 'GET' ('/development/b2b-staging-readiness?branch_id='+$ForbiddenBranchId) -Bearer $financeToken) 403 'cross_branch_denied' 'branch_forbidden'
    Assert-ERP (Request-ERP 'GET' '/development/b2b-staging-readiness?branch_id=invalid' -Bearer $financeToken) 422 'malformed_branch_denied' 'parameter_invalid'
    $reply=Request-ERP 'GET' $path -Bearer $financeToken
    Assert-ERP $reply 200 'finance_read_only_preflight'
    $d=$reply.Json.data
    $contractFailed= @(
        $d.read_only -ne $true
        $d.structural_preflight_possible -ne $true
        $d.existing_source_table_count -ne 14
        $d.all_sources_innodb -ne $true
        $d.company_id -le 0
        $d.branch_id -ne $AuthorizedBranchId
        $d.financial_records_disclosed -ne $false
        $d.financial_posting_enabled -ne $false
        $d.production_release_authorized -ne $false
        $d.snapshot_executed -ne $false
    )
    if($contractFailed -contains $true){
        throw 'Structural source contract mismatch or unsafe financial release claim.'
    }
    $results['fourteen_innodb_no_financial_claim']='passed'
    $evidence.status='passed'
}finally{
    foreach($token in @($financeToken,$limitedToken)){
        if($token){try{[void](Request-ERP 'POST' '/auth/logout' -Bearer $token)}catch{}}
    }
    $dir=Split-Path -Parent $EvidencePath
    if($dir){New-Item -ItemType Directory -Force -Path $dir|Out-Null}
    $evidence|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $EvidencePath -Encoding utf8
    $client.Dispose()
}
Write-Host 'PASS B2B isolated WordPress HTTPS role UAT: financial operations were not invoked.'
