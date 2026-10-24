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
if ($uatUri.Host -ine 'office.excelherbal.in') { throw 'This owner-approved web-only preview uploader is restricted to office.excelherbal.in.' }
$uatSiteRoot = $UatSiteUrl.TrimEnd('/')

if ($env:GITHUB_REF -ne 'refs/heads/codex/erp-v8-foundation-20261017' -or $env:GITHUB_SHA -cne $SourceHead) {
  throw 'V8 preview requires the exact approved development branch HEAD.'
}
$runAttempt = if ($env:GITHUB_RUN_ATTEMPT -match '^\d+$') { $env:GITHUB_RUN_ATTEMPT } else { '1' }
if ($env:GITHUB_RUN_ID -notmatch '^\d+$') { throw 'GitHub Actions run ID required.' }
$candidateKey = $SourceHead + '-run' + $env:GITHUB_RUN_ID + '-attempt' + $runAttempt + '-slot-v8-office-preview'
$releaseRoot = Join-Path $env:USERPROFILE ('ERP7-Releases\uat-candidates\' + $candidateKey)
$zipPath = Join-Path $releaseRoot 'Excel-Herbal-ERP-v7.4.0-Web-Candidate.zip'
$candidateMain = Join-Path $releaseRoot 'web\main.dart.js'
foreach ($required in @($zipPath, $candidateMain)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
    throw ('Required deployment file is missing: ' + $required)
  }
}

$expectedMainHash = (Get-FileHash -LiteralPath $candidateMain -Algorithm SHA256).Hash.ToLowerInvariant()
# Web-only operation. Confirm the installed backend + old web bundle before upload.
$healthUrl = $uatSiteRoot + '/wp-json/excel-herbal-erp/v7/health'
$healthRaw = & curl.exe --fail --silent --show-error --location --connect-timeout 8 --max-time 25 $healthUrl
if ($LASTEXITCODE -ne 0) { throw 'Office staging health endpoint unreachable.' }
$health = ($healthRaw -join [Environment]::NewLine) | ConvertFrom-Json
# Both SHA pins must come from the same exact-head GitHub workflow preflight.
if ([string]$env:CURRENT_BACKEND_SHA -cnotmatch '^[a-f0-9]{40}$' -or
    [string]$env:OLD_WEB_SHA256 -cnotmatch '^[a-f0-9]{64}$') {
  throw 'Missing audited expected Office backend/web hash: refuse deployment.'
}
if ($health.ok -ne $true -or [string]$health.data.environment -ne 'staging' -or
    [string]$health.data.source_head -cne [string]$env:CURRENT_BACKEND_SHA -or
    [string]$health.data.web_runtime.main_sha256 -cne [string]$env:OLD_WEB_SHA256 -or
    [string]$health.data.host_hardening.status -ne 'passed' -or $health.data.schema_installed -ne $true) {
  throw 'Office staging baseline changed; abort web-only preview without modifying the site.'
}
Write-Host 'PASS original Office backend and frontend hashes attested; V7 PHP plugin will not be replaced.'


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

function Get-VerifiedSetupWindow([string]$Url) {
  # A GitHub service account can see Chrome processes yet cannot use their
  # desktop HWNDs. Reject Session 0 and never pick a tab by title alone.
  $session=(Get-Process -Id $PID -ErrorAction Stop).SessionId
  if($session -eq 0){
    throw 'Windows Actions runner is in non-interactive Session 0. Run the runner with run.cmd from the unlocked Windows desktop, not as a service.'
  }
  $target=[Uri]$Url
  $match=@()
  $visible=@(Get-Process chrome -ErrorAction SilentlyContinue | Where-Object {$_.MainWindowHandle -ne [IntPtr]::Zero})
  foreach($window in $visible){
    try {
      $root=[System.Windows.Automation.AutomationElement]::FromHandle($window.MainWindowHandle)
      if(-not $root){continue}
      $elements=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
      foreach($control in $elements){
        if($control.Current.ControlType -ne [System.Windows.Automation.ControlType]::Edit){continue}
        if([string]$control.Current.Name -notmatch '(?i)address and search bar|search google or type a url'){continue}
        $pattern=$control.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $addr=([string]$pattern.Current.Value).Trim()
        if(-not $addr){continue}
        $fullAddress=if($addr -match '^https?://'){$addr}else{'https://'+$addr}
        $uri=[Uri]$fullAddress
        if($uri.Host -ine $target.Host -or $uri.AbsolutePath -ine '/wp-admin/tools.php'){break}
        $query=[Uri]::UnescapeDataString($uri.Query.TrimStart('?'))
        if($query -notmatch '(?:^|&)page=eh7-uat-web-deploy(?:&|$)'){break}
        if($window.MainWindowTitle -match '(?i)Log In|Login'){break}
        $match+=,$window
        break
      }
    }catch{}
  }
  Write-Host ('INFO runner_session='+$session+' chrome_visible_count='+$visible.Count+' authenticated_setup_window_count='+$match.Count)
  if($match.Count -gt 1){throw 'Multiple Setup Assistant windows exist on the runner desktop; refusing ambiguous upload.'}
  if($match.Count -eq 1){return $match[0]}
  return $null
}

