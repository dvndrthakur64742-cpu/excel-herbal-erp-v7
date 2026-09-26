# Behavioral tests with fake browser/UIA boundaries: no browser, network or ERP data.
$ErrorActionPreference = 'Stop'
$tokens = $null
$parseErrors = $null
$source = Join-Path $PSScriptRoot 'uat-runtime-screen-smoke.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw 'UAT smoke script did not parse.' }
foreach ($name in @('Get-ChromeWindows','Get-ChromeProcessCommandLine','Open-AppWindow','Root','Wait-ForFreshLogin')) {
  $definition = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
  },$true)
  if (-not $definition) { throw ('Missing function: ' + $name) }
  . ([scriptblock]::Create($definition.Extent.Text))
}

function Assert($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Get-ChromeExe { return 'fake-chrome.exe' }
function Start-Sleep { param($Milliseconds) }
function Start-Process {
  param($FilePath,$ArgumentList,$WindowStyle)
  $script:launchArguments = $ArgumentList
}
$process = [System.Diagnostics.Process]::GetCurrentProcess()
$personalWindow = [pscustomobject]@{ Current = [pscustomobject]@{ NativeWindowHandle = 101; ProcessId = 501; ClassName = 'Chrome_WidgetWin_1' } }
$isolatedWindow = [pscustomobject]@{ Current = [pscustomobject]@{ NativeWindowHandle = 202; ProcessId = $process.Id; ClassName = 'Chrome_WidgetWin_1' } }
$script:windowReads = 0
$script:showIsolatedWindow = $true
function Get-ChromeWindows {
  $script:windowReads++
  $personalWindow
  if ($script:windowReads -gt 1 -and $script:showIsolatedWindow) { $isolatedWindow }
}
function Get-ChromeProcessCommandLine {
  param($ProcessId)
  if ($ProcessId -eq $process.Id) { return 'chrome.exe --user-data-dir="C:\Temp\profile with spaces"' }
  return 'chrome.exe --user-data-dir="C:\Users\intel\AppData\Local\Google\Chrome\User Data"'
}
function Get-Process {
  param($Id,$ErrorAction)
  if ($Id -eq $process.Id) { return $process }
  throw 'Personal Chrome process must never be adopted.'
}
$launched = Open-AppWindow 'https://office.excelherbal.in/wp-content/uploads/eh7-flutter-web/' 'C:\Temp\profile with spaces'
Assert ([object]::ReferenceEquals($launched,$process)) 'Must return only the isolated-profile browser process.'
Assert ($script:appWindowHandle -eq 202) 'Must capture the isolated-profile window, not a personal New Tab.'
Assert ($script:launchArguments -contains '--user-data-dir="C:\Temp\profile with spaces"') 'Profile path must be quoted.'
Assert ($script:launchArguments -contains '--app=https://office.excelherbal.in/wp-content/uploads/eh7-flutter-web/') 'App window must use the requested UAT URL.'
Write-Host 'PASS isolated_browser_launch'

$script:windowReads = 0
$script:showIsolatedWindow = $false
$failed = $false
try { Open-AppWindow 'https://office.excelherbal.in/' 'C:\Temp\profile with spaces' | Out-Null } catch { $failed = $true }
Assert $failed 'A launch without a matching isolated-profile window must fail instead of adopting an existing browser.'
Write-Host 'PASS launch_failure_no_fallback'

# Stub only the UI Automation boundary; Root still uses a real Process object.
Add-Type -TypeDefinition @'
namespace System.Windows.Automation {
  public class FakeCurrent { public int ProcessId; }
  public class AutomationElement {
    public FakeCurrent Current = new FakeCurrent();
    public static int Owner;
    public static System.IntPtr ObservedHandle;
    public static AutomationElement FromHandle(System.IntPtr handle) {
      ObservedHandle = handle;
      var element = new AutomationElement();
      element.Current.ProcessId = Owner;
      return element;
    }
  }
}
'@
$process = [System.Diagnostics.Process]::GetCurrentProcess()
[System.Windows.Automation.AutomationElement]::Owner = $process.Id
$script:appWindowHandle = [IntPtr]101
Root $process | Out-Null
Assert ([System.Windows.Automation.AutomationElement]::ObservedHandle -eq 101) 'Root must use the pinned handle, not the process current main window.'
[System.Windows.Automation.AutomationElement]::Owner = -1
$failed = $false
try { Root $process | Out-Null } catch { $failed = $true }
Assert $failed 'A recycled window belonging to another process must fail closed.'
$script:appWindowHandle = [IntPtr]::Zero
$failed = $false
try { Root $process | Out-Null } catch { $failed = $true }
Assert $failed 'A missing window must fail closed.'
Write-Host 'PASS pinned_window_and_ownership'

$script:readyQueue = New-Object System.Collections.Queue
$script:waits = @()
$script:invocations = 0
$script:invokeResult = $true
function Wait-ForAnyName {
  param($Process,$Names,$Seconds)
  $script:waits += ,@($Names,$Seconds)
  return $script:readyQueue.Dequeue()
}
function Try-Invoke { param($Element) $script:invocations++; return $script:invokeResult }
$enable = [pscustomobject]@{ Current = [pscustomobject]@{ Name = 'Enable accessibility' } }
$login = [pscustomobject]@{ Current = [pscustomobject]@{ Name = 'SIGN IN' } }
$script:readyQueue.Enqueue($enable)
$script:readyQueue.Enqueue($login)
$result = Wait-ForFreshLogin $process
Assert ([object]::ReferenceEquals($result,$login)) 'Cold startup must enable semantics and return the actual login control.'
Assert ($script:waits[0][0] -contains 'Enable accessibility') 'Readiness must include the delayed accessibility control.'
Assert ($script:waits[0][1] -eq 90) 'Cold startup must retain the bounded readiness budget.'
Assert ($script:invocations -eq 1) 'Accessibility must be invoked once.'
$script:readyQueue.Enqueue($login)
$result = Wait-ForFreshLogin $process
Assert ([object]::ReferenceEquals($result,$login)) 'Already enabled semantics must return login directly.'
Assert ($script:invocations -eq 1) 'Already enabled semantics must not invoke SIGN IN before credentials.'
foreach ($scenario in @('not_ready','invoke_failed','no_login_after_enable')) {
  $script:invokeResult = $scenario -ne 'invoke_failed'
  if ($scenario -eq 'not_ready') { $script:readyQueue.Enqueue($null) }
  else {
    $script:readyQueue.Enqueue($enable)
    if ($scenario -eq 'no_login_after_enable') { $script:readyQueue.Enqueue($null) }
  }
  $failed = $false
  try { Wait-ForFreshLogin $process | Out-Null } catch { $failed = $true }
  Assert $failed ('Readiness must fail closed: ' + $scenario)
}
Write-Host 'PASS delayed_accessibility_and_login_readiness'

$deploySource = Join-Path $PSScriptRoot 'deploy-uat-current-erp-workflow.ps1'
$deployAst = [System.Management.Automation.Language.Parser]::ParseFile($deploySource,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw 'Deployment script did not parse.' }
foreach ($name in @('Get-ChromeWindowAddress','Normalize-WebAddress','Select-VerifiedWordPressCandidate','Get-AuthenticatedWordPressWindow','Open-DedicatedChromeWindow','Root')) {
  $definition = $deployAst.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
  },$true)
  if (-not $definition) { throw ('Missing deployment function: ' + $name) }
  . ([scriptblock]::Create($definition.Extent.Text))
}

