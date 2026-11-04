#requires -Version 5.1
# Pester-free, offline, temporary-directory-only synthetic backup preflight acceptance.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$tool=Join-Path $PSScriptRoot 'hosted-backup-preflight.ps1'
$root=Join-Path $env:TEMP ('eh7-host-package-test-'+[Guid]::NewGuid().ToString('N'))
function Check([bool]$ok,[string]$description) {
  if(!$ok){throw ('FAIL '+$description)}
  Write-Output ('PASS '+$description)
}
function MustReject([scriptblock]$action,[string]$description) {
  $rejected=$false
  try {& $action | Out-Null} catch {$rejected=$true}
  Check $rejected $description
}
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
  $db=Join-Path $root 'office-synthetic.sql'
  $bad=Join-Path $root 'invalid.sql'
  $archiveRoot=Join-Path $root 'site-source'
  $zip=Join-Path $root 'wordpress-files.zip'
  $report=Join-Path $root 'private-attestation.json'
  $nl=[Environment]::NewLine
  [IO.File]::WriteAllText($db,("-- MySQL dump: dummy fixture only"+$nl+
      "CREATE TABLE wp_test (id INT);"+$nl+('INSERT INTO wp_test VALUES (1);'+$nl)*150))
  [IO.File]::WriteAllText($bad,('INVALID BACKUP DATA'*500))
  $plugin=Join-Path $archiveRoot 'wp-content\plugins\excel-herbal-erp-v7\plugin.php'
  $uploads=Join-Path $archiveRoot 'wp-content\uploads\2026\11\dummy-image.png'
  $config=Join-Path $archiveRoot 'wp-config.php'
  New-Item -ItemType Directory -Path (Split-Path -Parent $plugin) -Force|Out-Null
  New-Item -ItemType Directory -Path (Split-Path -Parent $uploads) -Force|Out-Null
  [IO.File]::WriteAllText($config,'<?php // CI DUMMY CONFIG: NO CREDENTIALS')
  $noise=New-Object byte[] 8192
  $random=New-Object System.Random(12345)
  $random.NextBytes($noise)
  [IO.File]::WriteAllBytes($plugin,$noise)
  $random.NextBytes($noise)
  [IO.File]::WriteAllBytes($uploads,$noise)
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [IO.Compression.ZipFile]::CreateFromDirectory($archiveRoot,$zip)
  & $tool -DatabaseDump $db -WordPressFilesZip $zip -ReportPath $report|Out-Null
  $result=Get-Content -LiteralPath $report -Raw|ConvertFrom-Json
  Check ($result.status -eq 'LOCAL_PACKAGE_PRECHECK_ONLY') 'valid local backup format gets PRECHECK-only attestation'
  Check (!$result.origin_verified -and !$result.database_restored -and
    !$result.wordpress_files_restored -and !$result.rollback_verified -and
    !$result.production_release_authorized) 'preflight cannot claim real hosted restore or deployment'
  Check ($result.database.sha256 -eq (Get-FileHash $db -Algorithm SHA256).Hash) 'local SQL SHA256 matches the evidence'
  MustReject {& $tool -DatabaseDump $bad -WordPressFilesZip $zip -ReportPath $report} 'corrupt SQL header refused'
  MustReject {& $tool -DatabaseDump (Join-Path $root 'missing.sql') -WordPressFilesZip $zip -ReportPath $report} 'missing SQL refused'
  $fakeFolder=Join-Path $root 'eh7-synthetic-checkpoint-incorrect'
  New-Item -Path $fakeFolder -ItemType Directory -Force|Out-Null
  $fake=Join-Path $fakeFolder 'backup.sql'
  Copy-Item -LiteralPath $db -Destination $fake
  MustReject {& $tool -DatabaseDump $fake -WordPressFilesZip $zip -ReportPath $report} 'old synthetic checkpoint refused'
  $badRoot=Join-Path $root 'missing-uploads-site'
  New-Item -ItemType Directory -Path (Join-Path $badRoot 'wp-content\plugins\excel-herbal-erp-v7') -Force|Out-Null
  Copy-Item -LiteralPath $config -Destination (Join-Path $badRoot 'wp-config.php')
  Copy-Item -LiteralPath $plugin -Destination (Join-Path $badRoot 'wp-content\plugins\excel-herbal-erp-v7\plugin.php')
  $incomplete=Join-Path $root 'incomplete-files.zip'
  [IO.Compression.ZipFile]::CreateFromDirectory($badRoot,$incomplete)
  MustReject {& $tool -DatabaseDump $db -WordPressFilesZip $incomplete -ReportPath $report} 'incomplete WordPress ZIP without uploads refused'
  Write-Output 'OFFLINE SYNTHETIC HOST BACKUP PACKAGE GATE PASSED; NO OFFICE WRITE'
} finally {
  if(Test-Path -LiteralPath $root) {Remove-Item -LiteralPath $root -Recurse -Force}
}
