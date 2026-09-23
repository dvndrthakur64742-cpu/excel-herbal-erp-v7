param(
  [Parameter(Mandatory = $true)]
  [string]$SourceHead
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if ($SourceHead -notmatch '^[a-f0-9]{40}$') {
  throw 'SourceHead must be a 40-character lowercase commit SHA.'
}

$repoRoot = $env:GITHUB_WORKSPACE
$releaseRoot = Join-Path $env:USERPROFILE ('ERP7-Releases\candidates\' + $SourceHead)
$webZip = Join-Path $releaseRoot 'Excel-Herbal-ERP-v7.4.0-Web-Candidate.zip'
$candidateMain = Join-Path $releaseRoot 'web\main.dart.js'
foreach ($required in @($webZip,$candidateMain)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
    throw ('Required certified web candidate file is missing: ' + $required)
  }
}
$expectedMainHash = (Get-FileHash -LiteralPath $candidateMain -Algorithm SHA256).Hash.ToLowerInvariant()

function Get-ChromeExe {
  $candidate = @(
    (Get-Command chrome.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
    'C:\Program Files\Google\Chrome\Application\chrome.exe',
    'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
  if (-not $candidate) { throw 'Chrome executable was not found.' }
  return $candidate
}

function Open-DedicatedChromeWindow([string]$Url,[string]$TitlePattern) {
  $before = @{}
  Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | ForEach-Object {
    $before[[string]$_.MainWindowHandle] = $true
  }

  Start-Process -FilePath (Get-ChromeExe) -ArgumentList @('--new-window',$Url) | Out-Null

  for ($attempt=0; $attempt -lt 24; $attempt++) {
    Start-Sleep -Milliseconds 500
    $windows = @(Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 })
    $newWindow = $windows | Where-Object { -not $before.ContainsKey([string]$_.MainWindowHandle) } | Select-Object -First 1
    if ($newWindow) { return $newWindow }

    $anyMatch = $windows | Where-Object { $_.MainWindowTitle -match $TitlePattern } | Select-Object -First 1
    if ($anyMatch) { return $anyMatch }
  }

  $windows = @(Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 })
  $fallback = $windows | Where-Object { $_.MainWindowTitle -match 'office|EH7|Excel Herbal|WordPress' } | Select-Object -First 1
  if (-not $fallback) { $fallback = $windows | Select-Object -First 1 }
  if ($fallback) {
    $shell = New-Object -ComObject WScript.Shell
    if ($shell.AppActivate($fallback.Id)) {
      Start-Sleep -Milliseconds 300
      [System.Windows.Forms.SendKeys]::SendWait('^l')
      Start-Sleep -Milliseconds 150
      [System.Windows.Forms.Clipboard]::SetText($Url)
      [System.Windows.Forms.SendKeys]::SendWait('^v')
      [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
      Start-Sleep -Seconds 5
      return (Get-Process -Id $fallback.Id -ErrorAction Stop)
    }
  }

  throw ('Chrome page did not open: ' + $Url)
}

function Root([System.Diagnostics.Process]$Process) {
  $fresh = Get-Process -Id $Process.Id -ErrorAction Stop
  return [System.Windows.Automation.AutomationElement]::FromHandle($fresh.MainWindowHandle)
}

function Find-ById([System.Windows.Automation.AutomationElement]$Root,[string]$Id) {
  $condition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::AutomationIdProperty,$Id
  )
  return $Root.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$condition)
}

function Find-ByName([System.Windows.Automation.AutomationElement]$Root,[string]$Name,[bool]$Like=$false) {
  $all = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  foreach ($element in $all) {
    try {
      $current = [string]$element.Current.Name
      if ((!$Like -and $current -eq $Name) -or ($Like -and $current -like $Name)) { return $element }
    } catch {}
  }
  return $null
}

function Write-UiHints([System.Windows.Automation.AutomationElement]$Root,[string]$Label) {
  Write-Host ('INFO ui_hints_begin=' + $Label)
  $seen = @{}
  $all = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  foreach ($element in $all) {
    try {
      $name = ([string]$element.Current.Name).Trim()
      if ($name -and $name.Length -lt 240 -and $name -match '(?i)replace|plugin|upload|install|update|error|failed|already|activate|return') {
        if (-not $seen.ContainsKey($name)) {
          $seen[$name] = $true
          Write-Host ('INFO UI: ' + $name + ' [' + $element.Current.ControlType.ProgrammaticName + ']')
        }
      }
    } catch {}
  }
  Write-Host ('INFO ui_hints_end=' + $Label)
}

