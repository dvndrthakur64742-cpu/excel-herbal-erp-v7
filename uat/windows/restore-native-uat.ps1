#requires -Version 5.1
<#
Restore a previously verified synthetic-only Windows UAT SQL dump into a
BRAND NEW disposable localhost database for disaster-recovery rehearsal.
Never edits the original UAT database, WordPress, its source pin, or live data.
No cleanup/drop is attempted; the new DB remains for inspection.
#>
param(
  [string]$BackupPath='E:\ERP-Backups\eh7-synthetic-checkpoint-20261103-195121',
  [switch]$DryRun
)
$ErrorActionPreference='Stop'
$site='http://127.0.0.1:18880/erp-uat'
$secretsDir='D:\ERP-Local-Secrets'
$secretsPath=Join-Path $secretsDir 'local-uat-db.json'
$mysqlExe='D:\xampp\mysql\bin\mysql.exe'
$backupPath=[System.IO.Path]::GetFullPath($BackupPath).TrimEnd('\')
if($backupPath -notmatch '^E:\\ERP-Backups\\eh7-synthetic-checkpoint-\d{8}-\d{6}$'){
  throw 'Refusing any non-E: synthetic checkpoint backup path'
}
foreach($path in @($mysqlExe,$secretsPath,(Join-Path $backupPath 'manifest.json'),
    (Join-Path $backupPath 'synthetic-wordpress.sql'),
    (Join-Path $backupPath 'synthetic-wordpress.sha256'))){
  if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw ('Backup preflight file missing: '+$path)}
}
$mysqlPorts=@(Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction Stop)
$httpPorts=@(Get-NetTCPConnection -LocalPort 18880 -State Listen -ErrorAction Stop)
foreach($entry in @(@{hits=$mysqlPorts;port=3306},@{hits=$httpPorts;port=18880})){
  if(!$entry.hits.Count -or @($entry.hits | Where-Object {$_.LocalAddress -ne '127.0.0.1'}).Count){
    throw ('Local-only runtime not verified on port '+$entry.port)
  }
}
$health=(Invoke-RestMethod -Uri ($site+'/wp-json/excel-herbal-erp/v7/health') -TimeoutSec 12)
if($health.ok -ne $true -or $health.data.environment -ne 'staging' -or
   $health.data.uat_bootstrap.synthetic_only -ne $true -or
   $health.data.uat_bootstrap.seeded -ne $true -or
   $health.data.staging_safety.sanitized -ne $true -or
   $health.data.staging_safety.active_mobile_sessions_zero -ne $true){
  throw 'Not an isolated, idle and sanitized synthetic localhost UAT'
}
$manifest=Get-Content -LiteralPath (Join-Path $backupPath 'manifest.json') -Raw | ConvertFrom-Json
$secret=Get-Content -LiteralPath $secretsPath -Raw | ConvertFrom-Json
if($manifest.backup_type -ne 'localhost-synthetic-wordpress-db' -or
   $manifest.production_ready -ne $false -or
   $manifest.restore_rehearsal_verified -ne $false -or
   $manifest.database_name -ne 'eh7_local_uat' -or
   $secret.name -ne 'eh7_local_uat' -or
   $secret.site_url -ne $site){
  throw 'Not an approved local synthetic checkpoint / source DB'
}
$dump=Join-Path $backupPath 'synthetic-wordpress.sql'
$length=(Get-Item -LiteralPath $dump).Length
$checksum=(Get-FileHash -LiteralPath $dump -Algorithm SHA256).Hash
$expectedChecksum=(Get-Content -LiteralPath (Join-Path $backupPath 'synthetic-wordpress.sha256') -Raw).Trim()
if($length -lt 10000 -or $length -ne [long]$manifest.sql_bytes -or
   $checksum -ine [string]$manifest.sql_sha256 -or $checksum -ine $expectedChecksum){
  throw 'Backup dump is missing, truncated or fails manifest SHA-256'
}
$dumpText=[System.IO.File]::ReadAllText($dump)
if($dumpText -notmatch '(?m)^-- Host: 127\.0\.0\.1\s+Database: eh7_local_uat' -or
  [regex]::IsMatch($dumpText,'(?im)^\s*(?:CREATE|DROP)\s+DATABASE\b|^\s*USE\s+|^\s*\\!') -or
  $dumpText -match '(?i)' + [regex]::Escape('eh7_local_uat') + '\s*\.'){
  throw 'Backup SQL contains an unsafe database change or unexpected source header'
}
if([string]::IsNullOrEmpty([string]$secret.root_password) -or
   [string]$secret.root_password -match '["\\\r\n]'){
  throw 'Local database administrator credential missing or unsafe for option-file format'
}
$acl=Get-Acl -LiteralPath $secretsDir
foreach($rule in $acl.Access){
  if($rule.AccessControlType -eq 'Allow' -and
    $rule.IdentityReference.Value -match '(^|\\)(Everyone|Users|Authenticated Users)$'){
    throw 'Local secrets folder has broad permissions'
  }
}
Write-Output ('PASS ISOLATED RESTORE PREFLIGHT: verified SQL bytes '+$length+
    ', source '+([string]$manifest.mounted_git_sha).Substring(0,8))
