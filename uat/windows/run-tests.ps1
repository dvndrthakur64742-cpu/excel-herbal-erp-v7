#requires -Version 5.1
<#
Developer-friendly quick checks. Everything runs locally, no paid hosting.
Never contacts the production WordPress API; does not mutate the DB.
Full WordPress/MariaDB integration remains in GitHub Actions CI.
#>
param(
    [ValidateSet('quick','backend','flutter','all')]
    [string]$Mode = 'quick',
    [string]$Workspace = 'D:\ERP7-Development',
    [string]$XamppRoot = 'D:\xampp',
    [string]$FlutterRoot = 'D:\tools\flutter'
)
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath (Join-Path $Workspace '.git'))) {
    throw "Workspace not found: $Workspace. Clone the approved GitHub branch to D: first."
}
function Executable([string]$cmd,[string]$preferred) {
    if ($preferred -and (Test-Path -LiteralPath $preferred)) { return $preferred }
    $c = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($c) {return $c.Source}
    return $null
}
$node = Executable 'node' $null
$php = Executable 'php' (Join-Path $XamppRoot 'php\php.exe')
$flutter = Executable 'flutter' (Join-Path $FlutterRoot 'bin\flutter.bat')
$errors = 0
function Execute-Test([string]$label,[scriptblock]$call) {
    Write-Host ("==> " + $label) -ForegroundColor Cyan
    try {
        & $call
        if ($LASTEXITCODE -ne 0) { throw "Process exited with code $LASTEXITCODE" }
        Write-Host ("PASS " + $label) -ForegroundColor Green
    } catch {
        Write-Warning ("FAIL " + $label + ": " + $_.Exception.Message)
        $script:errors++
    }
}
if ($Mode -in @('quick','all','backend')) {
    if (!$node) { throw 'Node.js is required; install it or add it to PATH.' }
    Execute-Test 'Railway / local-UAT safety contracts' { & $node --test (Join-Path $Workspace 'uat\railway\recovery-preflight.test.mjs') }
    Execute-Test 'Local synthetic ERP true-source pin contracts' { & $node --test (Join-Path $Workspace 'uat\windows\source-pin-guard.test.mjs') }
    Execute-Test 'Professional UI/UX lazy loaders and genuine retry' { & $node (Join-Path $Workspace 'flutter-app\tool\verify_async_panel_loaders.cjs') }
    if ($php) {
        Execute-Test 'WordPress dbDelta SQL definition formatting' { & $php (Join-Path $Workspace 'plugin\excel-herbal-erp-v7\tests\dbdelta_schema_format_contract.php') }
        Execute-Test 'PHP syntax for the ERP backend' {
            $files = @(Get-ChildItem (Join-Path $Workspace 'plugin\excel-herbal-erp-v7') -Filter '*.php' -Recurse -File)
            if (!$files.Count) { throw 'No ERP PHP files found.' }
            foreach ($file in $files) {
                & $php -l $file.FullName 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { throw ('PHP parse error: ' + $file.FullName) }
            }
            Write-Host ("Syntax checked {0} ERP PHP files" -f $files.Count)
        }
    } else {
        Write-Warning 'PHP syntax checks skipped: install free Windows-native PHP/XAMPP under D:\xampp'
        if ($Mode -in @('backend','all')) { $errors++ }
    }
}
if ($Mode -in @('flutter','all')) {
    if (!$flutter) {
        Write-Warning 'Flutter checks skipped: Flutter SDK not installed on D:'
        $errors++
    } else {
        Push-Location (Join-Path $Workspace 'flutter-app')
        try {
            Execute-Test 'Flutter package restore' { & $flutter pub get }
            if ($errors -eq 0) {
                Execute-Test 'Flutter static analysis' { & $flutter analyze --no-pub }
                Execute-Test 'Flutter unit and widget tests' { & $flutter test --no-pub }
            }
        } finally { Pop-Location }
    }
}
Write-Host ('Completed local ' + $Mode + ' checks. Failure count: ' + $errors)
if ($errors -gt 0) { exit 1 }
