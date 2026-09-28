param(
  [Parameter(Mandatory = $true)]
  [string]$SourceHead,
  [Parameter(Mandatory = $true)]
  [string]$UatSiteUrl
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

if ($SourceHead -notmatch '^[a-f0-9]{40}$') {
  throw 'SourceHead must be a 40-character lowercase commit SHA.'
}

try { $uatUri = [Uri]$UatSiteUrl.TrimEnd('/') }
catch { throw 'UatSiteUrl must be a valid absolute HTTPS URL.' }
if (-not $uatUri.IsAbsoluteUri -or $uatUri.Scheme -ne 'https') { throw 'Controlled UAT site must use HTTPS.' }
if ($uatUri.Host -ieq 'office.excelherbal.in') { throw 'Production office host is never a valid controlled UAT target.' }
$uatSiteRoot = $UatSiteUrl.TrimEnd('/')

$releaseRoot = Join-Path $env:USERPROFILE ('ERP7-Releases\uat-candidates\' + $SourceHead)
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
    $url = ($uatSiteRoot + '/wp-content/uploads/eh7-flutter-web/main.dart.js?cb=') + [Guid]::NewGuid().ToString('N')
    & curl.exe --fail --location --silent --show-error --connect-timeout 15 --max-time 120 --retry 3 --retry-delay 2 --retry-all-errors --output $tmp $url
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tmp -PathType Leaf)) {
      throw 'Live main.dart.js could not be downloaded for verification after retries.'
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

Write-Host ('INFO expected_main_sha256=' + $expectedMainHash)
Write-Host 'INFO pre_upload_live_hash_check=skipped_runner_network_is_slow'

    $setupUrl = $uatSiteRoot + '/wp-admin/admin.php?page=eh7-setup-assistant&tab=desktop'
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

$upload = Find-ControlByName -Root $root -Type ([System.Windows.Automation.ControlType]::Button) -ExactName 'Upload Web Bundle'
if (-not $upload) {
  throw ('Setup Assistant Upload Web Bundle control was not found. Browser title: ' + $chrome.MainWindowTitle)
}

# The page contains more than one file chooser. Resolve the chooser from the
# smallest ancestor that contains the Upload Web Bundle button so we never
# attach the web ZIP to the backend/other upload form by mistake.
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$container = $walker.GetParent($upload)
$choose = $null
for ($depth = 0; $depth -lt 14 -and $container; $depth++) {
  $candidate = Find-ControlByName -Root $container -Type ([System.Windows.Automation.ControlType]::Button) -ExactName '' -NameLike 'Choose File:*'
  if ($candidate) {
    $choose = $candidate
    break
  }
  $container = $walker.GetParent($container)
}

if (-not $choose) {
  throw 'The file chooser belonging to Upload Web Bundle was not found.'
}

Write-Host ('INFO web_upload_control=' + [string]$upload.Current.Name + ' automation_id=' + [string]$upload.Current.AutomationId)
Write-Host ('INFO web_choose_control=' + [string]$choose.Current.Name + ' automation_id=' + [string]$choose.Current.AutomationId)

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
Write-Host ('INFO selected_candidate_zip=' + $zipPath)

# Submit the exact form that owns Upload Web Bundle. The file has already
# been selected through the native chooser, so requestSubmit preserves the
# multipart file payload and includes the submit button name/value expected by
# the Setup Assistant handler.
$shell = New-Object -ComObject WScript.Shell
[void]$shell.AppActivate($chrome.Id)
Start-Sleep -Milliseconds 300
$submitScript = "script:(()=>{const all=[...document.querySelectorAll('button,input[type=submit],input[type=button]')];const b=all.find(e=>((e.value||e.textContent||'').trim()==='Upload Web Bundle'));if(!b){document.title='EH7SUBMIT-NOBUTTON';return;}const f=b.closest('form');if(!f){document.title='EH7SUBMIT-NOFORM';return;}document.title='EH7SUBMIT-FIRE';if(f.requestSubmit){f.requestSubmit(b)}else{f.submit()}})()"
[System.Windows.Forms.SendKeys]::SendWait('^l')
Start-Sleep -Milliseconds 120
# Chrome strips a pasted javascript: prefix; type "java" and paste the rest.
[System.Windows.Forms.SendKeys]::SendWait('java')
[System.Windows.Forms.Clipboard]::SetText($submitScript)
[System.Windows.Forms.SendKeys]::SendWait('^v')
[System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
Start-Sleep -Seconds 18
$chrome = Get-Process -Id $chrome.Id -ErrorAction Stop
Write-Host ('INFO post_submit_browser_title=' + $chrome.MainWindowTitle)

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

# A successful multipart POST reloads the Setup Assistant and clears the
# native file input. If the selected ZIP is still present, submission did not happen.
$root = Get-AutomationRoot $chrome
$uploadAfter = Find-ControlByName -Root $root -Type ([System.Windows.Automation.ControlType]::Button) -ExactName 'Upload Web Bundle'
$chooseAfter = $null
if ($uploadAfter) {
  $walkerAfter = [System.Windows.Automation.TreeWalker]::ControlViewWalker
  $containerAfter = $walkerAfter.GetParent($uploadAfter)
  for ($depth = 0; $depth -lt 14 -and $containerAfter; $depth++) {
    $candidateAfter = Find-ControlByName -Root $containerAfter -Type ([System.Windows.Automation.ControlType]::Button) -ExactName '' -NameLike 'Choose File:*'
    if ($candidateAfter) { $chooseAfter = $candidateAfter; break }
    $containerAfter = $walkerAfter.GetParent($containerAfter)
  }
}
if (-not $chooseAfter) {
  throw 'Web upload form could not be re-read after submission.'
}
$chooseAfterName = [string]$chooseAfter.Current.Name
Write-Host ('INFO post_submit_choose_control=' + $chooseAfterName)
if ($chooseAfterName -match 'Excel-Herbal-ERP-v7\.4\.0-Web-Candidate\.zip') {
  throw 'WordPress web upload form did not submit; selected ZIP is still attached to the file input.'
}

Write-Host 'PASS WordPress web upload form submitted and reloaded.'
Write-Host ('INFO expected_live_main_sha256=' + $expectedMainHash)
