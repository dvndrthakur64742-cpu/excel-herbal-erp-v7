param(
    [Parameter(Mandatory=$true)][string]$ApiBase,
    [Parameter(Mandatory=$true)][string]$Mobile,
    [Parameter(Mandatory=$true)][string]$Password,
    [Parameter(Mandatory=$true)][int]$BranchId,
    [Parameter(Mandatory=$true)][string]$From,
    [Parameter(Mandatory=$true)][string]$To,
    [string]$OutputDir = 'dist/staging-report-snapshot'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$ApiBase = $ApiBase.TrimEnd('/')
$uri=[Uri]$ApiBase
if ($uri.Scheme -ne 'https') { throw 'Staging API must use HTTPS.' }
if (-not [DateTime]::TryParseExact($From,'yyyy-MM-dd',$null,[Globalization.DateTimeStyles]::None,[ref]([datetime]$tmpFrom))) { throw 'from must be yyyy-MM-dd.' }
if (-not [DateTime]::TryParseExact($To,'yyyy-MM-dd',$null,[Globalization.DateTimeStyles]::None,[ref]([datetime]$tmpTo))) { throw 'to must be yyyy-MM-dd.' }
if ($tmpFrom -gt $tmpTo) { throw 'from must be on/before to.' }

$client=[Net.Http.HttpClient]::new()
$client.Timeout=[TimeSpan]::FromSeconds(60)
$access=''

function Send-Json {
    param([string]$Method,[string]$Path,[object]$Body=$null,[string]$Bearer='')
    $req=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method),$ApiBase+$Path)
    try {
        $req.Headers.Accept.ParseAdd('application/json')
        $req.Headers.UserAgent.ParseAdd('EH7-Staging-Report-Snapshot/1.0')
        if ($Bearer) { $req.Headers.Authorization=[Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$Bearer) }
        if ($null -ne $Body) {
            $json=$Body|ConvertTo-Json -Depth 10 -Compress
            $req.Content=[Net.Http.StringContent]::new($json,[Text.Encoding]::UTF8,'application/json')
        }
        $resp=$client.SendAsync($req).GetAwaiter().GetResult()
        $text=$resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $json=$null
        try { $json=$text|ConvertFrom-Json } catch {}
        [pscustomobject]@{Status=[int]$resp.StatusCode;Json=$json;Text=$text}
    } finally { $req.Dispose() }
}

function Require-Ok {
    param([object]$Response,[string]$Name)
    if ($Response.Status -ne 200 -or -not $Response.Json -or $Response.Json.ok -ne $true) {
        $code=if($Response.Json -and $Response.Json.error){[string]$Response.Json.error.code}else{''}
        throw "$Name failed HTTP $($Response.Status) code=$code"
    }
}

try {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    $login=Send-Json -Method POST -Path '/auth/login' -Body @{mobile=$Mobile;password=$Password;device='GitHub report snapshot';device_id=('gha-report-' + [Guid]::NewGuid().ToString('N'))}
    Require-Ok $login 'login'
    $access=[string]$login.Json.data.access_token
    if(-not $access){throw 'Login returned no access token.'}

    $qFrom=[Uri]::EscapeDataString($From); $qTo=[Uri]::EscapeDataString($To)
    $defs=[ordered]@{
      sales="/reports/sales?branch_id=$BranchId&from=$qFrom&to=$qTo"
      purchase="/reports/purchase?branch_id=$BranchId&from=$qFrom&to=$qTo"
      stock="/reports/stock?branch_id=$BranchId"
      stock_reconciliation="/reports/stock-reconciliation?branch_id=$BranchId"
      finance="/reports/finance?branch_id=$BranchId&from=$qFrom&to=$qTo"
      trial_balance="/reports/trial-balance?branch_id=$BranchId&to=$qTo"
      profit_loss="/reports/profit-loss?branch_id=$BranchId&from=$qFrom&to=$qTo"
      balance_sheet="/reports/balance-sheet?branch_id=$BranchId&to=$qTo"
      receivables="/reports/receivables?branch_id=$BranchId"
      payables="/reports/payables?branch_id=$BranchId"
      finance_reconciliation="/reports/finance-reconciliation?branch_id=$BranchId"
    }
    $manifest=[ordered]@{
      schema_version=1; gate='business_report_review'; target_host=$uri.Host; api_base=$ApiBase;
      branch_id=$BranchId; from=$From; to=$To; tested_at_utc=[DateTime]::UtcNow.ToString('o');
      commit=$env:GITHUB_SHA; run_id=$env:GITHUB_RUN_ID; reports=[ordered]@{}
    }
    foreach($name in $defs.Keys){
      $r=Send-Json -Method GET -Path $defs[$name] -Bearer $access
      Require-Ok $r $name
      $file=Join-Path $OutputDir ($name+'.json')
      $r.Json | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $file -Encoding utf8
      $hash=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
      $manifest.reports[$name]=[ordered]@{status='passed';sha256=$hash}
      Write-Host "PASS report_$name"
    }
    $manifest['status']='snapshot_ready_for_human_review'
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $OutputDir 'MANIFEST.json') -Encoding utf8
} finally {
    if($access){ try { [void](Send-Json -Method POST -Path '/auth/logout' -Bearer $access) } catch {} }
    $client.Dispose()
}
Write-Host 'PASSED staging report snapshot collection'
