param(
  [Parameter(Mandatory = $true)]
  [string]$SourceHead
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

if ($SourceHead -notmatch '^[a-f0-9]{40}$') {
  throw 'SourceHead must be a 40-character lowercase commit SHA.'
}

$releaseRoot = Join-Path $env:USERPROFILE ('ERP7-Releases\candidates\' + $SourceHead)
$zipPath = Join-Path $releaseRoot 'Excel-Herbal-ERP-v7.4.0-Web-Candidate.zip'
$candidateMain = Join-Path $releaseRoot 'web\main.dart.js'
foreach ($required in @($zipPath, $candidateMain)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
    throw ('Required deployment file is missing: ' + $required)
  }
}

$expectedMainHash = (Get-FileHash -LiteralPath $candidateMain -Algorithm SHA256).Hash.ToLowerInvariant()

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

function Get-ChromeWindow([string]$TitlePattern = '') {
  $windows = @(Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 })
  if ($windows.Count -eq 0) {
    throw 'Visible Chrome window was not found on the runner desktop.'
  }
  if ($TitlePattern) {
    $matched = $windows | Where-Object { $_.MainWindowTitle -match $TitlePattern } | Select-Object -First 1
    if ($matched) { return $matched }
    return $null
  }
  $preferred = $windows | Where-Object { $_.MainWindowTitle -match 'office|EH7|Excel Herbal|WordPress' } | Select-Object -First 1
  if ($preferred) { return $preferred }
  return $windows | Select-Object -First 1
}

