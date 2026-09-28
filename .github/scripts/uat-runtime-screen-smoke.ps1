param(
  [Parameter(Mandatory = $true)][string]$AppUrl,
  [string]$Mobile = '',
  [string]$Password = '',
  [string]$EvidencePath = 'dist/uat-runtime-screen-smoke/EVIDENCE.json'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$uri = [Uri]$AppUrl
if ($uri.Scheme -ne 'https' -or $uri.Host -ine 'office.excelherbal.in') {
  throw 'UAT runtime screen smoke is restricted to https://office.excelherbal.in.'
}

function Get-ChromeExe {
  $candidate = @(
    (Get-Command chrome.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
    'C:\Program Files\Google\Chrome\Application\chrome.exe',
    'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
  if (-not $candidate) { throw 'Chrome executable was not found.' }
  return $candidate
}

function Get-ChromeWindows {
  $windows = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
    [System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
  foreach ($window in $windows) {
    try {
      if ($window.Current.ClassName -eq 'Chrome_WidgetWin_1' -and $window.Current.NativeWindowHandle -ne 0) { $window }
    } catch {}
  }
}

function Get-ChromeProcessCommandLine([int]$ProcessId) {
  try {
    $row = Get-CimInstance Win32_Process -Filter ('ProcessId = ' + $ProcessId) -ErrorAction Stop
    return [string]$row.CommandLine
  } catch { return '' }
}

function Open-AppWindow([string]$Url,[string]$ProfilePath) {
  # Start-Process can return Chrome's broker/existing process even when the
  # actual app window belongs to another Chrome PID. Pin the newly-created
  # top-level HWND only after proving its owning process uses our isolated
  # UAT profile; this prevents a personal New Tab from being adopted.
  # Keep this ownership proof fail-closed before entering controlled UAT credentials.
  $before = @{}
  foreach ($window in (Get-ChromeWindows)) {
    $before[[string]$window.Current.NativeWindowHandle] = $true
  }
  $script:ownedChrome = $null
  $script:appWindowHandle = [IntPtr]::Zero
  Start-Process -FilePath (Get-ChromeExe) -ArgumentList @(
    ('--user-data-dir="' + $ProfilePath + '"'),
    '--no-first-run', '--no-default-browser-check', '--disable-sync',
    '--force-renderer-accessibility', ('--app=' + $Url)
  ) -WindowStyle Normal | Out-Null

  for ($attempt = 0; $attempt -lt 60; $attempt++) {
    Start-Sleep -Milliseconds 500
    $candidates = @(Get-ChromeWindows | Where-Object {
      -not $before.ContainsKey([string]$_.Current.NativeWindowHandle) -and
      (Get-ChromeProcessCommandLine $_.Current.ProcessId).IndexOf(
        $ProfilePath,[StringComparison]::OrdinalIgnoreCase) -ge 0
    })
    if ($candidates.Count -gt 1) {
      throw 'More than one isolated UAT Chrome window appeared; ownership is ambiguous.'
    }
    if ($candidates.Count -eq 1) {
      $ownerPid = [int]$candidates[0].Current.ProcessId
      $script:appWindowHandle = [IntPtr]$candidates[0].Current.NativeWindowHandle
      $script:ownedChrome = Get-Process -Id $ownerPid -ErrorAction Stop
      return $script:ownedChrome
    }
  }
  throw 'Excel Herbal ERP isolated Chrome window did not open.'
}

function Root([System.Diagnostics.Process]$Process) {
  $Process.Refresh()
  if ($Process.HasExited -or $script:appWindowHandle -eq 0) { throw 'Owned UAT Chrome window is no longer available.' }
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($script:appWindowHandle)
  if (-not $root -or $root.Current.ProcessId -ne $Process.Id) { throw 'UAT Chrome window ownership changed.' }
  return $root
}

function Find-ByNameLike([System.Windows.Automation.AutomationElement]$Root,[string[]]$Names) {
  $all = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  foreach ($wanted in $Names) {
    foreach ($element in $all) {
      try {
        $name = ([string]$element.Current.Name).Trim()
        if ($name -eq $wanted) { return $element }
      } catch {}
    }
  }
  return $null
}

function All-Names([System.Windows.Automation.AutomationElement]$Root) {
  $seen = @{}
  $out = New-Object System.Collections.Generic.List[string]
  $all = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  foreach ($element in $all) {
    try {
      $name = ([string]$element.Current.Name).Trim()
      if ($name -and $name.Length -le 220 -and -not $seen.ContainsKey($name)) {
        $seen[$name] = $true
        $out.Add($name)
      }
    } catch {}
  }
  return $out
}

function Write-UiHints([System.Diagnostics.Process]$Process,[string]$Label) {
  Write-Host ('INFO uat_ui_hints_begin=' + $Label)
  try {
    foreach ($name in (All-Names (Root $Process))) {
      foreach ($secret in @($Mobile,$Password)) {
        if (-not [string]::IsNullOrEmpty($secret)) { $name = $name.Replace($secret,'[redacted]') }
      }
      Write-Host ('INFO UAT_UI: ' + $name)
    }
  } catch {
    Write-Host ('INFO uat_ui_hints_error=' + $_.Exception.Message)
  }
  Write-Host ('INFO uat_ui_hints_end=' + $Label)
}

function Try-Invoke([System.Windows.Automation.AutomationElement]$Element) {
  if (-not $Element) { return $false }
  try {
    $p = $Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $p.Invoke()
    return $true
  } catch {}
  try {
    $p = $Element.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
    $p.Select()
    return $true
  } catch {}
  try {
    $p = $Element.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern)
    $p.DoDefaultAction()
    return $true
  } catch {}
  try {
    $Element.SetFocus()
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    return $true
  } catch {}
  return $false
}

function Set-ControlValue([System.Windows.Automation.AutomationElement]$Element,[string]$Value) {
  if (-not $Element) { return $false }
  try {
    $p = $Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $p.SetValue($Value)
    return $true
  } catch {}
  try {
    $Element.SetFocus()
    Start-Sleep -Milliseconds 150
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    [System.Windows.Forms.Clipboard]::SetText($Value)
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    return $true
  } catch {}
  return $false
}

function Set-LoginControlValue([System.Diagnostics.Process]$Process,[System.Windows.Automation.AutomationElement]$Element,[string]$Value) {
  if (-not $Element -or [string]::IsNullOrEmpty($Value)) { return $false }
  try {
    [void](Root $Process)
    $Element.SetFocus()
    Start-Sleep -Milliseconds 180
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    [System.Windows.Forms.Clipboard]::SetText($Value)
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    Start-Sleep -Milliseconds 220
    return $true
  } catch {}
  return $false
}


function Wait-ForAnyName([System.Diagnostics.Process]$Process,[string[]]$Names,[int]$Seconds = 25) {
  for ($attempt = 0; $attempt -lt ($Seconds * 2); $attempt++) {
    Start-Sleep -Milliseconds 500
    try {
      $element = Find-ByNameLike (Root $Process) $Names
      if ($element) { return $element }
    } catch {}
  }
  return $null
}

function Wait-ForFreshLogin([System.Diagnostics.Process]$Process) {
  # A cold profile downloads the Flutter runtime before exposing its semantics
  # opt-in control. Wait for readiness, rather than a short startup-only probe.
  $ready = Wait-ForAnyName $Process @('SIGN IN','Enable accessibility') 90
  if (-not $ready) { throw 'UAT app did not expose login or accessibility readiness.' }
  if ($ready.Current.Name.Trim() -eq 'Enable accessibility') {
    if (-not (Try-Invoke $ready)) { throw 'Flutter accessibility semantics could not be enabled.' }
    $signIn = Wait-ForAnyName $Process @('SIGN IN') 30
    if (-not $signIn) { throw 'UAT login semantics did not appear after enabling accessibility.' }
    Write-Host 'PASS flutter_accessibility_semantics_enabled'
    return $signIn
  }
  return $ready
}

function Assert-NoBootstrapCrash([System.Diagnostics.Process]$Process,[string]$Label) {
  $names = @(All-Names (Root $Process))
  $joined = ($names -join [Environment]::NewLine)
  foreach ($bad in @(
    'ERP server business date is unavailable or invalid.',
    'Bad state: No element',
    'StateError',
    'ERP startup data is unavailable.'
  )) {
    if ($joined -like ('*' + $bad + '*')) {
      Write-UiHints $Process ($Label + '_bootstrap_crash')
      throw ($Label + ' rendered bootstrap/startup failure: ' + $bad)
    }
  }
}

function Find-EditByLabel([System.Diagnostics.Process]$Process,[string]$Label) {
  $root = Root $Process
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  foreach ($element in $all) {
    try {
      if ($element.Current.ControlType -eq [System.Windows.Automation.ControlType]::Edit) {
        $name = ([string]$element.Current.Name).Trim()
        if ($name -like ('*' + $Label + '*')) { return $element }
      }
    } catch {}
  }
  return $null
}

$evidence = [ordered]@{
  schema_version = 1
  target = $uri.AbsoluteUri
  commit = $env:GITHUB_SHA
  run_id = $env:GITHUB_RUN_ID
  tested_at_utc = [DateTime]::UtcNow.ToString('o')
  status = 'failed'
  phase = 'browser_start'
  results = [ordered]@{}
}

$chrome = $null
$script:ownedChrome = $null
$script:appWindowHandle = [IntPtr]::Zero
$profileRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$profilePath = Join-Path $profileRoot ('eh7-uat-smoke-' + [Guid]::NewGuid().ToString('N'))
try {
  $chrome = Open-AppWindow $uri.AbsoluteUri $profilePath
  $shell = New-Object -ComObject WScript.Shell
  if (-not $shell.AppActivate($chrome.Id)) { throw 'Owned UAT Chrome window could not be activated.' }
  $evidence.phase = 'login_screen'
  try {
    $signIn = Wait-ForFreshLogin $chrome
  } catch {
    Write-UiHints $chrome 'fresh_login_screen_missing'
    throw
  }
  if ($signIn) {
    $evidence.results['fresh_login_screen'] = 'passed'
    if ([string]::IsNullOrWhiteSpace($Mobile) -or [string]::IsNullOrWhiteSpace($Password)) {
      Write-UiHints $chrome 'uat_login_required_but_credentials_missing'
      throw 'ERP login screen is visible and controlled UAT credentials are not configured.'
    }
    $workspace = $null
    for ($loginAttempt = 1; $loginAttempt -le 3; $loginAttempt++) {
      $mobileBox = Find-EditByLabel $chrome 'Mobile number'
      $passwordBox = Find-EditByLabel $chrome 'Password'
      if (-not $mobileBox -or -not $passwordBox) {
        Write-UiHints $chrome ('login_fields_missing_' + $loginAttempt)
        throw 'ERP login fields were not exposed to UI Automation.'
      }

      # Chrome/Flutter can report ValuePattern success for secure fields while
      # the password remains empty. Use focused keyboard/clipboard entry for
      # both credentials and never print either secret.
      if (-not (Set-LoginControlValue $chrome $mobileBox $Mobile)) { throw 'Could not enter UAT mobile number.' }
      if (-not (Set-LoginControlValue $chrome $passwordBox $Password)) { throw 'Could not enter UAT password.' }

      # Re-query after input because Flutter semantics can replace the button
      # element while editing form fields.
      $signIn = Find-ByNameLike (Root $chrome) @('SIGN IN')
      if (-not $signIn -or -not (Try-Invoke $signIn)) { throw 'Could not invoke ERP SIGN IN.' }
      $evidence.phase = 'authenticated_workspace'
      Write-Host ('INFO uat_login_submitted_attempt=' + $loginAttempt)

      $workspace = Wait-ForAnyName $chrome @('ERP Workspace') 15
      if ($workspace) { break }

      $names = @(All-Names (Root $chrome))
      $emptyPassword = $names -contains 'Enter your password.'
      $emptyMobile = $names -contains 'Enter your mobile number.'
      if (($emptyPassword -or $emptyMobile) -and $loginAttempt -lt 3) {
        Write-Host ('INFO uat_login_validation_retry=' + $loginAttempt + ' empty_mobile=' + $emptyMobile + ' empty_password=' + $emptyPassword)
        continue
      }

      Write-UiHints $chrome ('authenticated_workspace_missing_' + $loginAttempt)
      throw 'Authenticated ERP Workspace did not become visible after credential submission.'
    }
  }

  if (-not $workspace) {
    Write-UiHints $chrome 'authenticated_workspace_missing'
    throw 'Authenticated ERP Workspace did not become visible.'
  }
  $evidence.results['authenticated_workspace'] = 'passed'
  Write-Host 'PASS authenticated_workspace'

  Assert-NoBootstrapCrash $chrome 'home'
  $evidence.phase = 'home'
  $homeNav = Find-ByNameLike (Root $chrome) @('Home')
  if (-not $homeNav) {
    Write-UiHints $chrome 'home_navigation_missing'
    throw 'Home navigation item is missing.'
  }
  if (-not (Try-Invoke $homeNav)) { throw 'Home navigation item could not be invoked.' }
  Start-Sleep -Seconds 3
  Assert-NoBootstrapCrash $chrome 'home'
  $evidence.results['home'] = 'passed'
  Write-Host 'PASS uat_screen_home'

  $modules = @(
    @{ nav = @('Team Operations'); title = @('Team Operations'); key = 'team' },
    @{ nav = @('Sales & Collections'); title = @('Sales'); key = 'sales' },
    @{ nav = @('Inventory'); title = @('Inventory'); key = 'inventory' },
    @{ nav = @('Purchase & Suppliers'); title = @('Purchase'); key = 'purchase' },
    @{ nav = @('Finance & Accounts'); title = @('Finance'); key = 'finance' },
    @{ nav = @('Payroll & Performance'); title = @('Payroll & Performance'); key = 'payroll_performance' }
  )

  foreach ($module in $modules) {
    $evidence.phase = $module.key
    $nav = Find-ByNameLike (Root $chrome) $module.nav
    if (-not $nav) {
      Write-UiHints $chrome ($module.key + '_navigation_missing')
      throw ('Required UAT module navigation is missing: ' + ($module.nav -join ' / '))
    }
    if (-not (Try-Invoke $nav)) {
      throw ('Could not invoke UAT module navigation: ' + ($module.nav -join ' / '))
    }
    $title = Wait-ForAnyName $chrome $module.title 20
    if (-not $title) {
      Write-UiHints $chrome ($module.key + '_title_missing')
      throw ('UAT module did not render expected title: ' + ($module.title -join ' / '))
    }
    Assert-NoBootstrapCrash $chrome $module.key
    $evidence.results[$module.key] = 'passed'
    Write-Host ('PASS uat_screen_' + $module.key)
  }

  $evidence['status'] = 'passed'
  $evidence.phase = 'complete'
  Write-Host 'PASSED authenticated UAT runtime screen smoke'
}
finally {
  $dir = Split-Path -Parent $EvidencePath
  if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $EvidencePath -Encoding utf8
  if ($script:ownedChrome) {
    try {
      if (-not $script:ownedChrome.HasExited) {
        $script:ownedChrome.Kill()
        [void]$script:ownedChrome.WaitForExit(5000)
      }
    } catch { Write-Warning 'Could not stop the isolated UAT Chrome process.' }
  }
  # Delete only this invocation's generated profile, never the user's profile.
  $resolvedProfile = [IO.Path]::GetFullPath($profilePath)
  if (([IO.Path]::GetDirectoryName($resolvedProfile) -eq $profileRoot.TrimEnd([char]92,[char]47)) -and
      ([IO.Path]::GetFileName($resolvedProfile) -match '^eh7-uat-smoke-[a-f0-9]{32}$')) {
    if (Test-Path -LiteralPath $resolvedProfile) {
      Remove-Item -LiteralPath $resolvedProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}
