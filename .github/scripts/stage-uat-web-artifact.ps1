param(
  [Parameter(Mandatory = $true)]
  [string]$SourceHead,

  [Parameter(Mandatory = $true)]
  [string]$ArtifactDir
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
  if (-not ($line -cmatch '^([a-f0-9]{64})  (.+)
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

$releaseRoot = Join-Path $env:USERPROFILE ('ERP7-Releases\uat-candidates\' + $SourceHead)
$candidateDir = Join-Path $releaseRoot 'web'
if (Test-Path -LiteralPath $releaseRoot) {
  Remove-Item -LiteralPath $releaseRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $candidateDir -Force | Out-Null
Get-ChildItem -LiteralPath $artifactRoot -Force | Copy-Item -Destination $candidateDir -Recurse -Force
$zipPath = Join-Path $releaseRoot 'Excel-Herbal-ERP-v7.4.0-Web-Candidate.zip'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
  $candidateDir,
  $zipPath,
  [System.IO.Compression.CompressionLevel]::Optimal,
  $false
)
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
  throw 'Verified UAT candidate ZIP was not created.'
}
Write-Host ('PASS hosted_uat_artifact_source_head=' + $SourceHead)
Write-Host ('PASS hosted_uat_artifact_verified_files=' + $manifest.Count)
Write-Host ('PASS hosted_uat_artifact_main_sha256=' + $manifest['main.dart.js'])
Write-Host ('PASS staged_uat_candidate=' + $releaseRoot)
)) {
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

$releaseRoot = Join-Path $env:USERPROFILE ('ERP7-Releases\uat-candidates\' + $SourceHead)
$candidateDir = Join-Path $releaseRoot 'web'
if (Test-Path -LiteralPath $releaseRoot) {
  Remove-Item -LiteralPath $releaseRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $candidateDir -Force | Out-Null
Get-ChildItem -LiteralPath $artifactRoot -Force | Copy-Item -Destination $candidateDir -Recurse -Force
$zipPath = Join-Path $releaseRoot 'Excel-Herbal-ERP-v7.4.0-Web-Candidate.zip'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
  $candidateDir,
  $zipPath,
  [System.IO.Compression.CompressionLevel]::Optimal,
  $false
)
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
  throw 'Verified UAT candidate ZIP was not created.'
}
Write-Host ('PASS hosted_uat_artifact_source_head=' + $SourceHead)
Write-Host ('PASS hosted_uat_artifact_verified_files=' + $manifest.Count)
Write-Host ('PASS hosted_uat_artifact_main_sha256=' + $manifest['main.dart.js'])
Write-Host ('PASS staged_uat_candidate=' + $releaseRoot)