if($DryRun){Write-Output 'DRY RUN: zero DB creation, file writes or changes';return}
$report=Join-Path $backupPath 'restore-rehearsal.json'
if(Test-Path -LiteralPath $report){throw 'Refusing to overwrite previous restore rehearsal report'}
$originalHealthSha=[string]$health.data.source_head
# Authentication file remains inside user-restricted secrets folder and is always removed.
$authFile=Join-Path $secretsDir ('mysql-restore-'+[guid]::NewGuid().ToString('N')+'.tmp')
$target='eh7_restore_'+[guid]::NewGuid().ToString('N').Substring(0,12)
if($target -notmatch '^eh7_restore_[0-9a-f]{12}$'){throw 'Unsafe restore database target'}
$created=$false
try {
  @('[client]','user=root','host=127.0.0.1','port=3306',
    ('password="'+[string]$secret.root_password+'"')) |
    Set-Content -LiteralPath $authFile -Encoding ASCII -ErrorAction Stop
  function Sql([string]$query){
    $result=@(& $mysqlExe "--defaults-extra-file=$authFile" '--protocol=TCP' '--host=127.0.0.1' '--port=3306' '--batch' '--raw' '--skip-column-names' "--execute=$query" 2>&1)
    if($LASTEXITCODE -ne 0){throw ('MariaDB command failed with exit code '+$LASTEXITCODE)}
    return ($result -join [Environment]::NewLine).Trim()
  }
  function Q([string]$value){
    if($value -notmatch '^[a-zA-Z0-9_]+$'){throw 'Unsafe SQL identifier'}
    return ([string][char]96)+$value+([string][char]96)
  }
  $sourceDb=[string]$manifest.database_name
  $namesSql="SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='$sourceDb' AND TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME"
  $originalTables=@((Sql $namesSql) -split '\r?\n' | Where-Object {$_ -ne ''})
  if($originalTables.Count -lt 80){throw 'Unexpectedly few original synthetic WordPress tables'}
  function CountRows([string]$schema,[string[]]$tables){
    $selects=@()
    foreach($table in $tables){
      if($table -notmatch '^[a-zA-Z0-9_]+$'){throw 'Unexpected table name'}
      $selects += ("SELECT '"+$table+"', COUNT(*) FROM "+(Q $schema)+'.'+(Q $table))
    }
    $lines=@((Sql ($selects -join ' UNION ALL ')) -split '\r?\n' | Where-Object {$_ -ne ''})
    $counts=@{}
    foreach($line in $lines){
      $parts=$line.Split([char]9)
      if($parts.Count -ne 2 -or $parts[0] -notmatch '^[a-zA-Z0-9_]+$' -or
        $parts[1] -notmatch '^\d+$'){throw 'Invalid MariaDB table count result'}
      $counts[$parts[0]]=[long]$parts[1]
    }
    if($counts.Count -ne $tables.Count){throw 'Cannot verify every source/restore table count'}
    return $counts
  }
  $before=CountRows $sourceDb $originalTables
  # No IF NOT EXISTS: a collision is a hard failure, never reuse an old DB.
  [void](Sql ("CREATE DATABASE "+(Q $target)+" CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci"))
  $created=$true
  $psi=New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName=$mysqlExe
  $psi.Arguments=("--defaults-extra-file="+$authFile+" --protocol=TCP --host=127.0.0.1 --port=3306 --database="+$target)
  $psi.UseShellExecute=$false
  $psi.CreateNoWindow=$true
  $psi.RedirectStandardInput=$true
  $psi.RedirectStandardError=$true
  $process=New-Object System.Diagnostics.Process
  $process.StartInfo=$psi
  if(!$process.Start()){throw 'Failed to start MariaDB isolated restore client'}
  $stream=[System.IO.File]::OpenRead($dump)
  try {$stream.CopyTo($process.StandardInput.BaseStream)}
  finally {$stream.Dispose();$process.StandardInput.Close()}
  $errorText=$process.StandardError.ReadToEnd()
  $process.WaitForExit()
  if($process.ExitCode -ne 0){throw ('MariaDB import returned '+$process.ExitCode+': '+$errorText.Substring(0,[Math]::Min(200,$errorText.Length)))}
  $restoredTables=@((Sql ("SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='"+$target+"' AND TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME")) -split '\r?\n' | Where-Object {$_ -ne ''})
  if($restoredTables.Count -ne $originalTables.Count -or
    (Compare-Object $originalTables $restoredTables).Count){
    throw 'Restored database has missing, altered or extra tables'
  }
  $after=CountRows $sourceDb $originalTables
  $restored=CountRows $target $restoredTables
  $differences=@($originalTables | Where-Object {
    $name=$_; $before[$name] -ne $after[$name] -or $before[$name] -ne $restored[$name]
  })
  if($differences.Count){throw ('Source or restored table counts differ on '+$differences.Count+' tables')}
  $newHealth=Invoke-RestMethod -Uri ($site+'/wp-json/excel-herbal-erp/v7/health') -TimeoutSec 12
  if($newHealth.ok -ne $true -or [string]$newHealth.data.source_head -ine $originalHealthSha){
    throw 'Original WordPress ERP health/source marker changed during isolated restore'
  }
  $result=[ordered]@{
    backup_type='synthetic_isolated_restore_rehearsal'
    source_checkpoint_sha256=$checksum
    source_mounted_git_sha=[string]$manifest.mounted_git_sha
    source_health_sha=[string]$manifest.wordpress_health_source_sha
    original_database=$sourceDb
    restored_database=$target
    verified_tables=$originalTables.Count
    all_row_counts_equal=$true
    original_row_counts_unchanged=$true
    original_source_marker_changed=$false
    isolated_restore_verified=$true
    production_restore_verified=$false
    logged_at_utc=(Get-Date).ToUniversalTime().ToString('o')
  }
  $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $report -Encoding UTF8
  Write-Output ('PASS ISOLATED RESTORE '+$target+'; verified '+$originalTables.Count+' table row counts, source DB unchanged')
  Write-Output ('REPORT '+$report)
  Write-Output 'ORIGINAL ERP SOURCE STILL MISMATCHED; PRODUCTION NOT VERIFIED'
} catch {
  if($created){Write-Warning ('Isolated restore DB '+$target+' may require manual inspection; original database was not targeted')}
  throw
} finally {
  Remove-Item -LiteralPath $authFile -Force -ErrorAction SilentlyContinue
}
