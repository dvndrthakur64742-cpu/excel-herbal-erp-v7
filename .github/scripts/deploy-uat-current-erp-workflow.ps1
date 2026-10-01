param(
  [Parameter(Mandatory = $true)]
  [string]$SourceHead,
  [Parameter(Mandatory = $true)]
  [string]$UatSiteUrl
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class UatWindowNative {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr window);
  [DllImport("user32.dll")] public static extern IntPtr SetActiveWindow(IntPtr window);
  [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr window);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr window, System.Text.StringBuilder className, int maxCount);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, IntPtr processId);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint attach, uint attachTo, bool value);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();

  public static string GetWindowClass(IntPtr window) {
    var name = new System.Text.StringBuilder(256);
    return GetClassName(window, name, name.Capacity) > 0 ? name.ToString() : "";
  }

  public static bool ForceForeground(IntPtr window) {
    ShowWindow(window, 9);
    if (GetForegroundWindow() == window) return true;

    IntPtr foreground = GetForegroundWindow();
    uint currentThread = GetCurrentThreadId();
    uint targetThread = GetWindowThreadProcessId(window, IntPtr.Zero);
    uint foregroundThread = foreground == IntPtr.Zero ? 0 : GetWindowThreadProcessId(foreground, IntPtr.Zero);
    bool currentToTarget = false;
    bool currentToForeground = false;
    try {
      if (targetThread != 0 && targetThread != currentThread) {
        currentToTarget = AttachThreadInput(currentThread, targetThread, true);
      }
      if (foregroundThread != 0 && foregroundThread != currentThread && foregroundThread != targetThread) {
        currentToForeground = AttachThreadInput(currentThread, foregroundThread, true);
      }
      BringWindowToTop(window);
      SetForegroundWindow(window);
      SetActiveWindow(window);
      SetFocus(window);
    } finally {
      if (currentToForeground) AttachThreadInput(currentThread, foregroundThread, false);
      if (currentToTarget) AttachThreadInput(currentThread, targetThread, false);
    }
    return GetForegroundWindow() == window;
  }
}
'@

if ($SourceHead -notmatch '^[a-f0-9]{40}$') {
  throw 'SourceHead must be a 40-character lowercase commit SHA.'
}

try { $uatUri = [Uri]$UatSiteUrl.TrimEnd('/') }
catch { throw 'UatSiteUrl must be a valid absolute HTTPS URL.' }
if (-not $uatUri.IsAbsoluteUri -or $uatUri.Scheme -ne 'https') {
  throw 'Controlled UAT site must use HTTPS.'
}
$script:isOfficeBuildUat = $uatUri.Host -ieq 'office.excelherbal.in'
if (-not $script:isOfficeBuildUat -and $uatUri.Host -notmatch '(?i)(^|[-.])(uat|staging)([-.]|$)') {
  throw 'UAT hostname must either be office.excelherbal.in during BUILD/UAT or explicitly contain uat/staging.'
}
$script:uatSiteRoot = $UatSiteUrl.TrimEnd('/')
Write-Host ('INFO build_uat_site=' + $script:uatSiteRoot + ' office_build_uat=' + $script:isOfficeBuildUat)

$repoRoot = $env:GITHUB_WORKSPACE
$releaseRoot = Join-Path $env:USERPROFILE ('ERP7-Releases\uat-candidates\' + $SourceHead)
$webZip = Join-Path $releaseRoot 'Excel-Herbal-ERP-v7.4.0-Web-Candidate.zip'
$candidateMain = Join-Path $releaseRoot 'web\main.dart.js'
$candidateManifest = Join-Path $releaseRoot 'web\SHA256SUMS.txt'
foreach ($required in @($webZip,$candidateMain,$candidateManifest)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
    throw ('Required certified web candidate file is missing: ' + $required)
  }
}
$expectedMainHash = (Get-FileHash -LiteralPath $candidateMain -Algorithm SHA256).Hash.ToLowerInvariant()
$expectedManifestHash = (Get-FileHash -LiteralPath $candidateManifest -Algorithm SHA256).Hash.ToLowerInvariant()

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
      if ($window.Current.ClassName -ne 'Chrome_WidgetWin_1' -or $window.Current.NativeWindowHandle -eq 0) { continue }
      $owner = Get-Process -Id $window.Current.ProcessId -ErrorAction Stop
      if ($owner.ProcessName -eq 'chrome') { $window }
    } catch {}
  }
}

function Get-ChromeWindowAddress($Window) {
  try {
    $all = $Window.FindAll(
      [System.Windows.Automation.TreeScope]::Descendants,
      [System.Windows.Automation.Condition]::TrueCondition
    )
    foreach ($element in $all) {
      try {
        if ($element.Current.ControlType -ne [System.Windows.Automation.ControlType]::Edit) { continue }
        $name = [string]$element.Current.Name
        if ($name -notmatch '(?i)address and search bar|search google or type a url') { continue }
        $pattern = $element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $value = ([string]$pattern.Current.Value).Trim()
        if ($value) { return $value }
      } catch {}
    }
  } catch {}
  return ''
}

function Normalize-WebAddress([string]$Address) {
  if (-not $Address) { return '' }
  $value = $Address.Trim()
  $value = $value -replace '^(?i)https?://',''
  return $value.TrimEnd('/')
}

