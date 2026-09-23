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

  # Chrome can reuse an existing process/window even with --new-window.
  # Fall back to an authenticated visible window and navigate it explicitly.
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