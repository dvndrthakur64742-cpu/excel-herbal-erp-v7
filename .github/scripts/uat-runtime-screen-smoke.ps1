param(
  [Parameter(Mandatory = $true)][string]$AppUrl,
  [Parameter(Mandatory = $true)][string]$Mobile,
  [Parameter(Mandatory = $true)][string]$Password,
  [string]$EvidencePath = 'dist/uat-runtime-screen-smoke/EVIDENCE.json'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

if ([string]::IsNullOrWhiteSpace($Mobile) -or [string]::IsNullOrWhiteSpace($Password)) {
  throw 'UAT runtime screen smoke requires a controlled UAT login.'
}

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

function Open-AppWindow([string]$Url) {
  $before = @{}
  Get-Process chrome -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    ForEach-Object { $before[[string]$_.MainWindowHandle] = $true }

  Start-Process -FilePath (Get-ChromeExe) -ArgumentList @('--new-window',$Url) | Out-Null
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    Start-Sleep -Milliseconds 500
    $windows = @(Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 })
    $newWindow = $windows | Where-Object { -not $before.ContainsKey([string]$_.MainWindowHandle) } | Select-Object -First 1
    if ($newWindow) { return $newWindow }
    $match = $windows | Where-Object { $_.MainWindowTitle -match 'Excel Herbal|office\.excelherbal\.in' } | Select-Object -First 1
    if ($match) { return $match }
  }
  throw 'Excel Herbal ERP Chrome window did not open.'
}

function Root([System.Diagnostics.Process]$Process) {
  $fresh = Get-Process -Id $Process.Id -ErrorAction Stop
  return [System.Windows.Automation.AutomationElement]::FromHandle($fresh.MainWindowHandle)
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
    foreach ($name in (All-Names (Root $Process))) { Write-Host ('INFO UAT_UI: ' + $name) }
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
  $exact = Find-ByNameLike $root @($Label)
  if ($exact) { return $exact }

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
  results = [ordered]@{}
}

$chrome = $null
try {
  $chrome = Open-AppWindow $uri.AbsoluteUri
  $shell = New-Object -ComObject WScript.Shell
  [void]$shell.AppActivate($chrome.Id)
  Start-Sleep -Seconds 8

  # Flutter web hides the semantic accessibility tree until this Chrome/Flutter
  # accessibility control is activated. Enable it before looking for the login
  # fields or application navigation so the smoke test observes real Flutter
  # semantics instead of only browser chrome.
  $enableAccessibility = Wait-ForAnyName $chrome @('Enable accessibility') 6
  if ($enableAccessibility) {
    if (-not (Try-Invoke $enableAccessibility)) {
      throw 'Flutter accessibility semantics could not be enabled.'
    }
    Start-Sleep -Seconds 2
    Write-Host 'PASS flutter_accessibility_semantics_enabled'
  }

  $signIn = Wait-ForAnyName $chrome @('SIGN IN') 8
  if ($signIn) {
    $mobileBox = Find-EditByLabel $chrome 'Mobile number'
    $passwordBox = Find-EditByLabel $chrome 'Password'
    if (-not $mobileBox -or -not $passwordBox) {
      Write-UiHints $chrome 'login_fields_missing'
      throw 'ERP login fields were not exposed to UI Automation.'
    }
    if (-not (Set-ControlValue $mobileBox $Mobile)) { throw 'Could not enter UAT mobile number.' }
    if (-not (Set-ControlValue $passwordBox $Password)) { throw 'Could not enter UAT password.' }
    if (-not (Try-Invoke $signIn)) { throw 'Could not invoke ERP SIGN IN.' }
    Start-Sleep -Seconds 4
  }

  $workspace = Wait-ForAnyName $chrome @('ERP Workspace') 30
  if (-not $workspace) {
    Write-UiHints $chrome 'authenticated_workspace_missing'
    throw 'Authenticated ERP Workspace did not become visible.'
  }
  $evidence.results['authenticated_workspace'] = 'passed'
  Write-Host 'PASS authenticated_workspace'

  Assert-NoBootstrapCrash $chrome 'home'
  $home = Find-ByNameLike (Root $chrome) @('Home')
  if (-not $home) {
    Write-UiHints $chrome 'home_navigation_missing'
    throw 'Home navigation item is missing.'
  }
  if (-not (Try-Invoke $home)) { throw 'Home navigation item could not be invoked.' }
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
  Write-Host 'PASSED authenticated UAT runtime screen smoke'
}
finally {
  $dir = Split-Path -Parent $EvidencePath
  if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $EvidencePath -Encoding utf8
  if ($chrome) {
    try { Stop-Process -Id $chrome.Id -Force -ErrorAction SilentlyContinue } catch {}
  }
}