function Test-WebAddressMatchesTarget([string]$Address,[string]$Target) {
  $candidateNormalized = Normalize-WebAddress $Address
  $targetNormalized = Normalize-WebAddress $Target
  if (-not $candidateNormalized -or -not $targetNormalized) { return $false }
  try {
    $candidateUri = [Uri]('https://' + $candidateNormalized)
    $targetUri = [Uri]('https://' + $targetNormalized)
    if ($candidateUri.Host -ine $targetUri.Host -or $candidateUri.AbsolutePath -ine $targetUri.AbsolutePath) { return $false }

    $candidatePairs = @{}
    foreach ($part in $candidateUri.Query.TrimStart('?').Split('&',[StringSplitOptions]::RemoveEmptyEntries)) {
      $kv = $part.Split('=',2)
      $key = [Uri]::UnescapeDataString($kv[0])
      $value = if ($kv.Count -gt 1) { [Uri]::UnescapeDataString($kv[1]) } else { '' }
      $candidatePairs[$key] = $value
    }
    foreach ($part in $targetUri.Query.TrimStart('?').Split('&',[StringSplitOptions]::RemoveEmptyEntries)) {
      $kv = $part.Split('=',2)
      $key = [Uri]::UnescapeDataString($kv[0])
      $value = if ($kv.Count -gt 1) { [Uri]::UnescapeDataString($kv[1]) } else { '' }
      if (-not $candidatePairs.ContainsKey($key) -or [string]$candidatePairs[$key] -cne $value) { return $false }
    }
    return $true
  } catch {
    return $candidateNormalized -eq $targetNormalized
  }
}

function Select-VerifiedWordPressCandidate($Candidates,[string]$AmbiguousMessage) {
  $items = @($Candidates)
  if ($items.Count -eq 0) { return $null }
  if ($items.Count -eq 1) { return $items[0] }

  $foreground = [UatWindowNative]::GetForegroundWindow()
  $foregroundMatches = @($items | Where-Object {
    [IntPtr]$_.Window.Current.NativeWindowHandle -eq $foreground
  })
  if ($foregroundMatches.Count -eq 1) { return $foregroundMatches[0] }

  # Multiple windows can be left behind by a previous WordPress upload and can
  # point to the exact same authenticated admin endpoint. When every candidate
  # is semantically equivalent, selecting one deterministic HWND is safe; any
  # differing admin URL remains ambiguous and still fails closed.
  $addresses = @($items | ForEach-Object { Normalize-WebAddress ([string]$_.Address) } | Select-Object -Unique)
  if ($addresses.Count -eq 1 -and $addresses[0]) {
    $selected = $items | Sort-Object { [int64]$_.Window.Current.NativeWindowHandle } | Select-Object -First 1
    Write-Host ('INFO equivalent_wp_windows=' + $items.Count + ' selected_hwnd=' + $selected.Window.Current.NativeWindowHandle + ' address=' + $selected.Address)
    return $selected
  }

  throw $AmbiguousMessage
}

function Get-AuthenticatedWordPressWindow([string]$Url,[string]$TitlePattern) {
  $target = Normalize-WebAddress $Url
  $urlMatches = @()
  $titleMatches = @()
  $admin = @()
  foreach ($window in (Get-ChromeWindows)) {
    try {
      $address = Get-ChromeWindowAddress $window
      $addressNormalized = Normalize-WebAddress $address
      if (-not $addressNormalized) { continue }
      try {
        $addressUri = [Uri]('https://' + $addressNormalized)
        $targetUri = [Uri]('https://' + $target)
        if ($addressUri.Host -ine $targetUri.Host -or -not $addressUri.AbsolutePath.StartsWith('/wp-admin',[StringComparison]::OrdinalIgnoreCase)) { continue }
      } catch { continue }
      if ([string]$window.Current.Name -match '(?i)Log In|Login') { continue }
      $entry = [pscustomobject]@{ Window = $window; Address = $address }
      $admin += $entry
      if (Test-WebAddressMatchesTarget $address $target) { $urlMatches += $entry }
      if ([string]$window.Current.Name -match $TitlePattern) { $titleMatches += $entry }
    } catch {}
  }
  $selected = Select-VerifiedWordPressCandidate $urlMatches 'More than one authenticated WordPress window has the requested deployment URL.'
  if ($selected) { return $selected }
  if ($titleMatches.Count -gt 1) {
    foreach ($entry in $titleMatches) {
      Write-Host ('INFO ambiguous_wp_title_candidate address=' + $entry.Address + ' hwnd=' + $entry.Window.Current.NativeWindowHandle)
    }
  }
  $selected = Select-VerifiedWordPressCandidate $titleMatches 'More than one authenticated WordPress window matches the requested deployment page.'
  if ($selected) { return $selected }
  return Select-VerifiedWordPressCandidate $admin 'More than one authenticated office WordPress admin window is open; deployment target is ambiguous.'
}

function Open-DedicatedChromeWindow([string]$Url,[string]$TitlePattern) {
  # Prefer the already-authenticated office WordPress admin window. Verify it
  # from Chrome's address-bar value before adopting its HWND; unrelated Chrome
  # windows are never reused. This keeps the deployment on the user's actual
  # authenticated profile while remaining fail-closed.
  $authenticated = Get-AuthenticatedWordPressWindow -Url $Url -TitlePattern $TitlePattern
  if ($authenticated) {
    $script:appWindowHandle = [IntPtr]$authenticated.Window.Current.NativeWindowHandle
    $owner = Get-Process -Id $authenticated.Window.Current.ProcessId -ErrorAction Stop
    Activate-OwnedChromeWindow $owner
    Write-Host ('INFO authenticated_wp_admin_window_reused=true address=' + $authenticated.Address + ' hwnd=' + $script:appWindowHandle)
    Navigate-ChromeWindow $owner $Url 5
    return $owner
  }

  # No verified authenticated admin window is currently visible. Open a new
  # top-level window, pin only the newly-created HWND, and let the caller reject
  # a WordPress login page rather than borrowing an unrelated browser window.
  $before = @{}
  foreach ($window in (Get-ChromeWindows)) { $before[[string]$window.Current.NativeWindowHandle] = $true }
  $script:appWindowHandle = [IntPtr]::Zero
  Start-Process -FilePath (Get-ChromeExe) -ArgumentList @('--new-window',$Url) | Out-Null
  for ($attempt=0; $attempt -lt 60; $attempt++) {
    Start-Sleep -Milliseconds 500
    $candidates = @(Get-ChromeWindows | Where-Object {
      -not $before.ContainsKey([string]$_.Current.NativeWindowHandle) -and
      $_.Current.Name -match ($TitlePattern + '|Log In|Login')
    })
    if ($candidates.Count -gt 1) { throw 'More than one new matching Chrome window appeared; deployment target is ambiguous.' }
    if ($candidates.Count -eq 1) {
      $script:appWindowHandle = [IntPtr]$candidates[0].Current.NativeWindowHandle
      $owner = Get-Process -Id $candidates[0].Current.ProcessId -ErrorAction Stop
      Activate-OwnedChromeWindow $owner
      return $owner
    }
  }
  throw ('Dedicated Chrome page did not open: ' + $Url)
}

