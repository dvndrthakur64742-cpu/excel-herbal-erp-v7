#requires -Version 5.1
<#
 Local READ-ONLY Hostinger Office backup-package preflight.
 Never reads or publishes SQL rows, wp-config.php contents, user secrets.
 Never connects to WordPress, imports data, or mutates an input ZIP.
 This is NOT a successful restore; a separate disposable restore is mandatory.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$DatabaseDump,
  [Parameter(Mandatory=$true)][Alias('WordPressFilesZip')][string]$WordPressFilesArchive,
  [string]$ReportPath = 'E:\ERP-Backups\office-hosted-package-preflight.json'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Guard-Input([string]$path,[string]$role) {
  if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "$role not available on this authorized computer"
  }
  $item=Get-Item -LiteralPath $path
  if ($item.Length -lt 4096) { throw "$role too small to certify as a hosted backup package" }
  $absolute=$item.FullName.ToLowerInvariant()
  if ($absolute.Contains('\erp7-development\') -or
      $absolute.Contains('\xampp\htdocs\') -or
      $absolute.Contains('\eh7-synthetic-checkpoint') -or
      $absolute.Contains('\eh7-local-') -or
      $absolute.Contains('\erp7-uat-candidate\')) {
      throw "$role is a source/development or synthetic checkpoint, not a hosted Office backup"
  }
  return $item
}
$db=Guard-Input $DatabaseDump 'Database archive'
$files=Guard-Input $WordPressFilesArchive 'WordPress files archive'
if ($db.FullName -eq $files.FullName) { throw 'Database and files backup must be independent files' }
$dbExt=$db.Name.ToLowerInvariant()
if (!($dbExt.EndsWith('.sql') -or $dbExt.EndsWith('.sql.gz') -or
      $dbExt.EndsWith('.gz') -or $dbExt.EndsWith('.zip'))) {
  throw 'DB archive must be SQL, SQL.gz or ZIP containing SQL'
}
$fileName=$files.Name.ToLowerInvariant()
if (!($fileName.EndsWith('.zip') -or $fileName.EndsWith('.tar.gz'))) {
  throw 'Files archive must be Hostinger .tar.gz or ZIP so its structure can be checked without extraction'
}
function Probe-Magic([System.IO.FileInfo]$item,[byte[]]$sig) {
  $stream=[System.IO.File]::OpenRead($item.FullName)
  try {
    $head=New-Object byte[] $sig.Length
    if ($stream.Read($head,0,$head.Length) -ne $head.Length) {return $false}
    for($i=0;$i -lt $sig.Length;$i++) {if($head[$i] -ne $sig[$i]){return $false}}
    return $true
  } finally { $stream.Dispose() }
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Assert-SqlHeader([System.IO.Stream]$stream) {
  $buffer=New-Object byte[] 65536
  $read=$stream.Read($buffer,0,$buffer.Length)
  if($read -le 0){throw 'Database dump is empty'}
  $header=[System.Text.Encoding]::UTF8.GetString($buffer,0,$read)
  if($header -notmatch '(?i)\b(CREATE TABLE|MySQL dump|MariaDB dump|phpMyAdmin SQL Dump|SET NAMES|SQL_MODE)\b') {
    throw 'Database archive does not contain a recognizable MySQL/MariaDB SQL header in its first 64 KB'
  }
}
function Scan-Zip([System.IO.FileInfo]$item,[string]$purpose) {
  if (!(Probe-Magic $item ([byte[]](0x50,0x4B,0x03,0x04)))) {throw "$purpose ZIP signature invalid"}
  $archive=[System.IO.Compression.ZipFile]::OpenRead($item.FullName)
  try {
    $names=@($archive.Entries | ForEach-Object {$_.FullName.Replace('\','/').ToLowerInvariant()})
    if ($purpose -eq 'DB') {
      $sqlEntry=$archive.Entries | Where-Object {$_.FullName -match '\.sql$'} | Select-Object -First 1
      if (!$sqlEntry) {throw 'No SQL dump in database ZIP'}
      $sqlStream=$sqlEntry.Open()
      try {Assert-SqlHeader $sqlStream} finally {$sqlStream.Dispose()}
      return
    }
    $config=@($names | Where-Object {$_ -match '(^|/)wp-config\.php$'}).Count -gt 0
    $plugin=@($names | Where-Object {$_ -match '(^|/)wp-content/plugins/excel-herbal-erp-v7/'}).Count -gt 0
    $uploads=@($names | Where-Object {$_ -match '(^|/)wp-content/uploads/'}).Count -gt 0
    if (!$config -or !$plugin -or !$uploads) {
      throw 'WordPress file ZIP lacks wp-config.php, ERP plugin or uploads; not a full hosted-files checkpoint'
    }
  } finally { $archive.Dispose() }
}
if ($dbExt.EndsWith('.zip')) {Scan-Zip $db 'DB'}
elseif ($dbExt.EndsWith('.gz')) {
  if (!(Probe-Magic $db ([byte[]](0x1F,0x8B)))) {throw 'Database gzip signature invalid'}
  $compressed=[System.IO.File]::OpenRead($db.FullName)
  try {
    $inflated=New-Object System.IO.Compression.GZipStream($compressed,[System.IO.Compression.CompressionMode]::Decompress)
    try {Assert-SqlHeader $inflated} finally {$inflated.Dispose()}
  } finally {$compressed.Dispose()}
} else {
  $sqlStream=[System.IO.File]::OpenRead($db.FullName)
  try {Assert-SqlHeader $sqlStream} finally {$sqlStream.Dispose()}
}
if ($fileName.EndsWith('.zip')) {Scan-Zip $files 'WP'}
else {
  if (!(Probe-Magic $files ([byte[]](0x1F,0x8B)))) {throw 'Hostinger file archive gzip signature invalid'}
  $tar=Get-Command tar.exe -ErrorAction SilentlyContinue
  if (!$tar) {throw 'tar.exe required to list Hostinger .tar.gz backup safely without extraction'}
  $names=@(& $tar.Source -tzf $files.FullName 2>$null | ForEach-Object {$_.Replace('\','/').ToLowerInvariant()})
  if ($LASTEXITCODE -ne 0) {throw 'Hostinger .tar.gz archive is unreadable'}
  $config=@($names|Where-Object {$_ -match '(^|/)wp-config\.php$'}).Count -gt 0
  $plugin=@($names|Where-Object {$_ -match '(^|/)wp-content/plugins/excel-herbal-erp-v7/'}).Count -gt 0
  $uploads=@($names|Where-Object {$_ -match '(^|/)wp-content/uploads/'}).Count -gt 0
  if (!$config -or !$plugin -or !$uploads) {
    throw 'Hostinger .tar.gz is incomplete: needs wp-config.php, ERP plugin and uploads'
  }
}
$parent=Split-Path -Parent $ReportPath
if (!$parent -or !(Test-Path -LiteralPath $parent -PathType Container)) {
  throw 'Private report destination directory missing'
}
if (([System.IO.Path]::GetFullPath($ReportPath)).ToLowerInvariant().Contains('\erp7-development\')) {
  throw 'Never write backup metadata into Git source'
}
$report=[ordered]@{
  target='office.excelherbal.in'
  status='LOCAL_PACKAGE_PRECHECK_ONLY'
  checked_utc=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
  database=[ordered]@{name=$db.Name;bytes=$db.Length;sha256=(Get-FileHash -LiteralPath $db.FullName -Algorithm SHA256).Hash}
  wordpress=[ordered]@{name=$files.Name;bytes=$files.Length;sha256=(Get-FileHash -LiteralPath $files.FullName -Algorithm SHA256).Hash}
  origin_verified=$false
  database_restored=$false
  wordpress_files_restored=$false
  session_compatibility_verified=$false
  rollback_verified=$false
  production_release_authorized=$false
}
[System.IO.File]::WriteAllText($ReportPath,($report|ConvertTo-Json -Depth 8),[System.Text.UTF8Encoding]::new($false))
Write-Output 'PASS local backup package format, size, and WordPress file structure precheck'
Write-Output 'NOT CERTIFIED: original Hostinger provenance, database restore, sessions and rollback'
Write-Output ('Private report written at: ' + $ReportPath)