function Wait-ForNamedElement([System.Diagnostics.Process]$Process,[string]$Name,[int]$Seconds=30) {
  for ($attempt=0; $attempt -lt ($Seconds*2); $attempt++) {
    Start-Sleep -Milliseconds 500
    try {
      $root = Root $Process
      $element = Find-ByName $root $Name
      if ($element) { return $element }
    } catch {}
  }
  return $null
}

function Invoke-Element([System.Windows.Automation.AutomationElement]$Element) {
  if (-not $Element) { throw 'UI element is missing.' }
  $pattern = $Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
  $pattern.Invoke()
}

function Set-ElementValue([System.Windows.Automation.AutomationElement]$Element,[string]$Value) {
  if (-not $Element) { throw 'Editable UI element is missing.' }
  $pattern = $Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
  $pattern.SetValue($Value)
}

function Choose-File([System.Windows.Automation.AutomationElement]$Button,[string]$Path) {
  Invoke-Element $Button
  Start-Sleep -Seconds 2
  [System.Windows.Forms.SendKeys]::SendWait('^a')
  Start-Sleep -Milliseconds 100
  [System.Windows.Forms.Clipboard]::SetText($Path)
  [System.Windows.Forms.SendKeys]::SendWait('^v')
  [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
  Start-Sleep -Seconds 3
}

function Get-HealthSourceHead {
  try {
    $health = Invoke-RestMethod -UseBasicParsing -Uri ('https://office.excelherbal.in/wp-json/excel-herbal-erp/v7/health?cb=' + [Guid]::NewGuid().ToString('N')) -TimeoutSec 20
    if ($health.data -and $health.data.source_head) { return [string]$health.data.source_head }
    if ($health.source_head) { return [string]$health.source_head }
    return ''
  } catch { return '' }
}

function Get-LiveMainHash {
  $tmp = Join-Path $env:RUNNER_TEMP ('eh7-live-main-' + [Guid]::NewGuid().ToString('N') + '.js')
  try {
    & curl.exe --fail --location --silent --show-error --max-time 30 --output $tmp ('https://office.excelherbal.in/wp-content/uploads/eh7-flutter-web/main.dart.js?cb=' + [Guid]::NewGuid().ToString('N'))
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tmp -PathType Leaf)) {
      throw 'Live main.dart.js could not be downloaded.'
    }
    return (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
  } finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

function New-BackendPluginZip {
  $source = Join-Path $repoRoot 'backend\excel-herbal-erp-v7'
  $work = Join-Path $env:RUNNER_TEMP ('eh7-backend-deploy-' + [Guid]::NewGuid().ToString('N'))
  $plugin = Join-Path $work 'excel-herbal-erp-v7'
  $zipPath = Join-Path $env:RUNNER_TEMP ('excel-herbal-erp-v7-' + $SourceHead.Substring(0,8) + '.zip')
  if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
  New-Item -ItemType Directory -Path $plugin -Force | Out-Null
  Copy-Item -Path (Join-Path $source '*') -Destination $plugin -Recurse -Force
  @(
    '<?php',
    "if(!defined('ABSPATH'))exit;",
    "define('EH7_SOURCE_HEAD','$SourceHead');"
  ) | Set-Content -LiteralPath (Join-Path $plugin 'build-meta.php') -Encoding ascii

  foreach ($required in @(
    (Join-Path $plugin 'excel-herbal-erp-v7.php'),
    (Join-Path $plugin 'build-meta.php'),
    (Join-Path $plugin 'src\Administration\UatWebDeployAdmin.php')
  )) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw ('Backend deploy package missing: ' + $required) }
  }

  $base = (Resolve-Path -LiteralPath $work).Path
  $archive = [System.IO.Compression.ZipFile]::Open($zipPath,[System.IO.Compression.ZipArchiveMode]::Create)
  try {
    Get-ChildItem -LiteralPath $work -Recurse -File | ForEach-Object {
      $relative = $_.FullName.Substring($base.Length).TrimStart([char[]]@([char]92,[char]47))
      $entryName = $relative -replace '\\','/'
      $entry = $archive.CreateEntry($entryName,[System.IO.Compression.CompressionLevel]::Optimal)
      $entryStream = $entry.Open()
      $fileStream = [System.IO.File]::OpenRead($_.FullName)
      try { $fileStream.CopyTo($entryStream) }
      finally { $fileStream.Dispose(); $entryStream.Dispose() }
    }
  } finally { $archive.Dispose() }
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
  return $zipPath
}

