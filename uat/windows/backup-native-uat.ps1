#requires -Version 5.1
<#
Backup only the dedicated Windows localhost synthetic WordPress ERP database.
Fail closed for non-local/suspect environments; NEVER repin, migrate or deploy.
Includes wp-config (locally, with secrets) and a source provenance manifest.
#>
param([switch]$DryRun)
$ErrorActionPreference='Stop'
$site='http://127.0.0.1:18880/erp-uat'
$wp='D:\xampp\htdocs\erp-uat'
$backupRoot='E:\ERP-Backups'
$cfg=Join-Path $wp 'wp-config.php'
$dumpExe='D:\xampp\mysql\bin\mysqldump.exe'
$mountPath=Join-Path $wp 'wp-content\plugins\excel-herbal-erp-v7'
foreach($f in @($cfg,$dumpExe)){
    if(!(Test-Path -LiteralPath $f -PathType Leaf)){throw ('Local UAT dependency missing: '+$f)}
}
foreach($port in @(18880,3306)){
    $listeners=@(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop)
    if(!$listeners.Count -or @($listeners | Where-Object {$_.LocalAddress -ne '127.0.0.1'}).Count){
        throw ('Refusing non-loopback or missing listener: '+$port)
    }
}
$mount=Get-Item -LiteralPath $mountPath -Force -ErrorAction Stop
$targets=@($mount.Target)
if($mount.LinkType -ne 'Junction' -or $targets.Count -ne 1){
    throw 'Synthetic UAT plugin mount must be exactly one local junction'
}
$mountedPlugin=[string]$targets[0]
$repo=& git -C $mountedPlugin rev-parse --show-toplevel 2>$null
if($LASTEXITCODE -ne 0 -or !$repo){throw 'Mounted WordPress plugin has no verified Git checkout'}
$expected=[System.IO.Path]::GetFullPath((Join-Path $repo 'plugin\excel-herbal-erp-v7')).TrimEnd('\')
$actual=[System.IO.Path]::GetFullPath($mountedPlugin).TrimEnd('\')
if($expected -ine $actual -or !$actual.StartsWith('D:\',[System.StringComparison]::OrdinalIgnoreCase)){
    throw 'Mounted ERP plugin is not the canonical local repository plugin'
}
$mountedSha=(& git -C $mountedPlugin rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0 -or $mountedSha -notmatch '^[a-f0-9]{40}$'){
    throw 'Mounted source does not have a valid immutable SHA'
}
if(@(& git -C $repo status --porcelain).Count){throw 'Pinned ERP plugin checkout has uncommitted changes'}
$response=Invoke-RestMethod -Uri ($site+'/wp-json/excel-herbal-erp/v7/health') -TimeoutSec 12
$state=$response.data
if($response.ok -ne $true -or $state.environment -ne 'staging' -or
   $state.uat_bootstrap.seeded -ne $true -or
   $state.uat_bootstrap.synthetic_only -ne $true -or
   $state.staging_safety.sanitized -ne $true -or
   $state.staging_safety.active_mobile_sessions_zero -ne $true){
    throw 'Refusing non-synthetic, unsanitized or active-session ERP backup'
}
$healthSha=[string]$state.source_head
if($healthSha -notmatch '^[a-f0-9]{40}$'){throw 'Invalid WordPress UAT source marker'}
$configText=[System.IO.File]::ReadAllText($cfg)
function Read-Config([string]$name){
    $pattern='define\s*\(\s*[''"]'+[regex]::Escape($name)+'[''"]\s*,\s*([''"])(.*?)\1\s*\)'
    $match=[regex]::Match($configText,$pattern)
    if(!$match.Success){throw ('Unsupported local WordPress config: '+$name)}
    return $match.Groups[2].Value
}
$dbName=Read-Config 'DB_NAME'
$dbUser=Read-Config 'DB_USER'
$dbPass=Read-Config 'DB_PASSWORD'
$dbHost=Read-Config 'DB_HOST'
if($dbHost -notin @('localhost','127.0.0.1','127.0.0.1:3306','localhost:3306')){
    throw 'Refusing remote database backup'
}
if($dbName -notmatch '^[A-Za-z0-9_]+$' -or $dbName -notmatch 'eh7|uat|local'){
    throw 'Database name is not an isolated synthetic UAT database'
}
if($dbUser -match '["\\\r\n]' -or $dbPass -match '["\\\r\n]'){
    throw 'Unsupported credential characters for isolated client option file'
}
if(!(Test-Path -LiteralPath $backupRoot -PathType Container)){throw 'Dedicated E: backup root missing'}
Write-Output ('PASS SYNTHETIC BACKUP PREFLIGHT; MOUNT='+$mountedSha.Substring(0,8)+'; HEALTH='+$healthSha.Substring(0,8))
if($mountedSha -ine $healthSha){
    Write-Warning 'Source mismatch preserved in snapshot metadata; UAT remains BLOCKED for release'
}
if($DryRun){Write-Output 'DRY RUN: no file or database changes';return}
$folder=Join-Path $backupRoot ('eh7-synthetic-checkpoint-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
if(Test-Path -LiteralPath $folder){throw 'Backup destination already exists'}
New-Item -ItemType Directory -Path $folder -ErrorAction Stop | Out-Null
$tempOptions=Join-Path $folder 'mysql-client-options.tmp'
$dump=Join-Path $folder 'synthetic-wordpress.sql'
try {
    @('[client]','host=127.0.0.1','port=3306',('user="'+$dbUser+'"'),('password="'+$dbPass+'"')) |
        Set-Content -LiteralPath $tempOptions -Encoding ASCII -ErrorAction Stop
    & $dumpExe "--defaults-extra-file=$tempOptions" --single-transaction --quick --skip-lock-tables --hex-blob --routines --triggers --events "--result-file=$dump" $dbName
    if($LASTEXITCODE -ne 0){throw 'Synthetic MariaDB dump failed'}
    if(!(Test-Path -LiteralPath $dump) -or (Get-Item -LiteralPath $dump).Length -lt 10000){
        throw 'Synthetic WordPress SQL dump is missing or incomplete'
    }
    Copy-Item -LiteralPath $cfg -Destination (Join-Path $folder 'wp-config-before.php') -ErrorAction Stop
    $checksum=(Get-FileHash -LiteralPath $dump -Algorithm SHA256).Hash
    Set-Content -LiteralPath (Join-Path $folder 'synthetic-wordpress.sha256') -Value $checksum -Encoding ASCII
    $manifest=[ordered]@{
        backup_type='localhost-synthetic-wordpress-db'
        captured_utc=(Get-Date).ToUniversalTime().ToString('o')
        mounted_git_sha=$mountedSha
        wordpress_health_source_sha=$healthSha
        source_matches_health=($mountedSha -ieq $healthSha)
        database_name=$dbName
        sql_bytes=(Get-Item -LiteralPath $dump).Length
        sql_sha256=$checksum
        restore_rehearsal_verified=$false
        production_ready=$false
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $folder 'manifest.json') -Encoding UTF8
    if((Get-FileHash -LiteralPath $dump -Algorithm SHA256).Hash -ne $checksum){
        throw 'Backup SHA256 verification failed'
    }
    Write-Output ('PASS SYNTHETIC CHECKPOINT '+$folder)
    Write-Output ('SQL BYTES '+$manifest.sql_bytes)
    Write-Output 'IMPORTANT: wp-config contains local secrets; keep E: backup private'
    Write-Output 'NOT RESTORE-VERIFIED; NOT RELEASE-APPROVED'
} finally {
    Remove-Item -LiteralPath $tempOptions -Force -ErrorAction SilentlyContinue
}