$chooseFileDefinition = $deployAst.Find({ param($node)
  $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Choose-File'
},$true)
Assert ($chooseFileDefinition -and $chooseFileDefinition.Extent.Text -like '*Invoke-Element $Button*') 'Deployment file picker must be opened through the file input InvokePattern.'
Write-Host 'PASS deployment_file_picker_uses_invoke_pattern'
function Get-Process { param($Id,$ErrorAction) return $process }
function Activate-OwnedChromeWindow { param($Process) $script:focusedHandle = $script:appWindowHandle }
function Navigate-ChromeWindow {
  param($Process,$Url,$SettleSeconds)
  $script:navigatedUrl = $Url
  $script:focusedHandle = $script:appWindowHandle
}
function Get-ChromeWindowAddress { param($Window) return [string]$Window.Address }
$adminWindow = [pscustomobject]@{
  Address = 'https://office.excelherbal.in/wp-admin/'
  Current = [pscustomobject]@{ NativeWindowHandle = 201; ProcessId = $process.Id; Name = 'Dashboard - Excel Herbal - WordPress'; ClassName = 'Chrome_WidgetWin_1' }
}
$uploadWindow = [pscustomobject]@{
  Address = 'https://office.excelherbal.in/wp-admin/plugin-install.php?tab=upload'
  Current = [pscustomobject]@{ NativeWindowHandle = 211; ProcessId = $process.Id; Name = 'Add Plugins - Excel Herbal - WordPress'; ClassName = 'Chrome_WidgetWin_1' }
}
$personalWindow = [pscustomobject]@{
  Address = 'https://www.google.com/'
  Current = [pscustomobject]@{ NativeWindowHandle = 301; ProcessId = $process.Id; Name = 'New Tab - Google Chrome'; ClassName = 'Chrome_WidgetWin_1' }
}
$newWindow = [pscustomobject]@{
  Address = 'https://office.excelherbal.in/wp-admin/tools.php?page=eh7-uat-cleanup'
  Current = [pscustomobject]@{ NativeWindowHandle = 202; ProcessId = $process.Id; Name = 'EH7 UAT Cleanup - Chrome'; ClassName = 'Chrome_WidgetWin_1' }
}
$script:windowMode = 'reuse'
$script:windowReads = 0
$script:deployLaunches = 0
$script:navigatedUrl = ''
function Get-ChromeWindows {
  $script:windowReads++
  if ($script:windowMode -eq 'reuse') { $adminWindow; return }
  if ($script:windowMode -eq 'precise') { $adminWindow; $uploadWindow; return }
  $personalWindow
  if ($script:windowMode -eq 'new' -and $script:windowReads -gt 2) { $newWindow }
}
function Start-Process {
  param($FilePath,$ArgumentList,$WindowStyle)
  $script:deployLaunches++
}
$targetUrl = 'https://office.excelherbal.in/wp-admin/tools.php?page=eh7-uat-cleanup'
Open-DedicatedChromeWindow $targetUrl 'EH7 UAT Cleanup' | Out-Null
Assert ($script:appWindowHandle -eq 201) 'Deployment must reuse the verified authenticated office WordPress admin HWND.'
Assert ($script:navigatedUrl -eq $targetUrl) 'Reused authenticated admin window must navigate to the requested deployment page.'
Assert ($script:deployLaunches -eq 0) 'An authenticated office WordPress admin window must be reused without launching a new Chrome window.'
Write-Host 'PASS deployment_reuses_verified_authenticated_admin_window'

