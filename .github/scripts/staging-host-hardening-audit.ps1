param(
    [Parameter(Mandatory=$true)][string]$ApiBase,
    [Parameter(Mandatory=$true)][string]$Mobile,
    [Parameter(Mandatory=$true)][string]$Password,
    [string]$EvidencePath = 'dist/staging-host-hardening/EVIDENCE.json'
)

$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Net.Http
$ApiBase=$ApiBase.TrimEnd('/')
$uri=[Uri]$ApiBase
if($uri.Scheme -ne 'https'){throw 'Staging API must use HTTPS.'}
if(-not $uri.AbsolutePath.TrimEnd('/').EndsWith('/wp-json/excel-herbal-erp/v7')){throw 'API base must end with /wp-json/excel-herbal-erp/v7.'}

$handler=[System.Net.Http.HttpClientHandler]::new()
$handler.UseCookies=$false
$client=[System.Net.Http.HttpClient]::new($handler)
$client.Timeout=[TimeSpan]::FromSeconds(30)

function Send-Eh7 {
    param([string]$Method,[string]$Path,[object]$Body=$null,[string]$Bearer='')
    $request=[System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method),$ApiBase+$Path)
    try{
        $request.Headers.Accept.ParseAdd('application/json')
        $request.Headers.UserAgent.ParseAdd('EH7-Host-Hardening-Audit/1.0')
        if($Bearer){$request.Headers.Authorization=[System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$Bearer)}
        if($null-ne $Body){
            $json=$Body|ConvertTo-Json -Depth 10 -Compress
            $request.Content=[System.Net.Http.StringContent]::new($json,[System.Text.Encoding]::UTF8,'application/json')
        }
        $response=$client.SendAsync($request).GetAwaiter().GetResult()
        $text=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $parsed=$null
        if($text){try{$parsed=$text|ConvertFrom-Json}catch{}}
        return [pscustomobject]@{Status=[int]$response.StatusCode;Json=$parsed}
    }finally{$request.Dispose()}
}

$evidence=[ordered]@{
    schema_version=1
    gate='environment_hardening'
    target_host=$uri.Host
    api_base=$ApiBase
    tested_at_utc=[DateTime]::UtcNow.ToString('o')
    workflow_source_head=$env:GITHUB_SHA
    run_id=$env:GITHUB_RUN_ID
    status='blocked'
    passed=[ordered]@{}
    blockers=[ordered]@{}
}
$token=''
try{
    $health=Send-Eh7 -Method GET -Path '/health'
    if($health.Status-ne 200-or-not $health.Json.ok){throw "Health check failed HTTP $($health.Status)."}
    $evidence['reported_source_head']=[string]$health.Json.data.source_head
    $evidence['reported_environment']=[string]$health.Json.data.environment

    $hostStatus=$health.Json.data.host_hardening
    if($null-eq $hostStatus){
        $device='gha-host-hardening-'+[Guid]::NewGuid().ToString('N')
        $login=Send-Eh7 -Method POST -Path '/auth/login' -Body @{mobile=$Mobile;password=$Password;device='GitHub host hardening audit';device_id=$device}
        if($login.Status-ne 200-or-not $login.Json.ok){throw "Admin login failed HTTP $($login.Status)."}
        $token=[string]$login.Json.data.access_token
        if(-not $token){throw 'Login did not return an access token.'}
        $diag=Send-Eh7 -Method GET -Path '/administration/diagnostics' -Bearer $token
        if($diag.Status-ne 200-or-not $diag.Json.ok){throw "Diagnostics failed HTTP $($diag.Status)."}
        $hostStatus=$diag.Json.data.host_hardening
    }
    if($null-eq $hostStatus){throw 'Host hardening status is unavailable. Deploy the current backend before auditing.'}

    $evidence.passed['wp_environment_type_defined']=[bool]$hostStatus.wp_environment_type_defined
    $evidence.passed['wp_environment_type']=[string]$hostStatus.wp_environment_type
    $evidence.passed['disallow_file_edit_defined']=[bool]$hostStatus.disallow_file_edit_defined
    $evidence.passed['disallow_file_edit']=[bool]$hostStatus.disallow_file_edit

    if(-not [bool]$hostStatus.wp_environment_type_defined){$evidence.blockers['WP_ENVIRONMENT_TYPE']='undefined'}
    elseif([string]$hostStatus.wp_environment_type-ne 'staging'){$evidence.blockers['WP_ENVIRONMENT_TYPE']=[string]$hostStatus.wp_environment_type}
    if(-not [bool]$hostStatus.disallow_file_edit_defined){$evidence.blockers['DISALLOW_FILE_EDIT']='undefined'}
    elseif(-not [bool]$hostStatus.disallow_file_edit){$evidence.blockers['DISALLOW_FILE_EDIT']='false'}

    if([string]$hostStatus.status-ne 'passed'){throw ('Host hardening is BLOCKED: '+(($evidence.blockers.GetEnumerator()|ForEach-Object{"$($_.Key)=$($_.Value)"})-join ', '))}
    $evidence.status='passed'
    Write-Host 'PASS WP_ENVIRONMENT_TYPE=staging'
    Write-Host 'PASS DISALLOW_FILE_EDIT=true'
}finally{
    if($token){try{[void](Send-Eh7 -Method POST -Path '/auth/logout' -Bearer $token)}catch{}}
    $dir=Split-Path -Parent $EvidencePath
    if($dir){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $evidence|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $EvidencePath -Encoding utf8
    $client.Dispose()
}
Write-Host 'PASSED staging host hardening audit'