function Root([System.Diagnostics.Process]$Process) {
  $Process.Refresh()
  if ($Process.HasExited -or $script:appWindowHandle -eq 0) { throw 'Owned deployment window is no longer available.' }
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($script:appWindowHandle)
  if (-not $root -or $root.Current.ProcessId -ne $Process.Id) { throw 'Deployment window ownership changed.' }
  return $root
}

function Activate-OwnedChromeWindow([System.Diagnostics.Process]$Process) {
  # Stay pinned to the verified HWND. Windows can deny a plain
  # SetForegroundWindow call to a background automation process, so use a
  # thread-input attachment fallback that still targets only this exact HWND.
  [void](Root $Process)
  for ($attempt=1; $attempt -le 3; $attempt++) {
    if ([UatWindowNative]::ForceForeground($script:appWindowHandle)) {
      Write-Host ('INFO deployment_foreground_activation_attempt=' + $attempt + ' hwnd=' + $script:appWindowHandle)
      return
    }
    Start-Sleep -Milliseconds (150 * $attempt)
  }
  throw 'Owned UAT Chrome window could not become foreground. Keep the runner desktop unlocked.'
}

function Navigate-ChromeWindow([System.Diagnostics.Process]$Process,[string]$Url,[int]$SettleSeconds=5) {
  $beforeRoot = Root $Process
  $beforeTitle = [string]$beforeRoot.Current.Name
  $beforeAddress = ''
  try { $beforeAddress = [string](Get-ChromeWindowAddress $beforeRoot) } catch {}
  $alreadyTarget = Test-WebAddressMatchesTarget $beforeAddress $Url

  for ($navAttempt=1; $navAttempt -le 3; $navAttempt++) {
    Activate-OwnedChromeWindow $Process
    Start-Sleep -Milliseconds 250
    [System.Windows.Forms.SendKeys]::SendWait('^l')
    Start-Sleep -Milliseconds 120
    [System.Windows.Forms.Clipboard]::SetText($Url)
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')

    $iterations = [Math]::Max(8,$SettleSeconds * 4)
    for ($attempt=0; $attempt -lt $iterations; $attempt++) {
      Start-Sleep -Milliseconds 250
      $root = Root $Process
      $title = [string]$root.Current.Name
      $address = ''
      try { $address = [string](Get-ChromeWindowAddress $root) } catch {}
      $addressMatches = Test-WebAddressMatchesTarget $address $Url
      $pageTransitioned = $alreadyTarget -or ($title -ne $beforeTitle)

      if ($addressMatches -and $pageTransitioned) {
        Write-Host ('INFO chrome_navigation_verified=true attempt=' + $navAttempt + ' address=' + $address)
        Write-Host ('INFO chrome_page_title=' + $title)
        return
      }
    }

    Write-Host ('INFO chrome_navigation_retry=' + $navAttempt + ' target=' + $Url)
    # If the address bar changed but content did not, re-entering the exact
    # target forces Chrome to commit/reload the requested admin page.
    $alreadyTarget = $false
  }

  $finalRoot = Root $Process
  $finalAddress = ''
  try { $finalAddress = [string](Get-ChromeWindowAddress $finalRoot) } catch {}
  throw ('Chrome navigation did not verify the requested page. target=' + $Url + ' address=' + $finalAddress + ' title=' + [string]$finalRoot.Current.Name)
}