function Deploy-BackendPlugin([string]$ZipPath) {
  $current = Get-HealthSourceHead
  if ($current -eq $SourceHead) {
    Write-Host 'PASS backend exact source head is already live.'
    return
  }

  $chrome = Open-DedicatedChromeWindow -Url 'https://office.excelherbal.in/wp-admin/plugin-install.php?tab=upload' -TitlePattern 'Add Plugins|Upload Plugin|office.*WordPress'
  $shell = New-Object -ComObject WScript.Shell
  $null = $shell.AppActivate($chrome.Id)
  Start-Sleep -Seconds 5
  if ((Get-Process -Id $chrome.Id).MainWindowTitle -match 'Log In|Login') { throw 'WordPress admin session is not authenticated.' }

  $root = Root $chrome
  $file = Find-ById $root 'pluginzip'
  $install = Find-ById $root 'install-plugin-submit'
  if (-not $file -or -not $install) { throw 'WordPress Upload Plugin controls were not found.' }
  Choose-File $file $ZipPath

  $root = Root $chrome
  $install = Find-ById $root 'install-plugin-submit'
  if (-not $install -or -not $install.Current.IsEnabled) { throw 'Install Now is unavailable after choosing the backend ZIP.' }
  Invoke-Element $install
  Write-Host ('INFO backend_zip_submitted=' + $ZipPath)

  # WordPress shows an explicit replacement comparison for an existing plugin.
  # Wait for it instead of assuming the navigation has completed after a fixed delay.
  for ($attempt=0; $attempt -lt 60; $attempt++) {
    Start-Sleep -Milliseconds 500
    $current = Get-HealthSourceHead
    if ($current -eq $SourceHead) {
      Write-Host ('PASS backend_source_head=' + $current)
      return
    }
    try {
      $root = Root $chrome
      $replace = Find-ByName $root 'Replace current with uploaded'
      if ($replace) {
        Write-Host 'INFO replacement_confirmation_found=true'
        Invoke-Element $replace
        Start-Sleep -Seconds 2
        break
      }
    } catch {}
  }

  for ($attempt=0; $attempt -lt 30; $attempt++) {
    $current = Get-HealthSourceHead
    if ($current -eq $SourceHead) {
      Write-Host ('PASS backend_source_head=' + $current)
      return
    }
    Start-Sleep -Seconds 2
  }

  try { Write-UiHints (Root $chrome) 'backend_replace_failure' } catch {}
  throw ('Backend replacement finished but live source_head is not ' + $SourceHead + '. Current: ' + $current)
}

