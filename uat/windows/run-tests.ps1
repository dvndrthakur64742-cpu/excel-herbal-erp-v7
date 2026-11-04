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
    Execute-Test 'Disposable live-shaped synthetic upgrade fixture contracts' { & $node --test (Join-Path $Workspace 'uat\railway\ci-live-shaped-fixture.test.mjs') }
    Execute-Test 'Local synthetic ERP true-source pin contracts' { & $node --test (Join-Path $Workspace 'uat\windows\source-pin-guard.test.mjs') }
    Execute-Test 'Windows localhost synthetic backup safety contracts' { & $node --test (Join-Path $Workspace 'uat\windows\backup-native-uat.test.mjs') }
    Execute-Test 'Isolated MariaDB restore rehearsal contracts' { & $node --test (Join-Path $Workspace 'uat\windows\restore-native-uat.test.mjs') }
    Execute-Test 'Local candidate WordPress source/identity isolation contracts' { & $node --test (Join-Path $Workspace 'uat\windows\candidate-uat.test.mjs') }
    Execute-Test 'Candidate Cash/UPI transaction and clock safety contracts' { & $node --test (Join-Path $Workspace 'uat\windows\candidate-transaction-contract.test.mjs') }
    Execute-Test 'Candidate real-date GPS, stock custody and evening settlement safety contracts' { & $node --test (Join-Path $Workspace 'uat\windows\candidate-field-contract.test.mjs') }
    Execute-Test 'Live ERP deployment fail-closed safety contracts' { & $node --test (Join-Path $Workspace 'uat\release\live-deployment-gate.test.mjs') }
    Execute-Test 'Plugin review metadata and responsive UX source contracts' { & $node --test (Join-Path $Workspace 'uat\release\release-metadata-ux.test.mjs') }
    Execute-Test 'Live 83/85 table non-destructive migration inventory contracts' { & $node --test (Join-Path $Workspace 'uat\release\schema-migration-inventory.test.mjs') }
    Execute-Test 'Local hosted backup package safety and synthetic corruption checks' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Workspace 'uat\release\hosted-backup-preflight.test.ps1')
    }
    Execute-Test 'WordPress REST bearer authentication live-session parity' {
        if (!$php) { throw 'PHP 8.3 required for WordPress authentication parity' }
        & $php (Join-Path $Workspace 'plugin\excel-herbal-erp-v7\tests\mobile_rest_authentication.php')
    }
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
        Execute-Test 'Candidate and original read-only UAT CLI PHP syntax' {
            foreach ($name in @('candidate-sales-preflight.php','candidate-prepaid-transactions.php','candidate-sales-audit.php','original-uat-readonly.php')) {
                $file = Join-Path $Workspace ('uat\windows\'+$name)
                & $php -l $file 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { throw ('Candidate test parse error: '+$file) }
            }
            Write-Host 'Syntax checked 4 isolated candidate/readonly CLI PHP scripts'
            foreach ($name in @('candidate-field-current-day.php','candidate-field-issue-receive.php','candidate-field-evening.php','candidate-field-audit.php','candidate-field-status.php')) {
                $file = Join-Path $Workspace ('uat\windows\'+$name)
                & $php -l $file 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { throw ('Candidate field test parse error: '+$file) }
            }
            Write-Host 'Syntax checked 5 candidate field-work CLI PHP scripts'
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