function Wait-ForWordPressAdminAuthentication([System.Diagnostics.Process]$Process,[string]$TargetUrl,[int]$Seconds=480) {
  $notified = $false
  $iterations = [Math]::Max(1,$Seconds * 2)
  for ($attempt=0; $attempt -lt $iterations; $attempt++) {
    $root = Root $Process
    $title = [string]$root.Current.Name
    $address = ''
    try { $address = [string](Get-ChromeWindowAddress $root) } catch {}

    if ($title -notmatch '(?i)Log In|Login' -and $address -match '(?i)(https?://)?[^/]+/wp-admin(?:/|\?|$)') {
      Write-Host ('PASS wordpress_admin_session_authenticated=true address=' + $address)
      if (-not (Test-WebAddressMatchesTarget $address $TargetUrl)) {
        Navigate-ChromeWindow $Process $TargetUrl 5
        $root = Root $Process
        if ([string]$root.Current.Name -match '(?i)Log In|Login') {
          throw 'WordPress admin session became unauthenticated after post-login navigation.'
        }
      }
      return
    }

    if (-not $notified) {
      Activate-OwnedChromeWindow $Process
      Write-Host ('ACTION_REQUIRED wordpress_admin_login=true target=' + $TargetUrl)
      Write-Host 'ACTION_REQUIRED Complete WordPress admin login in the foreground runner Chrome window; deployment will continue automatically.'
      $notified = $true
    } elseif (($attempt % 20) -eq 0) {
      Write-Host ('INFO wordpress_admin_login_wait_seconds=' + [Math]::Floor($attempt / 2))
    }
    Start-Sleep -Milliseconds 500
  }
  throw 'WordPress admin login was not completed within the bounded deployment wait.'
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

function Find-ControlByIdOrNameLike(
  [System.Windows.Automation.AutomationElement]$Root,
  [string]$Id,
  [string[]]$Names,
  [System.Windows.Automation.AutomationPattern]$RequiredPattern
) {
  $byId = Find-ById $Root $Id
  if ($byId) {
    try {
      [void]$byId.GetCurrentPattern($RequiredPattern)
      return $byId
    } catch {}
  }

  $all = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  foreach ($element in $all) {
    try {
      $current = ([string]$element.Current.Name).Trim()
      if (-not $current) { continue }
      $matches = $false
      foreach ($pattern in $Names) {
        if ($current -like $pattern) { $matches = $true; break }
      }
      if (-not $matches) { continue }
      [void]$element.GetCurrentPattern($RequiredPattern)
      Write-Host ('INFO deployment_control_name_fallback id=' + $Id + ' name=' + $current)
      return $element
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

function Choose-File([System.Windows.Automation.AutomationElement]$Button,[string]$Path,[System.Diagnostics.Process]$Browser) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or [IO.Path]::GetExtension($Path) -ine '.zip') {
    throw 'The certified deployment ZIP is missing or invalid.'
  }
  $fullPath = [IO.Path]::GetFullPath($Path)
  $fileName = [IO.Path]::GetFileName($fullPath)
  # Chrome can host the native picker on a sibling browser process even when
  # the initiating page HWND is pinned correctly. Snapshot existing dialogs,
  # trigger the picker from the verified deployment window, then accept only
  # one newly-created visible native dialog. This stays fail-closed without
  # relying on Chrome's unstable process ownership.
  $beforeDialogs = @{}
  $existing = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
    [System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
  foreach ($window in $existing) {
    try {
      if ($window.Current.ClassName -eq '#32770' -and $window.Current.NativeWindowHandle -ne 0) {
        $beforeDialogs[[string]$window.Current.NativeWindowHandle] = $true
      }
    } catch {}
  }

  Activate-OwnedChromeWindow $Browser
  # The previously successful WordPress deployment path opens Chrome's native
  # file chooser through the input element's InvokePattern. Keep the newer
  # HWND/dialog verification below, but use that proven trigger rather than
  # keyboard Enter, which can leave the chooser unopened on Chrome.
  Invoke-Element $Button
  Write-Host 'INFO deployment_file_picker_trigger=invoke_pattern'
  $dialog = $null
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    Start-Sleep -Milliseconds 500

    # Prefer the actual foreground native dialog HWND when Chrome opens the
    # file picker outside the UIA RootElement child enumeration.
    $foreground = [UatWindowNative]::GetForegroundWindow()
    if ($foreground -ne [IntPtr]::Zero -and
        [UatWindowNative]::GetWindowClass($foreground) -eq '#32770' -and
        -not $beforeDialogs.ContainsKey([string]$foreground)) {
      try {
        $candidate = [System.Windows.Automation.AutomationElement]::FromHandle($foreground)
        if ($candidate -and $candidate.Current.IsEnabled -and -not $candidate.Current.IsOffscreen) {
          $dialog = $candidate
          Write-Host ('INFO deployment_file_picker_source=foreground hwnd=' + $foreground + ' pid=' + $dialog.Current.ProcessId)
          break
        }
      } catch {}
    }

    $windows = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
      [System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
    $candidates = @()
    foreach ($window in $windows) {
      try {
        $handle = [string]$window.Current.NativeWindowHandle
        if ($window.Current.ClassName -eq '#32770' -and $window.Current.NativeWindowHandle -ne 0 -and
            -not $beforeDialogs.ContainsKey($handle) -and $window.Current.IsEnabled -and -not $window.Current.IsOffscreen) {
          $candidates += $window
        }
      } catch {}
    }
    if ($candidates.Count -gt 1) { throw 'More than one new deployment file picker appeared; target is ambiguous.' }
    if ($candidates.Count -eq 1) {
      $dialog = $candidates[0]
      Write-Host ('INFO deployment_file_picker_source=uia_root pid=' + $dialog.Current.ProcessId + ' hwnd=' + $dialog.Current.NativeWindowHandle)
      break
    }
  }
  if (-not $dialog) { throw 'Chrome deployment file picker did not become ready.' }
  $fileControl = Find-ById $dialog '1148'
  if (-not $fileControl) { throw 'Deployment file picker filename control is missing.' }
  $editCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Edit)
  $edit = $fileControl.FindFirst([System.Windows.Automation.TreeScope]::Subtree,$editCondition)
  if (-not $edit) { throw 'Deployment file picker filename edit is missing.' }
  $dialogHandle = [IntPtr]$dialog.Current.NativeWindowHandle
  if ([UatWindowNative]::GetWindowClass($dialogHandle) -ne '#32770') {
    throw 'Deployment file picker HWND changed before verified confirmation.'
  }
  if (-not [UatWindowNative]::ForceForeground($dialogHandle) -or
      [UatWindowNative]::GetForegroundWindow() -ne $dialogHandle) {
    throw 'Deployment file picker could not be safely focused for verified confirmation.'
  }

  # ValuePattern alone can update the visible filename text without changing
  # the native dialog's selected file. That can cause Windows to submit a
  # previously selected ZIP. Focus the verified filename edit, paste the exact
  # certified path, read it back, and confirm with Enter on this exact dialog.
  $dialog = [System.Windows.Automation.AutomationElement]::FromHandle($dialogHandle)
  if (-not $dialog -or -not $dialog.Current.IsEnabled -or $dialog.Current.IsOffscreen) {
    throw 'Deployment file picker became unavailable before verified confirmation.'
  }
  $fileControl = Find-ById $dialog '1148'
  if (-not $fileControl) { throw 'Deployment file picker filename control disappeared before verified confirmation.' }
  $edit = $fileControl.FindFirst([System.Windows.Automation.TreeScope]::Subtree,$editCondition)
  if (-not $edit) { throw 'Deployment file picker filename edit disappeared before verified confirmation.' }

  $edit.SetFocus()
  [System.Windows.Forms.Clipboard]::SetText($fullPath)
  [System.Windows.Forms.SendKeys]::SendWait('^a')
  [System.Windows.Forms.SendKeys]::SendWait('^v')
  Start-Sleep -Milliseconds 150
  $value = $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
  if ($value.Current.Value -ne $fullPath) {
    throw 'Deployment file picker did not retain the exact certified ZIP path.'
  }
  Write-Host ('INFO deployment_file_picker_exact_path=' + $value.Current.Value)
  Write-Host 'INFO deployment_file_picker_confirm=verified_keyboard'
  [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')

  # Do not trust the pre-picker UIA file-input object after the native dialog
  # closes. Chrome can leave that object stale even though the file was
  # accepted. Instead require the native picker to close and the verified
  # browser HWND/UIA root to become usable again. The caller then re-queries
  # the form controls and performs the authoritative submit/server checks.
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    Start-Sleep -Milliseconds 250
    $foreground = [UatWindowNative]::GetForegroundWindow()
    if ($foreground -ne $dialogHandle) {
      try {
        [void](Root $Browser)
        Write-Host ('PASS deployment_file_picker_closed=' + $fileName)
        return
      } catch {}
    }
  }
  throw 'Deployment file picker did not close after verified fallback confirmation.'
}

function Assert-ControlledUatTarget([bool]$RequireErpHealth=$false) {
  $health = $null
  try {
    $health = Invoke-RestMethod -UseBasicParsing -Uri ($script:uatSiteRoot + '/wp-json/excel-herbal-erp/v7/health?cb=' + [Guid]::NewGuid().ToString('N')) -TimeoutSec 20
  } catch {
    if ($RequireErpHealth) {
      throw ('Controlled UAT ERP health endpoint is required after backend deployment: ' + $_.Exception.Message)
    }
    Write-Host 'INFO controlled_uat_erp_health_not_installed_yet=true'
    return
  }

  $data = if ($health.data) { $health.data } else { $health }
  if (-not $data) { throw 'Controlled UAT health response is empty.' }
  if ([string]$data.environment -ne 'staging') {
    if (-not $RequireErpHealth -and $script:isOfficeBuildUat) {
      Write-Host ('INFO office_build_uat_previous_environment=' + [string]$data.environment)
      return
    }
    throw ('BUILD/UAT target must report environment=staging after backend deployment; got ' + [string]$data.environment)
  }
  if (-not $data.staging_safety -or $data.staging_safety.required -ne $true) {
    throw 'Controlled UAT target does not require staging safety.'
  }
  Write-Host ('PASS controlled_uat_environment=staging host=' + ([Uri]$script:uatSiteRoot).Host)
}

function Get-HealthSourceHead {
  try {
    $health = Invoke-RestMethod -UseBasicParsing -Uri ($script:uatSiteRoot + '/wp-json/excel-herbal-erp/v7/health?cb=' + [Guid]::NewGuid().ToString('N')) -TimeoutSec 20
    if ($health.data -and $health.data.source_head) { return [string]$health.data.source_head }
    if ($health.source_head) { return [string]$health.source_head }
    return ''
  } catch { return '' }
}

function Get-WebRuntimeHealth {
  try {
    $health = Invoke-RestMethod -UseBasicParsing -Uri ($script:uatSiteRoot + '/wp-json/excel-herbal-erp/v7/health?cb=' + [Guid]::NewGuid().ToString('N')) -TimeoutSec 20
    if ($health.data -and $health.data.web_runtime) { return $health.data.web_runtime }
    if ($health.web_runtime) { return $health.web_runtime }
  } catch {}
  return $null
}

function Get-LiveMainHash {
  $urlBase = $script:uatSiteRoot + '/wp-content/uploads/eh7-flutter-web/main.dart.js'
  $lastExit = -1
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    $tmp = Join-Path $env:RUNNER_TEMP ('eh7-live-main-' + [Guid]::NewGuid().ToString('N') + '.js')
    try {
      & curl.exe --fail --location --silent --show-error --connect-timeout 15 --max-time 90 --retry 2 --retry-delay 2 --retry-all-errors --output $tmp ($urlBase + '?cb=' + [Guid]::NewGuid().ToString('N'))
      $lastExit = $LASTEXITCODE
      if ($lastExit -eq 0 -and (Test-Path -LiteralPath $tmp -PathType Leaf) -and (Get-Item -LiteralPath $tmp).Length -gt 0) {
        $hash = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Host ('INFO live_main_download_attempt=' + $attempt + ' sha256=' + $hash)
        return $hash
      }
      Write-Host ('INFO live_main_download_retry=' + $attempt + ' curl_exit=' + $lastExit)
    } finally {
      Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    if ($attempt -lt 3) { Start-Sleep -Seconds (2 * $attempt) }
  }
  throw ('Live main.dart.js could not be downloaded after retries. curl_exit=' + $lastExit)
}

function New-BackendPluginZip {
  $source = Join-Path $repoRoot 'backend\excel-herbal-erp-v7'
  $work = Join-Path $env:RUNNER_TEMP ('eh7-backend-deploy-' + [Guid]::NewGuid().ToString('N'))
  $plugin = Join-Path $work 'excel-herbal-erp-v7'
  $zipPath = Join-Path $env:RUNNER_TEMP ('excel-herbal-erp-v7-' + $SourceHead.Substring(0,8) + '.zip')
  if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
  New-Item -ItemType Directory -Path $plugin -Force | Out-Null
  Copy-Item -Path (Join-Path $source '*') -Destination $plugin -Recurse -Force
  $uatHost = ([Uri]$script:uatSiteRoot).Host.ToLowerInvariant()
  $allowOffice = if ($script:isOfficeBuildUat) { 'true' } else { 'false' }
  @(
    '<?php',
    "if(!defined('ABSPATH'))exit;",
    "define('EH7_SOURCE_HEAD','$SourceHead');",
    "define('EH7_DEPLOY_ENVIRONMENT','staging');",
    "define('EH7_BUILD_UAT_ALLOW_OFFICE',$allowOffice);",
    "define('EH7_BUILD_UAT_HOST','$uatHost');"
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

  $chrome = Open-DedicatedChromeWindow -Url ($script:uatSiteRoot + '/wp-admin/plugin-install.php?tab=upload') -TitlePattern 'Add Plugins|Upload Plugin'
  Activate-OwnedChromeWindow $chrome
  Start-Sleep -Seconds 5
  Wait-ForWordPressAdminAuthentication $chrome ($script:uatSiteRoot + '/wp-admin/plugin-install.php?tab=upload')

  $root = Root $chrome
  $file = $null
  $install = $null
  for ($pageAttempt=1; $pageAttempt -le 3; $pageAttempt++) {
    $root = Root $chrome
    $file = Find-ById $root 'pluginzip'
    if (-not $file) { $file = Find-ByName $root 'Choose File*' $true }
    if (-not $file) { $file = Find-ByName $root '*No file chosen*' $true }
    $install = Find-ById $root 'install-plugin-submit'
    if (-not $install) { $install = Find-ByName $root 'Install Now' }
    if ($file -and $install) { break }
    Write-Host ('INFO backend_upload_controls_retry=' + $pageAttempt)
    try { Write-UiHints $root ('backend_upload_controls_missing_' + $pageAttempt) } catch {}
    Navigate-ChromeWindow $chrome ($script:uatSiteRoot + '/wp-admin/plugin-install.php?tab=upload') 5
  }
  if (-not $file -or -not $install) {
    throw 'WordPress Upload Plugin controls were not found after explicit navigation retries.'
  }
  Write-Host ('INFO backend_choose_control=' + [string]$file.Current.Name + ' automation_id=' + [string]$file.Current.AutomationId)
  Write-Host ('INFO backend_install_control=' + [string]$install.Current.Name + ' automation_id=' + [string]$install.Current.AutomationId)
  Choose-File $file $ZipPath $chrome

  $root = Root $chrome
  $install = Find-ById $root 'install-plugin-submit'
  if (-not $install) { $install = Find-ByName $root 'Install Now' }
  if (-not $install -or -not $install.Current.IsEnabled) {
    Write-UiHints $root 'backend_install_unavailable'
    throw 'Install Now is unavailable after choosing the backend ZIP.'
  }
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

function Attest-ExistingWebRuntime {
  $chrome = Open-DedicatedChromeWindow -Url ($script:uatSiteRoot + '/wp-admin/tools.php?page=eh7-uat-web-deploy') -TitlePattern 'EH7 UAT Web Deploy'
  Activate-OwnedChromeWindow $chrome
  Start-Sleep -Seconds 4
  Wait-ForWordPressAdminAuthentication $chrome ($script:uatSiteRoot + '/wp-admin/tools.php?page=eh7-uat-web-deploy')

  $root = Root $chrome
  $source = Find-ById $root 'eh7_attest_source_head'
  $main = Find-ById $root 'eh7_attest_main_sha256'
  $manifest = Find-ById $root 'eh7_attest_manifest_sha256'
  $reason = Find-ById $root 'eh7_attest_reason'
  $confirm = Find-ById $root 'eh7_attest_confirm'
  $submit = Find-ById $root 'eh7_attest_submit'
  if (-not $source -or -not $main -or -not $manifest -or -not $reason -or -not $confirm -or -not $submit) {
    try { Write-UiHints $root 'web_attest_controls_missing' } catch {}
    throw 'Byte-identical runtime attestation controls were not found.'
  }

  Set-ElementValue $source $SourceHead
  Set-ElementValue $main $expectedMainHash
  Set-ElementValue $manifest $expectedManifestHash
  Set-ElementValue $reason 'Attest byte-identical exact-head build on controlled UAT'
  $toggle = $confirm.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
  if ($toggle.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On) { $toggle.Toggle() }
  Invoke-Element $submit
  Write-Host 'INFO web_attest_submit_invoked=true'

  for ($attempt = 1; $attempt -le 12; $attempt++) {
    Start-Sleep -Seconds 3
    $runtime = Get-WebRuntimeHealth
    $marker = if ($runtime -and $runtime.source_head) { [string]$runtime.source_head } else { '' }
    $mainHash = if ($runtime -and $runtime.main_sha256) { [string]$runtime.main_sha256 } else { '' }
    $manifestHash = if ($runtime -and $runtime.manifest_sha256) { [string]$runtime.manifest_sha256 } else { '' }
    Write-Host ('INFO web_attest_poll=' + $attempt + ' source_marker=' + $marker + ' main_sha256=' + $mainHash + ' manifest_sha256=' + $manifestHash)
    if ($marker -eq $SourceHead -and $mainHash -eq $expectedMainHash -and $manifestHash -eq $expectedManifestHash) {
      Write-Host ('PASS live_web_source_head=' + $marker)
      Write-Host ('PASS live_web_sha256=' + $mainHash)
      Write-Host ('PASS live_web_manifest_sha256=' + $manifestHash)
      return
    }
  }
  throw 'Byte-identical UAT web runtime attestation did not advance the certified source marker.'
}

function Deploy-WebRuntime {
  $before = Get-LiveMainHash
  Write-Host ('INFO current_live_main_sha256=' + $before)
  Write-Host ('INFO expected_main_sha256=' + $expectedMainHash)
  Write-Host ('INFO expected_manifest_sha256=' + $expectedManifestHash)

  $runtime = Get-WebRuntimeHealth
  $currentMarker = if ($runtime -and $runtime.source_head) { [string]$runtime.source_head } else { '' }
  $serverMainHash = if ($runtime -and $runtime.main_sha256) { [string]$runtime.main_sha256 } else { '' }
  $serverManifestHash = if ($runtime -and $runtime.manifest_sha256) { [string]$runtime.manifest_sha256 } else { '' }

  if ($before -eq $expectedMainHash -and $serverMainHash -eq $expectedMainHash -and $serverManifestHash -eq $expectedManifestHash -and $currentMarker -eq $SourceHead) {
    Write-Host 'PASS certified web runtime hashes and source marker are already live.'
    Write-Host ('INFO live_web_source_marker=' + $currentMarker)
    return
  }
  if ($before -eq $expectedMainHash -and $serverMainHash -eq $expectedMainHash -and $serverManifestHash -eq $expectedManifestHash -and $currentMarker -ne $SourceHead) {
    Write-Host ('INFO web_runtime_byte_identical_marker_requires_attestation=' + $currentMarker)
    Attest-ExistingWebRuntime
    return
  }
  if ($before -eq $expectedMainHash -and $serverMainHash -eq $expectedMainHash -and $serverManifestHash -ne $expectedManifestHash) {
    Write-Host ('INFO main_hash_matches_but_manifest_differs=' + $serverManifestHash)
  } elseif ($before -eq $expectedMainHash) {
    Write-Host ('INFO browser_web_hash_matches_but_server_hash_differs=' + $serverMainHash)
  }

  $chrome = Open-DedicatedChromeWindow -Url ($script:uatSiteRoot + '/wp-admin/tools.php?page=eh7-uat-web-deploy') -TitlePattern 'EH7 UAT Web Deploy'
  Activate-OwnedChromeWindow $chrome
  Start-Sleep -Seconds 5
  Wait-ForWordPressAdminAuthentication $chrome ($script:uatSiteRoot + '/wp-admin/tools.php?page=eh7-uat-web-deploy')

  $root = Root $chrome
  $file = $null
  $source = $null
  $reason = $null
  $confirm = $null
  $submit = $null
  for ($pageAttempt=1; $pageAttempt -le 3; $pageAttempt++) {
    $root = Root $chrome
    $file = Find-ControlByIdOrNameLike $root 'eh7_web_bundle' @('*Certified Flutter Web ZIP*','*Choose File*') ([System.Windows.Automation.InvokePattern]::Pattern)
    $source = Find-ControlByIdOrNameLike $root 'eh7_source_head' @('*Certified source head*') ([System.Windows.Automation.ValuePattern]::Pattern)
    $reason = Find-ControlByIdOrNameLike $root 'eh7_reason' @('*Audit reason*') ([System.Windows.Automation.ValuePattern]::Pattern)
    $confirm = Find-ControlByIdOrNameLike $root 'eh7_confirm' @('*confirm this certified BUILD/UAT web deployment*') ([System.Windows.Automation.TogglePattern]::Pattern)
    $submit = Find-ControlByIdOrNameLike $root 'eh7_submit' @('Deploy Certified Web Bundle') ([System.Windows.Automation.InvokePattern]::Pattern)
    if ($file -and $source -and $reason -and $confirm -and $submit) { break }
    Write-Host ('INFO web_deploy_controls_retry=' + $pageAttempt)
    try { Write-UiHints $root ('web_deploy_controls_missing_' + $pageAttempt) } catch {}
    Navigate-ChromeWindow $chrome ($script:uatSiteRoot + '/wp-admin/tools.php?page=eh7-uat-web-deploy') 5
  }
  if (-not $file -or -not $source -or -not $reason -or -not $confirm -or -not $submit) {
    throw 'Current ERP UAT web deployment controls were not found after explicit navigation retries.'
  }

  Choose-File $file $webZip $chrome
  $root = Root $chrome
  Set-ElementValue (Find-ControlByIdOrNameLike $root 'eh7_source_head' @('*Certified source head*') ([System.Windows.Automation.ValuePattern]::Pattern)) $SourceHead
  Set-ElementValue (Find-ControlByIdOrNameLike $root 'eh7_reason' @('*Audit reason*') ([System.Windows.Automation.ValuePattern]::Pattern)) 'Deploy certified exact-head build to controlled UAT'
  $confirm = Find-ControlByIdOrNameLike $root 'eh7_confirm' @('*confirm this certified BUILD/UAT web deployment*') ([System.Windows.Automation.TogglePattern]::Pattern)
  $toggle = $confirm.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
  if ($toggle.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On) { $toggle.Toggle() }

  # Submit the real HTML form through the visible browser. WordPress can take
  # well over the old fixed wait to validate/extract a production Flutter ZIP,
  # so verify by polling the server-side source marker instead of assuming a
  # 12-18 second completion time.
  $submit = Find-ControlByIdOrNameLike (Root $chrome) 'eh7_submit' @('Deploy Certified Web Bundle') ([System.Windows.Automation.InvokePattern]::Pattern)
  if (-not $submit) { throw 'Deploy Certified Web Bundle submit control disappeared before submission.' }
  Invoke-Element $submit
  Write-Host 'INFO web_deploy_submit_invoked=true'

  $marker = ''
  $serverHash = ''
  $serverManifest = ''
  $runtime = $null
  for ($attempt = 1; $attempt -le 18; $attempt++) {
    Start-Sleep -Seconds 5
    try {
      $runtime = Get-WebRuntimeHealth
      $marker = if ($runtime -and $runtime.source_head) { [string]$runtime.source_head } else { '' }
      $serverHash = if ($runtime -and $runtime.main_sha256) { [string]$runtime.main_sha256 } else { '' }
      $serverManifest = if ($runtime -and $runtime.manifest_sha256) { [string]$runtime.manifest_sha256 } else { '' }
      Write-Host ('INFO web_deploy_poll=' + $attempt + ' source_marker=' + $marker + ' main_sha256=' + $serverHash + ' manifest_sha256=' + $serverManifest)
      if ($marker -eq $SourceHead -and $serverHash -eq $expectedMainHash -and $serverManifest -eq $expectedManifestHash) { break }
    } catch {
      Write-Host ('INFO web_deploy_poll=' + $attempt + ' health_error=' + $_.Exception.Message)
    }
  }

  if ($marker -ne $SourceHead) { throw ('Live server-side web source marker mismatch after deployment wait: ' + $marker) }
  if ($serverHash -ne $expectedMainHash) { throw ('Live server-side web main.dart.js hash mismatch: ' + $serverHash) }
  if ($serverManifest -ne $expectedManifestHash) { throw ('Live server-side web manifest hash mismatch: ' + $serverManifest) }

  $actual = Get-LiveMainHash
  Write-Host ('INFO final_live_main_sha256=' + $actual)
  if ($actual -ne $expectedMainHash) {
    throw 'Live browser-facing main.dart.js hash does not match the certified candidate after deployment.'
  }
  Write-Host ('PASS live_web_source_head=' + $marker)
  Write-Host ('PASS live_web_sha256=' + $serverHash)
  Write-Host ('PASS live_web_manifest_sha256=' + $serverManifest)
}

function Resolve-UatAnomalies {
  $chrome = Open-DedicatedChromeWindow -Url ($script:uatSiteRoot + '/wp-admin/tools.php?page=eh7-uat-cleanup') -TitlePattern 'EH7 UAT Cleanup'
  Activate-OwnedChromeWindow $chrome
  Start-Sleep -Seconds 5
  Wait-ForWordPressAdminAuthentication $chrome ($script:uatSiteRoot + '/wp-admin/tools.php?page=eh7-uat-cleanup')

  $root = Root $chrome
  $reason = $null
  $confirm = $null
  $submit = $null
  for ($pageAttempt=1; $pageAttempt -le 3; $pageAttempt++) {
    $root = Root $chrome
    $reason = Find-ById $root 'eh7_reason'
    $confirm = Find-ByName $root '*confirm safe UAT anomaly resolution*' $true
    $submit = Find-ByName $root 'Resolve Safe UAT Anomalies'
    if ($reason -and $confirm -and $submit) { break }
    Write-Host ('INFO uat_cleanup_controls_retry=' + $pageAttempt)
    try { Write-UiHints $root ('uat_cleanup_controls_missing_' + $pageAttempt) } catch {}
    Navigate-ChromeWindow $chrome ($script:uatSiteRoot + '/wp-admin/tools.php?page=eh7-uat-cleanup') 5
  }
  if (-not $reason -or -not $confirm -or -not $submit) {
    throw 'EH7 UAT Cleanup controls were not found after explicit navigation retries.'
  }

  Set-ElementValue $reason 'Resolve verified post-deployment UAT anomalies after diagnostics review'
  $toggle = $confirm.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
  if ($toggle.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On) { $toggle.Toggle() }
  Invoke-Element $submit
  Write-Host 'INFO uat_cleanup_submit_invoked=true'

  $healthy = $false
  $lastState = ''
  for ($attempt = 1; $attempt -le 15; $attempt++) {
    Start-Sleep -Seconds 2
    try {
      $health = Invoke-RestMethod -UseBasicParsing -Uri ($script:uatSiteRoot + '/wp-json/excel-herbal-erp/v7/health?cb=' + [Guid]::NewGuid().ToString('N')) -TimeoutSec 20
      $data = if ($health.data) { $health.data } else { $health }
      $safety = $data.staging_safety
      $seed = $data.uat_bootstrap
      $safetyOk = $safety -and $safety.sanitized -eq $true -and $safety.source_head_match -eq $true -and $safety.active_mobile_sessions_zero -eq $true -and $safety.active_push_devices_zero -eq $true -and $safety.search_indexing_disabled -eq $true
      $seedOk = $seed -and $seed.seeded -eq $true -and $seed.source_head_match -eq $true -and $seed.synthetic_only -eq $true -and $seed.admin_employee_present -eq $true -and $seed.limited_employee_present -eq $true
      $lastState = 'safety_sanitized=' + [string]$safety.sanitized + ' safety_source_match=' + [string]$safety.source_head_match + ' seed_seeded=' + [string]$seed.seeded + ' seed_source_match=' + [string]$seed.source_head_match + ' synthetic_only=' + [string]$seed.synthetic_only
      Write-Host ('INFO uat_cleanup_health_poll=' + $attempt + ' ' + $lastState)
      if ($safetyOk -and $seedOk) {
        $healthy = $true
        break
      }
    } catch {
      $lastState = 'health_error=' + $_.Exception.Message
      Write-Host ('INFO uat_cleanup_health_poll=' + $attempt + ' ' + $lastState)
    }
  }

  $root = Root $chrome
  $success = ''
  $diag = ''
  try {
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
    foreach ($element in $all) {
      try {
        $name = ([string]$element.Current.Name).Trim()
        if ($name -like 'UAT cleanup complete:*') { $success = $name }
        if ($name -like 'Current diagnostics:*') { $diag = $name }
      } catch {}
    }
  } catch {}

  if (-not $healthy) {
    try { Write-UiHints $root 'uat_cleanup_health_not_ready' } catch {}
    throw ('EH7 UAT cleanup/safety attestation did not become healthy. ' + $lastState)
  }
  if ($success) { Write-Host ('INFO uat_cleanup_ui_result=' + $success) }
  if ($diag) { Write-Host ('INFO uat_cleanup_diagnostics_label=' + $diag) }
  Write-Host 'PASS uat_cleanup_staging_safety_and_fresh_seed_health=true'
}

Assert-ControlledUatTarget -RequireErpHealth $false
$backendZip = New-BackendPluginZip
try {
  Deploy-BackendPlugin $backendZip
  Assert-ControlledUatTarget -RequireErpHealth $true
  Deploy-WebRuntime
  Resolve-UatAnomalies
} finally {
  Remove-Item -LiteralPath $backendZip -Force -ErrorAction SilentlyContinue
}
