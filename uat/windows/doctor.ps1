#requires -Version 5.1
<#
Read-only, free local ERP developer environment report.
No installers, no administrative changes, no secrets, no network requests.
#>
param(
    [string]$Workspace = 'D:\ERP7-Development',
    [string]$XamppRoot = 'D:\xampp',
    [string]$FlutterRoot = 'D:\tools\flutter',
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
function Check-Tool([string]$Name, [string]$PreferredPath) {
    if ($PreferredPath -and (Test-Path -LiteralPath $PreferredPath)) {
        return [ordered]@{ ready = $true; path = $PreferredPath }
    }
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    return [ordered]@{ ready = [bool]$cmd; path = $(if ($cmd) { $cmd.Source } else { $null }) }
}
function Drive-Space([string]$Letter) {
    $drive = Get-PSDrive -Name $Letter -PSProvider FileSystem -ErrorAction SilentlyContinue
    if (!$drive) { return $null }
    return [math]::Round($drive.Free / 1GB, 1)
}
$git = Check-Tool 'git' $null
$node = Check-Tool 'node' $null
$php = Check-Tool 'php' (Join-Path $XamppRoot 'php\php.exe')
$mysql = Check-Tool 'mysql' (Join-Path $XamppRoot 'mysql\bin\mysql.exe')
$flutter = Check-Tool 'flutter' (Join-Path $FlutterRoot 'bin\flutter.bat')
$adb = Check-Tool 'adb' "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$wp = Test-Path -LiteralPath (Join-Path $XamppRoot 'htdocs\erp-uat\wp-load.php')
$project = Test-Path -LiteralPath (Join-Path $Workspace '.git')
$branchName = $null
$dirty = $null
if ($git.ready -and $project) {
    $branchName = (& $git.path -C $Workspace branch --show-current | Select-Object -First 1)
    $dirty = [bool]((& $git.path -C $Workspace status --porcelain) | Select-Object -First 1)
}
$system = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$out = [ordered]@{
    report = 'Excel Herbal ERP V7 - Local Developer Readiness'
    computer = $env:COMPUTERNAME
    memoryGB = [math]::Round($system.TotalPhysicalMemory / 1GB, 1)
    cpu = $cpu.Name
    virtualizationEnabled = [bool]$cpu.VirtualizationFirmwareEnabled
    driveFreeGB = [ordered]@{ C = Drive-Space C; D = Drive-Space D; E = Drive-Space E }
    workspace = [ordered]@{ path = $Workspace; present = $project; branch = $branchName; uncommittedChanges = $dirty }
    tools = [ordered]@{ git = $git; node = $node; php = $php; mysql = $mysql; flutter = $flutter; androidDeviceBridge = $adb }
    wordpressLocalInstalled = $wp
    safeLocalUrl = 'http://127.0.0.1:18880/erp-uat'
    backendTestsReady = $project -and $php.ready -and $git.ready
    frontendTestsReady = $project -and $flutter.ready
    fullLocalUatReady = $project -and $php.ready -and $mysql.ready -and $wp
}
if ($Json) { $out | ConvertTo-Json -Depth 7; return }
Write-Host '=== Excel Herbal ERP V7 | Free Local Setup Doctor ===' -ForegroundColor Cyan
Write-Host ('Computer: ' + $out.computer + ' | RAM: ' + $out.memoryGB + ' GB')
Write-Host ('Drive free: C={0} GB, D={1} GB, E={2} GB' -f $out.driveFreeGB.C,$out.driveFreeGB.D,$out.driveFreeGB.E)
Write-Host ('Virtualization in BIOS: ' + $out.virtualizationEnabled + ' (not required by Windows-native XAMPP)')
Write-Host ('Workspace: ' + $Workspace + ' | Present: ' + $project + ' | Branch: ' + $branchName)
foreach($name in $out.tools.Keys) {
    $tool = $out.tools[$name]
    Write-Host ('{0}: {1}' -f $name,$(if ($tool.ready) {'READY'} else {'NOT INSTALLED'}))
}
Write-Host ('WordPress localhost installed: ' + $wp)
Write-Host ('Backend testing ready: {0} | Flutter testing ready: {1} | Interactive UAT ready: {2}' -f $out.backendTestsReady,$out.frontendTestsReady,$out.fullLocalUatReady)
if ($out.driveFreeGB.C -lt 10) { Write-Warning 'C: has less than 10 GB free. Install future tooling and caches on D:, without deleting personal files.' }
if (!$php.ready -or !$mysql.ready) { Write-Host 'NEXT: Download official XAMPP for Windows and install under D:\xampp. Keep Apache and MariaDB localhost-only.' -ForegroundColor Yellow }
if (!$flutter.ready) { Write-Host 'NEXT: Install the free Flutter SDK in D:\tools\flutter (do not install SDK on C:).' -ForegroundColor Yellow }
if (!$wp) { Write-Host 'NEXT: Create isolated synthetic WordPress on D: after the native stack is available. Never import live data.' -ForegroundColor Yellow }
Write-Host 'To run fast available tests: powershell -ExecutionPolicy Bypass -File .\uat\windows\run-tests.ps1'
