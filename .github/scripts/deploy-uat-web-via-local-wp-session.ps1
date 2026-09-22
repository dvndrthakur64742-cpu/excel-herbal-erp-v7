param(
  [Parameter(Mandatory = $true)]
  [string]$SourceHead
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ($SourceHead -notmatch '^[a-f0-9]{40}$') {
  throw 'SourceHead must be a 40-character lowercase commit SHA.'
}

$releaseRoot = Join-Path $env:USERPROFILE ('ERP7-Releases\candidates\' + $SourceHead)
$zipPath = Join-Path $releaseRoot 'Excel-Herbal-ERP-v7.4.0-Web-Candidate.zip'
$candidateMain = Join-Path $releaseRoot 'web\main.dart.js'
$driver = Join-Path $env:GITHUB_WORKSPACE '.github\scripts\uat_web_upload_cdp.js'

foreach ($required in @($zipPath, $candidateMain, $driver)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
    throw ('Required deployment file is missing: ' + $required)
  }
}

$expectedMainHash = (Get-FileHash -LiteralPath $candidateMain -Algorithm SHA256).Hash.ToLowerInvariant()
$chromeExe = @(
  'C:\Program Files\Google\Chrome\Application\chrome.exe',
  'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

if (-not $chromeExe) {
  throw 'Google Chrome is unavailable on the self-hosted runner.'
}

$node = Get-Command node.exe -ErrorAction SilentlyContinue
if (-not $node) {
  throw 'node.exe is unavailable on the self-hosted runner.'
}

$chromeRoot = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
$localState = Join-Path $chromeRoot 'Local State'
if (-not (Test-Path -LiteralPath $localState -PathType Leaf)) {
  throw 'Chrome Local State is unavailable.'
}

function Copy-SharedFile {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
  )
  if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
    return $false
  }
  $parent = Split-Path $Destination -Parent
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
  $input = [System.IO.FileStream]::new(
    $Source,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::Read,
    [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
  )
  try {
    $output = [System.IO.FileStream]::new(
      $Destination,
      [System.IO.FileMode]::Create,
      [System.IO.FileAccess]::Write,
      [System.IO.FileShare]::None
    )
    try {
      $input.CopyTo($output)
    }
    finally {
      $output.Dispose()
    }
  }
  finally {
    $input.Dispose()
  }
  return $true
}

function Stop-Eh7HeadlessChrome {
  param([Parameter(Mandatory = $true)][string]$ProfileRoot)
  try {
    Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -and $_.CommandLine.Contains($ProfileRoot) } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  } catch {}
}

function Get-LiveMainHash {
  $tmp = Join-Path $env:RUNNER_TEMP ('eh7-live-main-' + [Guid]::NewGuid().ToString('N') + '.js')
  try {
    $url = 'https://office.excelherbal.in/wp-content/uploads/eh7-flutter-web/main.dart.js?cb=' + [Guid]::NewGuid().ToString('N')
    & curl.exe --fail --location --silent --show-error --max-time 30 --output $tmp $url
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tmp -PathType Leaf)) {
      throw 'Live main.dart.js could not be downloaded for verification.'
    }
    return (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
  }
  finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

$beforeHash = Get-LiveMainHash
Write-Host ('INFO current_live_main_sha256=' + $beforeHash)
Write-Host ('INFO expected_main_sha256=' + $expectedMainHash)

if ($beforeHash -eq $expectedMainHash) {
  Write-Host 'PASS exact-head web candidate is already live.'
  exit 0
}

$profiles = @('Default', 'Profile 1')
$uploaded = $false
$errors = New-Object System.Collections.Generic.List[string]

for ($index = 0; $index -lt $profiles.Count; $index++) {
  $profileName = $profiles[$index]
  $sourceProfile = Join-Path $chromeRoot $profileName
  $cookieSource = Join-Path $sourceProfile 'Network\Cookies'
  if (-not (Test-Path -LiteralPath $cookieSource -PathType Leaf)) {
    $errors.Add($profileName + ': cookie database missing')
    continue
  }

  $tempRoot = Join-Path $env:RUNNER_TEMP ('eh7-wp-session-' + [Guid]::NewGuid().ToString('N'))
  $tempProfile = Join-Path $tempRoot $profileName
  New-Item -ItemType Directory -Path (Join-Path $tempProfile 'Network') -Force | Out-Null

  try {
    Copy-Item -LiteralPath $localState -Destination (Join-Path $tempRoot 'Local State') -Force
    foreach ($name in @('Preferences', 'Secure Preferences')) {
      $source = Join-Path $sourceProfile $name
      if (Test-Path -LiteralPath $source -PathType Leaf) {
        Copy-SharedFile -Source $source -Destination (Join-Path $tempProfile $name) | Out-Null
      }
    }
    Copy-SharedFile -Source $cookieSource -Destination (Join-Path $tempProfile 'Network\Cookies') | Out-Null
    $cookieJournal = $cookieSource + '-journal'
    if (Test-Path -LiteralPath $cookieJournal -PathType Leaf) {
      Copy-SharedFile -Source $cookieJournal -Destination (Join-Path $tempProfile 'Network\Cookies-journal') | Out-Null
    }

    $port = 9320 + $index
    $setupUrl = 'https://office.excelherbal.in/wp-admin/admin.php?page=eh7-setup-assistant&tab=desktop'
    $arguments = @(
      '--headless=new',
      '--disable-gpu',
      '--no-first-run',
      '--no-default-browser-check',
      '--remote-allow-origins=*',
      ('--remote-debugging-port=' + $port),
      ('--user-data-dir=' + $tempRoot),
      ('--profile-directory=' + $profileName),
      $setupUrl
    )

    $started = Start-Process -FilePath $chromeExe -ArgumentList $arguments -PassThru -WindowStyle Hidden
    $ready = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
      Start-Sleep -Milliseconds 250
      try {
        $null = Invoke-RestMethod -UseBasicParsing -Uri ('http://127.0.0.1:' + $port + '/json/version') -TimeoutSec 2
        $ready = $true
        break
      } catch {}
    }
    if (-not $ready) {
      throw 'Headless Chrome did not expose the debugging endpoint.'
    }

    Start-Sleep -Seconds 3
    & $node.Source $driver ([string]$port) $zipPath
    $driverExit = $LASTEXITCODE
    if ($driverExit -ne 0) {
      $errors.Add($profileName + ': upload driver exit ' + $driverExit)
      continue
    }

    Start-Sleep -Seconds 3
    $liveHash = Get-LiveMainHash
    Write-Host ('INFO post_upload_live_main_sha256=' + $liveHash)
    if ($liveHash -eq $expectedMainHash) {
      $uploaded = $true
      Write-Host ('PASS exact-head web candidate deployed using Chrome profile ' + $profileName)
      break
    }
    $errors.Add($profileName + ': upload submitted but live SHA did not match')
  }
  catch {
    $errors.Add($profileName + ': ' + $_.Exception.Message)
  }
  finally {
    Stop-Eh7HeadlessChrome -ProfileRoot $tempRoot
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

if (-not $uploaded) {
  throw ('No authenticated local WordPress profile could complete the exact-head web deployment. ' + ($errors -join ' | '))
}

$finalHash = Get-LiveMainHash
if ($finalHash -ne $expectedMainHash) {
  throw 'Final live main.dart.js hash does not match the certified candidate.'
}
Write-Host ('PASS final_live_main_sha256=' + $finalHash)