function Open-SetupAssistantWindow([string]$Url) {
  $chromeExe=@(
    (Get-Command chrome.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
    'C:\Program Files\Google\Chrome\Application\chrome.exe',
    'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
  ) | Where-Object {$_ -and (Test-Path -LiteralPath $_ -PathType Leaf)} | Select-Object -First 1
  if(-not $chromeExe){throw 'Chrome executable missing on the Windows runner.'}
  $existing=Get-VerifiedSetupWindow -Url $Url
  if($existing){
    Write-Host 'PASS verified existing authenticated Office Setup Assistant browser window'
    return $existing
  }
  Start-Process -FilePath $chromeExe -ArgumentList @('--new-window',$Url) | Out-Null
  for($attempt=0;$attempt -lt 30;$attempt++){
    Start-Sleep -Milliseconds 500
    $window=Get-VerifiedSetupWindow -Url $Url
    if($window){return $window}
  }
  throw 'Authenticated Office Setup Assistant window inaccessible to runner. Open WP Admin in the same unlocked runner desktop session; verify login and do not run runner as a Windows service.'
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

$setupUrl = $uatSiteRoot + '/wp-admin/tools.php?page=eh7-uat-web-deploy'
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

# Already verified the exact Office Advanced Certified Web Deployment management URL.
# Re-clicking Desktop Web starts a second navigation; UIA previously read the
# stale page during that reload and falsely reported the upload button missing.
# Wait for the original authenticated certified web upload control.
$upload = $null
for ($i=0; $i -lt 60; $i++) {
  $chrome = Get-Process -Id $chrome.Id -ErrorAction Stop
  if ($chrome.MainWindowTitle -match '(?i)Log In|Login') {
    throw 'WordPress administrator session needs login; upload not attempted.'
  }
  $root = Get-AutomationRoot $chrome
  $upload = Find-ControlByName -Root $root -Type ([System.Windows.Automation.ControlType]::Button) -ExactName 'Deploy Certified Web Bundle'
  if ($upload -and $upload.Current.IsEnabled) {
    Write-Host ('PASS authenticated WordPress Desktop Web upload control ready after '+$i+'s')
    break
  }
  Start-Sleep -Seconds 1
}
if (-not $upload -or -not $upload.Current.IsEnabled) {
  throw ('Authenticated Desktop Web upload control was not ready after 60 seconds. Browser title: '+$chrome.MainWindowTitle)
}

# The current V8 admin form requires original source SHA, audit reason and
# explicit owner acknowledgement. Use the native browser controls and its
# WordPress nonce: no direct unauthenticated multipart POST or cookie extraction.
function Find-CertifiedField(
  [System.Windows.Automation.AutomationElement]$Root,
  [System.Windows.Automation.ControlType]$Type,
  [string]$AutomationId,
  [string]$NameLike
) {
  $all=$Root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition)
  foreach($element in $all) {
    try {
      if($element.Current.ControlType -ne $Type){continue}
      if([string]$element.Current.AutomationId -eq $AutomationId){return $element}
      if(-not $AutomationId -and $NameLike -and [string]$element.Current.Name -like $NameLike){return $element}
    }catch{}
  }
  return $null
}
$root=Get-AutomationRoot $chrome
$headControl=Find-CertifiedField -Root $root -Type ([System.Windows.Automation.ControlType]::Edit) -AutomationId 'eh7_source_head' -NameLike '*Certified source head*'
$reasonControl=Find-CertifiedField -Root $root -Type ([System.Windows.Automation.ControlType]::Edit) -AutomationId 'eh7_reason' -NameLike '*Audit reason*'
$confirmControl=Find-CertifiedField -Root $root -Type ([System.Windows.Automation.ControlType]::CheckBox) -AutomationId 'eh7_confirm' -NameLike '*I confirm this certified BUILD/UAT web deployment*'
if(-not $headControl -or -not $reasonControl -or -not $confirmControl){
  throw 'Missing certified source, reason or confirmation field: refusing the wrong WordPress upload form.'
}
$headValue=$headControl.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
$reasonValue=$reasonControl.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
$confirmation=$confirmControl.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
$headValue.SetValue($SourceHead)
$reasonValue.SetValue('Owner approved Office read-only Employee Finance Review web preview')
if($confirmation.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On){$confirmation.Toggle()}
# Chromium accessibility controls commit ValuePattern/Toggle asynchronously.
# Do not prematurely reject a verified form while the UI is settling.
Start-Sleep -Milliseconds 650
if($headValue.Current.Value -cne $SourceHead -or
   $reasonValue.Current.Value.Length -lt 10 -or
   $confirmation.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On){
  throw 'Certified SHA, reason or explicit admin confirmation did not validate.'
}
Write-Host 'PASS original WordPress certified deploy form SHA, audit reason and confirmation validated'

# Chrome exposes this specific native WordPress file chooser as the
# AutomationId eh7_web_bundle, not as "Choose File:*".
# Never choose another browser or backend-upload input by positional order.
$choose=Find-CertifiedField -Root $root -Type ([System.Windows.Automation.ControlType]::Button) -AutomationId 'eh7_web_bundle' -NameLike ''
if(-not $choose -or [string]$choose.Current.Name -notlike 'Certified Flutter Web ZIP:*') {
  throw 'The original CERTIFIED Flutter web-only ZIP input could not be identified.'
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
$upload = Find-ControlByName -Root $root -Type ([System.Windows.Automation.ControlType]::Button) -ExactName 'Deploy Certified Web Bundle'
$headControl=Find-CertifiedField -Root $root -Type ([System.Windows.Automation.ControlType]::Edit) -AutomationId 'eh7_source_head' -NameLike '*Certified source head*'
$confirmControl=Find-CertifiedField -Root $root -Type ([System.Windows.Automation.ControlType]::CheckBox) -AutomationId 'eh7_confirm' -NameLike '*I confirm this certified BUILD/UAT web deployment*'
if(-not $headControl -or -not $confirmControl){
  throw 'Certified form controls went missing after ZIP selection.'
}
$afterHead=$headControl.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
$afterConfirm=$confirmControl.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
if($afterHead.Current.Value -cne $SourceHead -or
   $afterConfirm.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On){
  throw 'Certified source SHA or explicit authorization changed during ZIP selection.'
}
$afterChoose=Find-CertifiedField -Root $root -Type ([System.Windows.Automation.ControlType]::Button) -AutomationId 'eh7_web_bundle' -NameLike ''
if(-not $afterChoose -or [string]$afterChoose.Current.Name -notmatch 'Excel-Herbal-ERP-v7\.4\.0-Web-Candidate\.zip') {
  throw 'Incorrect or missing CERTIFIED web-only ZIP after the original Windows file dialog.'
}
if (-not $upload -or -not $upload.Current.IsEnabled) {
  throw 'Deploy Certified Web Bundle button is missing or disabled after ZIP selection.'
}
Write-Host ('INFO selected_candidate_zip=' + $zipPath)

# Press the verified native WordPress submit button directly.
# This preserves the browser's multipart file input and button name/value.
# Browser address-bar javascript pseudo URLs were unreliable and unnecessary.
$shell = New-Object -ComObject WScript.Shell
[void]$shell.AppActivate($chrome.Id)
Start-Sleep -Milliseconds 500
Write-Host 'INFO submitting verified Deploy Certified Web Bundle form via native button InvokePattern'
Invoke-Control $upload
Start-Sleep -Seconds 30

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

# A multi-megabyte WordPress POST may continue processing AFTER Chrome
# reports a network error or after the first 30-second UI wait. Do not
# retry/duplicate the upload. Observe the server to a bounded deadline.
# Fail on unexpected backend/schema/host changes. Only the exact certified
# new source HEAD + main.dart.js SHA qualifies as success.
$deadline=(Get-Date).AddMinutes(5)
$verified=$false
$lastObserved='none'
do {
  $rawResponse=& curl.exe --fail --silent --show-error --connect-timeout 10 --max-time 25 $healthUrl
  if($LASTEXITCODE -eq 0 -and $rawResponse) {
    $state=$null
    try {$state=($rawResponse -join [Environment]::NewLine)|ConvertFrom-Json}
    catch {Write-Host 'INFO WordPress upload processing; health JSON not yet available'}
    if($null -ne $state -and $state.ok -eq $true) {
      if($state.data.environment -ne 'staging' -or
         $state.data.source_head -cne [string]$env:CURRENT_BACKEND_SHA -or
         $state.data.schema_installed -ne $true -or
         $state.data.host_hardening.status -ne 'passed') {
        throw 'Unapproved ERP backend, schema or host change detected after web-only upload.'
      }
      $newHead=[string]$state.data.web_runtime.source_head
      $newHash=[string]$state.data.web_runtime.main_sha256
      $lastObserved=$newHead+' / '+$newHash
      if($newHead -ceq $SourceHead -and $newHash -ceq $expectedMainHash) {
        $verified=$true
        break
      }
      if($newHead -cne [string]$env:CURRENT_BACKEND_SHA -or
         $newHash -cne [string]$env:OLD_WEB_SHA256) {
        throw ('Unexpected independent Office web runtime after upload: '+$lastObserved)
      }
    }
  }
  Write-Host ('INFO WordPress still processing certified ZIP; observed='+$lastObserved)
  if((Get-Date) -ge $deadline){break}
  Start-Sleep -Seconds 10
} while((Get-Date) -lt $deadline)
if(-not $verified) {
  throw ('Web upload was NOT VERIFIED before the five-minute deadline. Last observed '+$lastObserved+'; do not resubmit automatically.')
}
Write-Host ('PASS WordPress certified web source HEAD='+$SourceHead)
Write-Host ('PASS WordPress certified main.dart.js HASH='+$expectedMainHash)