function Deploy-WebRuntime {
  $before = Get-LiveMainHash
  Write-Host ('INFO current_live_main_sha256=' + $before)
  Write-Host ('INFO expected_main_sha256=' + $expectedMainHash)

  $currentMarker = ''
  try {
    $currentMarker = (Invoke-WebRequest -UseBasicParsing -Uri ('https://office.excelherbal.in/wp-content/uploads/eh7-flutter-web/EH7-SOURCE-HEAD.txt?cb=' + [Guid]::NewGuid().ToString('N')) -TimeoutSec 20).Content.Trim()
  } catch {}

  if ($before -eq $expectedMainHash) {
    Write-Host 'PASS certified web runtime SHA already matches the exact candidate.'
    if ($currentMarker) {
      Write-Host ('INFO live_web_source_marker=' + $currentMarker)
    }
    return
  }

  $chrome = Open-DedicatedChromeWindow -Url 'https://office.excelherbal.in/wp-admin/tools.php?page=eh7-uat-web-deploy' -TitlePattern 'EH7 UAT Web Deploy|office.*WordPress'
  $shell = New-Object -ComObject WScript.Shell
  $null = $shell.AppActivate($chrome.Id)
  Start-Sleep -Seconds 5
  if ((Get-Process -Id $chrome.Id).MainWindowTitle -match 'Log In|Login') { throw 'WordPress admin session is not authenticated.' }

  $root = Root $chrome
  $file = Find-ById $root 'eh7_web_bundle'
  $source = Find-ById $root 'eh7_source_head'
  $reason = Find-ById $root 'eh7_reason'
  $confirm = Find-ByName $root '*confirm this certified BUILD/UAT web deployment*' $true
  $submit = Find-ByName $root 'Deploy Certified Web Bundle'
  if (-not $file -or -not $source -or -not $reason -or -not $confirm -or -not $submit) {
    throw 'Current ERP UAT web deployment controls were not found.'
  }

  Choose-File $file $webZip
  $root = Root $chrome
  Set-ElementValue (Find-ById $root 'eh7_source_head') $SourceHead
  Set-ElementValue (Find-ById $root 'eh7_reason') 'Deploy certified session-race fix to office BUILD/UAT'
  $confirm = Find-ByName $root '*confirm this certified BUILD/UAT web deployment*' $true
  $toggle = $confirm.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
  if ($toggle.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On) { $toggle.Toggle() }
  $submit = Find-ByName $root 'Deploy Certified Web Bundle'
  Invoke-Element $submit
  Start-Sleep -Seconds 12

  $actual = Get-LiveMainHash
  Write-Host ('INFO final_live_main_sha256=' + $actual)
  if ($actual -ne $expectedMainHash) {
    throw 'Current ERP web deployment completed but live main.dart.js hash does not match the certified candidate.'
  }

  try {
    $marker = (Invoke-WebRequest -UseBasicParsing -Uri ('https://office.excelherbal.in/wp-content/uploads/eh7-flutter-web/EH7-SOURCE-HEAD.txt?cb=' + [Guid]::NewGuid().ToString('N')) -TimeoutSec 20).Content.Trim()
    if ($marker -ne $SourceHead) { throw ('Live web source marker mismatch: ' + $marker) }
    Write-Host ('PASS live_web_source_head=' + $marker)
  } catch {
    throw ('Live web source-head marker verification failed. ' + $_.Exception.Message)
  }
  Write-Host ('PASS live_web_sha256=' + $actual)
}

function Resolve-UatAnomalies {
  $chrome = Open-DedicatedChromeWindow -Url 'https://office.excelherbal.in/wp-admin/tools.php?page=eh7-uat-cleanup' -TitlePattern 'EH7 UAT Cleanup|office.*WordPress'
  $shell = New-Object -ComObject WScript.Shell
  $null = $shell.AppActivate($chrome.Id)
  Start-Sleep -Seconds 5
  if ((Get-Process -Id $chrome.Id).MainWindowTitle -match 'Log In|Login') {
    throw 'WordPress admin session is not authenticated for UAT cleanup.'
  }

  $root = Root $chrome
  $reason = Find-ById $root 'eh7_reason'
  $confirm = Find-ByName $root '*confirm safe UAT anomaly resolution*' $true
  $submit = Find-ByName $root 'Resolve Safe UAT Anomalies'
  if (-not $reason -or -not $confirm -or -not $submit) {
    try { Write-UiHints $root 'uat_cleanup_controls_missing' } catch {}
    throw 'EH7 UAT Cleanup controls were not found.'
  }

  Set-ElementValue $reason 'Resolve verified post-deployment UAT anomalies after diagnostics review'
  $toggle = $confirm.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
  if ($toggle.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On) { $toggle.Toggle() }
  Invoke-Element $submit
  Start-Sleep -Seconds 8

  $root = Root $chrome
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  $success = ''
  $diag = ''
  foreach ($element in $all) {
    try {
      $name = ([string]$element.Current.Name).Trim()
      if ($name -like 'UAT cleanup complete:*') { $success = $name }
      if ($name -like 'Current diagnostics:*') { $diag = $name }
    } catch {}
  }
  if (-not $success) {
    try { Write-UiHints $root 'uat_cleanup_result_missing' } catch {}
    throw 'EH7 UAT Cleanup did not report a successful audited cleanup result.'
  }
  Write-Host ('PASS uat_cleanup_result=' + $success)
  if ($diag) { Write-Host ('INFO uat_cleanup_diagnostics_label=' + $diag) }
}

$backendZip = New-BackendPluginZip
try {
  Deploy-BackendPlugin $backendZip
  Deploy-WebRuntime
  Resolve-UatAnomalies
} finally {
  Remove-Item -LiteralPath $backendZip -Force -ErrorAction SilentlyContinue
}