$script:windowMode = 'precise'
$script:windowReads = 0
$script:deployLaunches = 0
$script:navigatedUrl = ''
$uploadUrl = 'https://office.excelherbal.in/wp-admin/plugin-install.php?tab=upload'
Open-DedicatedChromeWindow $uploadUrl 'Add Plugins|Upload Plugin|office.*WordPress' | Out-Null
Assert ($script:appWindowHandle -eq 211) 'Deployment must choose the single authenticated window whose address exactly matches the requested wp-admin URL.'
Assert ($script:navigatedUrl -eq $uploadUrl) 'Exact authenticated target must still navigate through the verified pinned HWND.'
Assert ($script:deployLaunches -eq 0) 'Exact authenticated target must not launch another Chrome window.'
Write-Host 'PASS deployment_exact_url_disambiguates_multiple_admin_windows'

$script:windowMode = 'new'
$script:windowReads = 0
$script:deployLaunches = 0
$script:navigatedUrl = ''
Open-DedicatedChromeWindow $targetUrl 'EH7 UAT Cleanup' | Out-Null
Assert ($script:appWindowHandle -eq 202) 'Without an authenticated admin window, deployment must select only the newly-created matching HWND.'
Assert ($script:deployLaunches -eq 1) 'Fallback must launch exactly one new Chrome window.'
Write-Host 'PASS deployment_new_window_isolation'

$script:windowMode = 'none'
$script:windowReads = 0
$script:deployLaunches = 0
$failed = $false
try { Open-DedicatedChromeWindow $targetUrl 'EH7 UAT Cleanup' | Out-Null } catch { $failed = $true }
Assert $failed 'Deployment must not adopt an unrelated existing Chrome window when no verified admin window or new target appears.'
Write-Host 'PASS deployment_no_unrelated_fallback'

Add-Type -TypeDefinition @'
public static class UatWindowNative {
  public static bool AllowActivation = true;
  public static System.IntPtr Foreground;
  public static bool ShowWindow(System.IntPtr window, int command) { return true; }
  public static bool SetForegroundWindow(System.IntPtr window) {
    if (AllowActivation) Foreground = window;
    return AllowActivation;
  }
  public static System.IntPtr GetForegroundWindow() { return Foreground; }
}
'@
$activation = $deployAst.Find({ param($node)
  $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Activate-OwnedChromeWindow'
},$true)
. ([scriptblock]::Create($activation.Extent.Text))
[System.Windows.Automation.AutomationElement]::Owner = $process.Id
$script:appWindowHandle = [IntPtr]202
Activate-OwnedChromeWindow $process
Assert ([UatWindowNative]::Foreground -eq 202) 'Activation must use the verified HWND.'
[UatWindowNative]::AllowActivation = $false
[UatWindowNative]::Foreground = [IntPtr]201
$failed = $false
try { Activate-OwnedChromeWindow $process } catch { $failed = $true }
Assert $failed 'Denied foreground activation must fail before any keyboard input.'
Write-Host 'PASS deployment_foreground_activation_fail_closed'
