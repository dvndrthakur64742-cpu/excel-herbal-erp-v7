param(
  [Parameter(Mandatory = $true)]
  [string]$SourceHead,

  [Parameter(Mandatory = $true)]
  [string]$ArtifactDir,

  [Parameter(Mandatory = $false)]
  [ValidatePattern('^[a-z0-9-]{1,64}$')]
  [string]$CandidateSlot = 'deploy-uat-current-erp'
)

$ErrorActionPreference = 'Stop'

# Only stage the immutable artifact produced by the exact-head hosted CI job.
if ($SourceHead -cnotmatch '^[a-f0-9]{40}$') {
  throw 'SourceHead must be an exact 40-character lowercase commit SHA.'
}
$artifactRoot = [System.IO.Path]::GetFullPath($ArtifactDir)
if (-not (Test-Path -LiteralPath $artifactRoot -PathType Container)) {
  throw ('Downloaded web artifact directory is missing: ' + $artifactRoot)
}

$manifestFile = Join-Path $artifactRoot 'SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)) {
  throw 'Downloaded web artifact is missing SHA256SUMS.txt.'
}
$manifest = @{}
foreach ($line in @(Get-Content -LiteralPath $manifestFile)) {
  if (-not ($line -cmatch '^([a-f0-9]{64})  (.+)$')) {
    throw ('Invalid SHA-256 manifest entry: ' + $line)
  }
  $expectedHash = $Matches[1]
  $relative = $Matches[2]
  if ($relative -match '(^/|\\|^[A-Za-z]:|(^|/)\.\.?(/|$))') {
    throw ('Unsafe relative path in SHA-256 manifest: ' + $relative)
  }
  if ($manifest.ContainsKey($relative)) { throw ('Duplicate path in SHA-256 manifest: ' + $relative) }
  $filePath = Join-Path $artifactRoot ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
  if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
    throw ('Manifest references a missing web artifact: ' + $relative)
  }
  $actualHash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actualHash -cne $expectedHash) {
    throw ('Downloaded web artifact failed SHA-256 verification: ' + $relative)
  }
  $manifest[$relative] = $expectedHash
}

$payloadFiles = @(Get-ChildItem -LiteralPath $artifactRoot -Recurse -File | Where-Object {
  $_.FullName -ne $manifestFile
})
if ($payloadFiles.Count -ne $manifest.Count) {
  throw ('Web artifact file count differs from SHA-256 manifest: ' + $payloadFiles.Count + ' vs ' + $manifest.Count)
}
foreach ($required in @('index.html', 'main.dart.js', 'flutter_bootstrap.js')) {
  if (-not $manifest.ContainsKey($required)) {
    throw ('Required web artifact missing from SHA-256 manifest: ' + $required)
  }
}

if ($CandidateSlot -cnotmatch '^[a-z0-9-]{1,64}$') { throw 'CandidateSlot must be a safe lowercase identifier.' }
$runSuffix = ''
if ($env:GITHUB_RUN_ID -match '^\d+$') {
  $attempt = if ($env:GITHUB_RUN_ATTEMPT -match '^\d+$') { $env:GITHUB_RUN_ATTEMPT } else { '1' }
  $runSuffix = '-run' + $env:GITHUB_RUN_ID + '-attempt' + $attempt
}
$candidateKey = $SourceHead + $runSuffix + '-slot-' + $CandidateSlot
$releaseRoot = Join-Path $env:USERPROFILE ('ERP7-Releases\uat-candidates\' + $candidateKey)
$candidateDir = Join-Path $releaseRoot 'web'
if (Test-Path -LiteralPath $releaseRoot) {
  Remove-Item -LiteralPath $releaseRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $candidateDir -Force | Out-Null
Get-ChildItem -LiteralPath $artifactRoot -Force | Copy-Item -Destination $candidateDir -Recurse -Force
$zipPath = Join-Path $releaseRoot 'Excel-Herbal-ERP-v7.4.0-Web-Candidate.zip'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
# ZipFile.CreateFromDirectory may emit platform-native separators in entry
# names on Windows. The WordPress UAT handler correctly rejects backslashes.
# Create portable forward-slash-only entries and validate before upload.
$archiveRoot = (Resolve-Path -LiteralPath $candidateDir).Path
$archiveFiles = @(Get-ChildItem -LiteralPath $candidateDir -Recurse -File -Force)
$archive = [System.IO.Compression.ZipFile]::Open(
  $zipPath, [System.IO.Compression.ZipArchiveMode]::Create
)
try {
  foreach ($file in $archiveFiles) {
    $relative = $file.FullName.Substring($archiveRoot.Length).TrimStart([char[]]@([char]92,[char]47))
    $entryName = $relative.Replace([char]92,[char]47)
    if (-not $entryName -or $entryName -match '(^/|\\|^[A-Za-z]:|(^|/)\.\.?(/|$))') {
      throw ('Unsafe portable web ZIP entry: ' + $entryName)
    }
    $entry = $archive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
    $inputStream = [System.IO.File]::OpenRead($file.FullName)
    $entryStream = $entry.Open()
    try { $inputStream.CopyTo($entryStream) }
    finally {
      $entryStream.Dispose()
      $inputStream.Dispose()
    }
  }
} finally { $archive.Dispose() }

if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
  throw 'Verified UAT candidate ZIP was not created.'
}
$check = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
  $entries = @($check.Entries | ForEach-Object { $_.FullName })
  if ($entries.Count -ne $archiveFiles.Count) {
    throw 'ZIP entries do not match the verified artifact file count.'
  }
  foreach ($entryName in $entries) {
    if (-not $entryName -or $entryName -match '(^/|\\|^[A-Za-z]:|(^|/)\.\.?(/|$))') {
      throw ('UAT web ZIP rejected by WordPress-compatible path guard: ' + $entryName)
    }
  }
  foreach ($required in @('index.html', 'main.dart.js', 'flutter_bootstrap.js', 'SHA256SUMS.txt', '.last_build_id')) {
    if ($entries -cnotcontains $required) {
      throw ('Certified UAT ZIP missing required entry: ' + $required)
    }
  }
} finally { $check.Dispose() }
Write-Host ('PASS portable_uat_zip_entries=' + $archiveFiles.Count)
Write-Host ('PASS hosted_uat_artifact_source_head=' + $SourceHead)
Write-Host ('PASS hosted_uat_artifact_verified_files=' + $manifest.Count)
Write-Host ('PASS hosted_uat_artifact_main_sha256=' + $manifest['main.dart.js'])
$zipBytes = (Get-Item -LiteralPath $zipPath).Length
Write-Host ('INFO staged_uat_zip_bytes=' + $zipBytes)
if ($zipBytes -gt 52428800) { throw ('Certified UAT ZIP exceeds the WordPress 50 MiB limit: ' + $zipBytes + ' bytes') }
Write-Host ('PASS staged_uat_candidate=' + $releaseRoot)
