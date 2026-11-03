#requires -Version 5.1
<#
Free Windows localhost-only ERP UAT launcher.
Never installs Windows services, changes Firewall, runs migrations,
resets passwords, or connects to the production office website.
#>
param([string]$XamppRoot='D:\xampp',[switch]$NoBrowser)
$ErrorActionPreference='Stop'
$Url='http://127.0.0.1:18880/erp-uat'
function Assert-Listener([int]$port,[string]$expectedExe){
    $hits=@(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
    foreach($hit in $hits){
        if($hit.LocalAddress -ne '127.0.0.1'){
            throw ('Port '+$port+' is not loopback-only: '+$hit.LocalAddress)
        }
        $process=Get-Process -Id $hit.OwningProcess -ErrorAction Stop
        if(!$process.Path -or !$process.Path.Equals($expectedExe,[System.StringComparison]::OrdinalIgnoreCase)){
            throw ('Port '+$port+' is occupied by another installation')
        }
    }
    return $hits.Count -gt 0
}
function Wait-Listener([int]$port,[string]$expectedExe){
    for($i=0;$i -lt 30;$i++){
        Start-Sleep -Milliseconds 500
        if(Assert-Listener $port $expectedExe){return}
    }
    throw ('Timed out starting localhost service on '+$port)
}
$dbExe=Join-Path $XamppRoot 'mysql\bin\mysqld.exe'
$dbIni=Join-Path $XamppRoot 'mysql\bin\my.ini'
$apacheExe=Join-Path $XamppRoot 'apache\bin\httpd.exe'
$apacheIni=Join-Path $XamppRoot 'apache\conf\httpd.conf'
foreach($p in @($dbExe,$dbIni,$apacheExe,$apacheIni)){
    if(!(Test-Path $p -PathType Leaf)){throw ('Required native XAMPP runtime missing: '+$p)}
}
$dbOn=Assert-Listener 3306 $dbExe
$apacheOn=Assert-Listener 18880 $apacheExe
if(!$dbOn){
    Write-Host 'Starting localhost MariaDB...'
    $args=@("--defaults-file=$dbIni",'--console')
    Start-Process -FilePath $dbExe -ArgumentList $args -WorkingDirectory (Split-Path $dbExe -Parent) -WindowStyle Hidden
    Wait-Listener 3306 $dbExe
}
if(!$apacheOn){
    Write-Host 'Starting localhost Apache...'
    $args=@('-f',$apacheIni)
    Start-Process -FilePath $apacheExe -ArgumentList $args -WorkingDirectory (Split-Path $apacheExe -Parent) -WindowStyle Hidden
    Wait-Listener 18880 $apacheExe
}
try{
    $response=Invoke-WebRequest -Uri ($Url+'/wp-json/excel-herbal-erp/v7/health') -TimeoutSec 12 -UseBasicParsing
    $result=$response.Content|ConvertFrom-Json
    if($response.StatusCode -ne 200 -or !$result.ok -or
       $result.data.environment -ne 'staging' -or
       !$result.data.uat_bootstrap.seeded -or
       !$result.data.uat_bootstrap.synthetic_only -or
       !$result.data.uat_bootstrap.source_head_match -or
       !$result.data.staging_safety.sanitized){
        throw 'Not a healthy, sanitized and pinned synthetic-only ERP'
    }
}catch{throw ('ERP Health Check failed: '+$_.Exception.Message)}
# This health check certifies the intentionally pinned UAT runtime, NOT the
# latest GitHub checkout. Warn when developers are editing a newer source.
# Never change the database/source marker or start a deployment here.
$checkoutRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$head=& git -C $checkoutRoot rev-parse HEAD 2>$null
if($LASTEXITCODE -ne 0 -or $head -notmatch '^[a-f0-9]{40}$'){
    throw 'Cannot identify current development Git HEAD'
}
$uatHead=[string]$result.data.source_head
if($uatHead -notmatch '^[a-f0-9]{40}$'){throw 'UAT source marker is not a full Git SHA'}
Write-Host ('PASS: Windows-native localhost synthetic ERP is healthy at '+$uatHead.Substring(0,8))
if($head -ine $uatHead){
    Write-Warning ('UAT is pinned to '+$uatHead.Substring(0,8)+', but development HEAD is '+$head.Substring(0,8)+'. Latest-source UAT is NOT verified. Back up, review migrations, repin and test before release.')
}else{
    Write-Host 'PASS: Local UAT source marker matches development Git HEAD'
}
Write-Host ('Open: '+$Url+'/wp-admin/')
if(!$NoBrowser){Start-Process ($Url+'/wp-admin/')}
