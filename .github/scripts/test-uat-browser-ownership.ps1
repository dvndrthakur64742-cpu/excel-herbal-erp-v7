# Behavioral tests with fake browser/UIA boundaries: no browser, network or ERP data.
$ErrorActionPreference = 'Stop'
$tokens = $null
$parseErrors = $null
$source = Join-Path $PSScriptRoot 'uat-runtime-screen-smoke.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw 'UAT smoke script did not parse.' }
foreach ($name in @('Open-AppWindow','Root')) {
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
