# Behavioral tests with fake browser/UIA boundaries: no browser, network or ERP data.
$ErrorActionPreference = 'Stop'
$tokens = $null
$parseErrors = $null
$source = Join-Path $PSScriptRoot 'uat-runtime-screen-smoke.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw 'UAT smoke script did not parse.' }
foreach ($name in @('Open-AppWindow','Root','Wait-ForFreshLogin')) {
  $definition = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
  },$true)
  if (-not $definition) { throw ('Missing function: ' + $name) }
  . ([scriptblock]::Create($definition.Extent.Text))
}

function Assert($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Get-ChromeExe { return 'fake-chrome.exe' }
function Start-Sleep { param($Milliseconds) }
function Get-Process { throw 'Must not enumerate or adopt personal Chrome processes.' }
function Start-Process {
  param($FilePath,$ArgumentList,[switch]$PassThru,$WindowStyle)
  $script:launchArguments = $ArgumentList
  return $script:fakeBrowser
}
$script:fakeBrowser = [pscustomobject]@{ HasExited = $false; MainWindowHandle = [IntPtr]101 }
$script:fakeBrowser | Add-Member ScriptMethod Refresh {}
$launched = Open-AppWindow 'https://office.excelherbal.in/wp-content/uploads/eh7-flutter-web/' 'C:\Temp\profile with spaces'
Assert ([object]::ReferenceEquals($launched,$script:fakeBrowser)) 'Must return only the launched browser.'
Assert ($script:appWindowHandle -eq 101) 'Must capture the owned window.'
Assert ($script:launchArguments -contains '--user-data-dir="C:\Temp\profile with spaces"') 'Profile path must be quoted.'
Assert ($script:launchArguments -contains '--app=https://office.excelherbal.in/wp-content/uploads/eh7-flutter-web/') 'App window must use the requested UAT URL.'
Write-Host 'PASS isolated_browser_launch'

$script:fakeBrowser.HasExited = $true
$failed = $false
try { Open-AppWindow 'https://office.excelherbal.in/' 'C:\Temp\test' | Out-Null } catch { $failed = $true }
Assert $failed 'An exited launch must fail instead of adopting an existing browser.'
$script:fakeBrowser.HasExited = $false
$script:fakeBrowser.MainWindowHandle = [IntPtr]::Zero
$failed = $false
try { Open-AppWindow 'https://office.excelherbal.in/' 'C:\Temp\test' | Out-Null } catch { $failed = $true }
Assert $failed 'A launch without a window must fail instead of adopting an existing browser.'
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
foreach ($name in @('Open-DedicatedChromeWindow','Root')) {
  $definition = $deployAst.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
  },$true)
  . ([scriptblock]::Create($definition.Extent.Text))
}
function Get-Process { param($Id,$ErrorAction) return $process }
function Activate-OwnedChromeWindow { param($Process) $script:focusedHandle = $script:appWindowHandle }
$oldWindow = [pscustomobject]@{ Current = [pscustomobject]@{ NativeWindowHandle = 201; ProcessId = $process.Id; Name = 'EH7 UAT Cleanup - Chrome' } }
$newWindow = [pscustomobject]@{ Current = [pscustomobject]@{ NativeWindowHandle = 202; ProcessId = $process.Id; Name = 'EH7 UAT Cleanup - Chrome' } }
$newWindow | Add-Member ScriptMethod SetFocus { $script:focusedHandle = $this.Current.NativeWindowHandle }
$script:windowReads = 0
$script:showNewWindow = $true
function Get-ChromeWindows {
  $script:windowReads++
  $oldWindow
  if ($script:windowReads -gt 1 -and $script:showNewWindow) { $newWindow }
}
Open-DedicatedChromeWindow 'https://office.excelherbal.in/wp-admin/tools.php?page=eh7-uat-cleanup' 'EH7 UAT Cleanup' | Out-Null
Assert ($script:appWindowHandle -eq 202) 'Deployment must select the new HWND even when the old window shares its process and title.'
Assert ($script:focusedHandle -eq 202) 'Deployment must focus the chosen window, not activate an arbitrary process window.'
[System.Windows.Automation.AutomationElement]::Owner = $process.Id
Root $process | Out-Null
Assert ([System.Windows.Automation.AutomationElement]::ObservedHandle -eq 202) 'Deployment reads must remain pinned to the new window.'
$script:windowReads = 0
$script:showNewWindow = $false
$failed = $false
try { Open-DedicatedChromeWindow 'https://office.excelherbal.in/' 'EH7 UAT Cleanup' | Out-Null } catch { $failed = $true }
Assert $failed 'Deployment must not fall back to an existing matching window.'
Write-Host 'PASS deployment_shared_process_window_isolation'

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
$script:appWindowHandle = [IntPtr]202
Activate-OwnedChromeWindow $process
Assert ([UatWindowNative]::Foreground -eq 202) 'Activation must use the verified HWND.'
[UatWindowNative]::AllowActivation = $false
[UatWindowNative]::Foreground = [IntPtr]201
$failed = $false
try { Activate-OwnedChromeWindow $process } catch { $failed = $true }
Assert $failed 'Denied foreground activation must fail before any keyboard input.'
Write-Host 'PASS deployment_foreground_activation_fail_closed'