function Open-SetupAssistantWindow([string]$Url) {
  $chromeExe = @(
    (Get-Command chrome.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
    'C:\Program Files\Google\Chrome\Application\chrome.exe',
    'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1

  if (-not $chromeExe) {
    throw 'Chrome executable was not found on the runner desktop.'
  }

  Start-Process -FilePath $chromeExe -ArgumentList @('--new-window', $Url) | Out-Null

  for ($attempt = 0; $attempt -lt 30; $attempt++) {
    Start-Sleep -Milliseconds 500
    $window = Get-ChromeWindow -TitlePattern 'EH7 Setup Assistant|office.*WordPress'
    if ($window) { return $window }
  }

  throw 'Dedicated WordPress Setup Assistant Chrome window did not appear.'
}

function Get-AutomationRoot([System.Diagnostics.Process]$Chrome) {
  $fresh = Get-Process -Id $Chrome.Id -ErrorAction Stop
  return [System.Windows.Automation.AutomationElement]::FromHandle($fresh.MainWindowHandle)
}

function Find-ControlByName(
  [System.Windows.Automation.AutomationElement]$Root,
  [System.Windows.Automation.ControlType]$Type,
  [string]$ExactName,
  [string]$NameLike = ''
) {
  $all = $Root.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition
  )
  foreach ($element in $all) {
    try {
      if ($element.Current.ControlType -ne $Type) { continue }
      $name = [string]$element.Current.Name
      if ($ExactName -and $name -eq $ExactName) { return $element }
      if ($NameLike -and $name -like $NameLike) { return $element }
    } catch {}
  }
  return $null
}

function Invoke-Control([System.Windows.Automation.AutomationElement]$Element) {
  $pattern = $Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
  $pattern.Invoke()
}

$beforeHash = Get-LiveMainHash
Write-Host ('INFO current_live_main_sha256=' + $beforeHash)
Write-Host ('INFO expected_main_sha256=' + $expectedMainHash)
if ($beforeHash -eq $expectedMainHash) {
  Write-Host 'PASS exact-head web candidate is already live.'
  exit 0
}

$setupUrl = 'https://office.excelherbal.in/wp-admin/admin.php?page=eh7-setup-assistant&tab=desktop'
$chrome = Open-SetupAssistantWindow -Url $setupUrl
$shell = New-Object -ComObject WScript.Shell
if (-not $shell.AppActivate($chrome.Id)) {
  throw 'Could not activate the dedicated WordPress Setup Assistant Chrome window.'
}
Start-Sleep -Seconds 6

$chrome = Get-Process -Id $chrome.Id -ErrorAction Stop
if ($chrome.MainWindowTitle -match 'Log In|Login') {
  throw 'Visible Chrome WordPress session is not authenticated.'
}

$root = Get-AutomationRoot $chrome
$desktopTab = Find-ControlByName -Root $root -Type ([System.Windows.Automation.ControlType]::Hyperlink) -ExactName 'Desktop Web'
if (-not $desktopTab) {
  $desktopTab = Find-ControlByName -Root $root -Type ([System.Windows.Automation.ControlType]::Button) -ExactName 'Desktop Web'
}
if ($desktopTab) {
  Invoke-Control $desktopTab
  Start-Sleep -Seconds 3
  $root = Get-AutomationRoot $chrome
}

$choose = Find-ControlByName -Root $root -Type ([System.Windows.Automation.ControlType]::Button) -ExactName '' -NameLike 'Choose File:*'
$upload = Find-ControlByName -Root $root -Type ([System.Windows.Automation.ControlType]::Button) -ExactName 'Upload Web Bundle'

if (-not $choose -or -not $upload) {
  throw ('Setup Assistant upload controls were not found. Browser title: ' + $chrome.MainWindowTitle)
}

Invoke-Control $choose
Start-Sleep -Seconds 2

$focused = [System.Windows.Automation.AutomationElement]::FocusedElement
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$window = $focused
for ($i = 0; $i -lt 12 -and $window; $i++) {
  if ($window.Current.ControlType -eq [System.Windows.Automation.ControlType]::Window) { break }
  $window = $walker.GetParent($window)
}
if (-not $window -or $window.Current.ControlType -ne [System.Windows.Automation.ControlType]::Window) {
  throw 'Native file chooser window was not found.'
}

[System.Windows.Forms.SendKeys]::SendWait('^a')
Start-Sleep -Milliseconds 100
[System.Windows.Forms.Clipboard]::SetText($zipPath)
[System.Windows.Forms.SendKeys]::SendWait('^v')
[System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
Start-Sleep -Seconds 3

$root = Get-AutomationRoot $chrome
$upload = Find-ControlByName -Root $root -Type ([System.Windows.Automation.ControlType]::Button) -ExactName 'Upload Web Bundle'
if (-not $upload -or -not $upload.Current.IsEnabled) {
  throw 'Upload Web Bundle button is missing or disabled after selecting the candidate ZIP.'
}

Invoke-Control $upload
Start-Sleep -Seconds 15

$root = Get-AutomationRoot $chrome
$allAfterUpload = $root.FindAll(
  [System.Windows.Automation.TreeScope]::Descendants,
  [System.Windows.Automation.Condition]::TrueCondition
)
$noticeNames = New-Object System.Collections.Generic.List[string]
foreach ($element in $allAfterUpload) {
  try {
    $name = ([string]$element.Current.Name).Trim()
    if ($name -and $name -match '(?i)upload|bundle|zip|error|failed|invalid|success|installed|deployed|too large|permission|nonce') {
      if (-not $noticeNames.Contains($name)) { $noticeNames.Add($name) }
    }
  } catch {}
}
if ($noticeNames.Count -gt 0) {
  Write-Host 'INFO post_upload_ui_notices_begin'
  foreach ($name in $noticeNames) { Write-Host ('INFO UI: ' + $name) }
  Write-Host 'INFO post_upload_ui_notices_end'
}

$liveHash = Get-LiveMainHash
Write-Host ('INFO post_upload_live_main_sha256=' + $liveHash)
if ($liveHash -ne $expectedMainHash) {
  throw 'Upload finished but live main.dart.js does not match the exact-head certified candidate. See post_upload_ui_notices for the WordPress response.'
}

Write-Host ('PASS exact-head web candidate deployed from visible authenticated WordPress session.')
Write-Host ('PASS final_live_main_sha256=' + $liveHash)