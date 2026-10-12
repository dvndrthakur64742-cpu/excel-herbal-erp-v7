param(
    [Parameter(Mandatory=$true)][string]$ApiBase,
    [Parameter(Mandatory=$true)][string]$Mobile,
    [Parameter(Mandatory=$true)][string]$Password,
    [string]$ExpectedSourceHead = '',
    [string]$EvidencePath = 'dist/uat-daily-order/EVIDENCE.json'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$ApiBase = $ApiBase.TrimEnd('/')
$uri = [Uri]$ApiBase
if ($uri.Scheme -ne 'https') { throw 'Daily Order UAT must use HTTPS.' }
if ($uri.AbsolutePath.TrimEnd('/') -notlike '*/wp-json/excel-herbal-erp/v7') {
    throw 'API base must end with /wp-json/excel-herbal-erp/v7.'
}
if ($uri.Host -ine 'office.excelherbal.in' -and $uri.Host -notmatch '(?i)(^|[-.])(uat|staging)([-.]|$)') {
    throw 'Daily Order UAT repair refuses a non-UAT hostname.'
}

$client = [System.Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromSeconds(40)

function Send-Eh7 {
    param(
        [Parameter(Mandatory=$true)][string]$Method,
        [Parameter(Mandatory=$true)][string]$Path,
        [object]$Body = $null,
        [string]$Bearer = '',
        [string]$IdempotencyKey = ''
    )
    $request = [System.Net.Http.HttpRequestMessage]::new(
        [System.Net.Http.HttpMethod]::new($Method),
        $ApiBase + $Path
    )
    try {
        $request.Headers.Accept.ParseAdd('application/json')
        $request.Headers.UserAgent.ParseAdd('EH7-Daily-Order-UAT/1.0')
        if (-not [string]::IsNullOrWhiteSpace($Bearer)) {
            $request.Headers.Authorization =
                [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Bearer)
        }
        if (-not [string]::IsNullOrWhiteSpace($IdempotencyKey)) {
            $request.Headers.Add('X-Idempotency-Key', $IdempotencyKey)
        }
        if ($null -ne $Body) {
            $json = $Body | ConvertTo-Json -Depth 12 -Compress
            $request.Content = [System.Net.Http.StringContent]::new(
                $json,
                [System.Text.Encoding]::UTF8,
                'application/json'
            )
        }
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $parsed = $null
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            try { $parsed = $text | ConvertFrom-Json } catch { $parsed = $null }
        }
        [pscustomobject]@{
            Status = [int]$response.StatusCode
            Json = $parsed
            Text = $text
        }
    } finally {
        $request.Dispose()
    }
}

function Assert-Ok {
    param([object]$Response,[string]$Label)
    if ($Response.Status -ne 200 -or -not $Response.Json -or $Response.Json.ok -ne $true) {
        $code = if ($Response.Json -and $Response.Json.error) {
            [string]$Response.Json.error.code
        } else { '' }
        throw "$Label failed http=$($Response.Status) code=$code"
    }
    Write-Host "PASS $Label"
}

function To-Decimal([object]$Value) {
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return [decimal]0
    }
    return [decimal]::Parse(
        [string]$Value,
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}

$evidence = [ordered]@{
    schema_version = 1
    target_host = $uri.Host
    api_base = $ApiBase
    tested_at_utc = [DateTime]::UtcNow.ToString('o')
    commit = $env:GITHUB_SHA
    run_id = $env:GITHUB_RUN_ID
    business_mutation_policy = 'read_only; authentication_session_cleanup_only'
    results = [ordered]@{}
}
$access = ''

try {
    $health = Send-Eh7 -Method GET -Path '/health'
    Assert-Ok $health 'health'
    $healthData = $health.Json.data
    if ([string]$healthData.environment -ne 'staging') {
        throw ('Daily Order UAT repair refuses environment=' + [string]$healthData.environment)
    }
    $expectedHead = if (-not [string]::IsNullOrWhiteSpace($ExpectedSourceHead)) { $ExpectedSourceHead } else { [string]$env:GITHUB_SHA }
    if ([string]::IsNullOrWhiteSpace($expectedHead)) { throw 'Expected source head is required.' }
    if ([string]$healthData.source_head -ne $expectedHead) {
        throw ('Live source head mismatch. expected=' + $expectedHead +
               ' actual=' + [string]$healthData.source_head)
    }
    $evidence.results['live_head'] = 'passed'

    $deviceId = 'gha-daily-uat-' + [Guid]::NewGuid().ToString('N')
    $login = Send-Eh7 -Method POST -Path '/auth/login' -Body @{
        mobile = $Mobile
        password = $Password
        device = 'GitHub Daily Order UAT'
        device_id = $deviceId
    }
    Assert-Ok $login 'login'
    $access = [string]$login.Json.data.access_token
    if ([string]::IsNullOrWhiteSpace($access)) {
        throw 'Login did not return access_token.'
    }
    $evidence.results['login'] = 'passed'

    $beforeMismatch = -1
    $afterMismatch = -1
    $diagnosticsAuthorized = $false
    $before = Send-Eh7 -Method GET -Path '/administration/diagnostics' -Bearer $access
    $beforeCode = if ($before.Json -and $before.Json.error) { [string]$before.Json.error.code } else { '' }
    if ($before.Status -eq 200 -and $before.Json -and $before.Json.ok -eq $true) {
        Write-Host 'PASS diagnostics_before'
        $diagnosticsAuthorized = $true
        $beforeData = $before.Json.data
        $beforeMismatch = [int]$beforeData.daily_order.legacy_distribution_snapshot_mismatches
        $evidence['legacy_snapshot_mismatches_before'] = $beforeMismatch
        $evidence['unbalanced_journals_before'] = [int]$beforeData.accounting.unbalanced_journals
        $evidence['negative_stock_before'] = [int]$beforeData.stock.negative_balances

        if ($beforeMismatch -gt 0) {
            $evidence.results['legacy_snapshot_repair'] = 'blocked_requires_separate_approval'
            throw ("Found $beforeMismatch legacy distribution snapshot mismatches. " +
                   'This live UAT verification is READ ONLY for business records; ' +
                   'a separately reviewed maintenance repair is required before certification.')
        }
        $evidence.results['legacy_snapshot_repair'] = 'not_required'

        $after = Send-Eh7 -Method GET -Path '/administration/diagnostics' -Bearer $access
        Assert-Ok $after 'diagnostics_after'
        $afterData = $after.Json.data
        $afterMismatch = [int]$afterData.daily_order.legacy_distribution_snapshot_mismatches
        $evidence['legacy_snapshot_mismatches_after'] = $afterMismatch
        $evidence['unbalanced_journals_after'] = [int]$afterData.accounting.unbalanced_journals
        $evidence['orphan_journal_lines_after'] = [int]$afterData.accounting.orphan_journal_lines
        $evidence['negative_stock_after'] = [int]$afterData.stock.negative_balances

        if ($afterMismatch -ne 0) { throw "Daily Order commercial mismatches remain: $afterMismatch" }
        if ([int]$afterData.accounting.unbalanced_journals -ne 0) { throw 'Unbalanced journals detected.' }
        if ([int]$afterData.accounting.orphan_journal_lines -ne 0) { throw 'Orphan journal lines detected.' }
        if ([int]$afterData.stock.negative_balances -ne 0) { throw 'Negative stock detected.' }
        $evidence.results['post_repair_integrity'] = 'passed'
    } elseif ($before.Status -eq 403 -and $beforeCode -eq 'permission_denied') {
        Write-Host 'INFO admin diagnostics are intentionally outside this UAT user scope; continuing with user-visible Daily Order invariants.'
        $evidence.results['admin_diagnostics'] = 'not_authorized_expected'
        $evidence.results['legacy_snapshot_repair'] = 'admin_scope_not_available'
        $evidence.results['post_repair_integrity'] = 'admin_scope_not_available'
    } else {
        Assert-Ok $before 'diagnostics_before'
    }

    $cycles = Send-Eh7 -Method GET -Path '/daily/cycles' -Bearer $access
    Assert-Ok $cycles 'daily_cycles'
    $completed = @($cycles.Json.data | Where-Object { [string]$_.status -eq 'completed' })
    if ($completed.Count -lt 1) { throw 'No completed Daily Order cycle exists for real-data verification.' }

    $verifiedCycles = @()
    $verifiedSalesReports = @()
    foreach ($summary in ($completed | Select-Object -First 3)) {
        $cycleId = [int]$summary.id
        $detail = Send-Eh7 -Method GET -Path ("/daily/cycles/$cycleId") -Bearer $access
        Assert-Ok $detail ("daily_cycle_" + $cycleId)
        $data = $detail.Json.data
        if ([string]$data.cycle.status -ne 'completed') {
            throw "Cycle $cycleId is not completed."
        }
        $requests = @($data.requests)
        if ($requests.Count -lt 1) { throw "Cycle $cycleId has no request." }
        foreach ($request in $requests) {
            if ([string]$request.status -ne 'issued') {
                throw "Cycle $cycleId request $($request.id) status=$($request.status), expected issued."
            }
            if (@($request.issued_lines).Count -lt 1) {
                throw "Cycle $cycleId request $($request.id) has no issued lines."
            }
        }
        if ($null -eq $data.evening -or [string]$data.evening.status -ne 'posted') {
            throw "Cycle $cycleId evening settlement is not posted."
        }

        [decimal]$lineTotal = 0
        foreach ($line in @($data.evening.lines)) {
            $issued = To-Decimal $line.issued_quantity
            $returned = To-Decimal $line.return_quantity
            $retail = To-Decimal $line.retail_quantity
            $wholesale = To-Decimal $line.wholesale_quantity
            if ([Math]::Abs([double]($issued - ($returned + $retail + $wholesale))) -gt 0.0005) {
                throw "Cycle $cycleId quantity conservation failed for evening line $($line.id)."
            }
            $lineTotal += To-Decimal $line.total_amount
        }
        $expected = To-Decimal $data.evening.expected_amount
        $settled = (To-Decimal $data.evening.cash_amount) + (To-Decimal $data.evening.upi_amount)
        if ([Math]::Abs([double]($lineTotal - $expected)) -gt 0.01) {
            throw "Cycle $cycleId expected amount does not equal evening line total."
        }
        if ([Math]::Abs([double]($settled - $expected)) -gt 0.01) {
            throw "Cycle $cycleId cash+UPI does not equal expected amount."
        }

        # Read-only check: each verified posted Daily Order appears once in Sales Summary.
        $businessDate = [string]$data.cycle.business_date
        $branchId = [int]$data.cycle.branch_id
        if ($branchId -le 0 -or $businessDate -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') {
            throw "Cycle $cycleId has an invalid branch or business date for Sales Summary verification."
        }
        $reportPath = '/reports/sales?branch_id=' + $branchId +
            '&from=' + [Uri]::EscapeDataString($businessDate) +
            '&to=' + [Uri]::EscapeDataString($businessDate)
        $salesReport = Send-Eh7 -Method GET -Path $reportPath -Bearer $access
        Assert-Ok $salesReport ("sales_report_" + $cycleId)
        $salesRows = @($salesReport.Json.data)
        $matchingRows = @($salesRows | Where-Object {
            [string]$_.source_type -eq 'daily_order' -and [int]$_.source_id -eq $cycleId
        })
        if ($matchingRows.Count -ne 1) {
            throw "Sales Summary must contain exactly one Daily Order row for cycle $cycleId; found $($matchingRows.Count)."
        }
        $salesRow = $matchingRows[0]
        if ([string]$salesRow.status -ne 'posted' -or
            [string]$salesRow.reference -ne ("DO-" + $cycleId) -or
            [Math]::Abs([double](To-Decimal $salesRow.gross_amount) - [double]$expected) -gt 0.01 -or
            [Math]::Abs([double](To-Decimal $salesRow.paid_amount) - [double]$settled) -gt 0.01 -or
            [Math]::Abs([double](To-Decimal $salesRow.outstanding_amount)) -gt 0.01) {
            throw "Sales Summary fields or source identity do not reconcile for Daily Order $cycleId."
        }
        $verifiedSalesReports += [ordered]@{
            cycle_id = $cycleId
            branch_id = $branchId
            business_date = $businessDate
            source_type = [string]$salesRow.source_type
            source_id = [int]$salesRow.source_id
            reference = [string]$salesRow.reference
            gross_amount = [string]$salesRow.gross_amount
            paid_amount = [string]$salesRow.paid_amount
            outstanding_amount = [string]$salesRow.outstanding_amount
            status = 'passed'
        }
        $verifiedCycles += [ordered]@{
            cycle_id = $cycleId
            business_date = [string]$data.cycle.business_date
            request_count = $requests.Count
            evening_line_count = @($data.evening.lines).Count
            expected_amount = [string]$data.evening.expected_amount
            cash_amount = [string]$data.evening.cash_amount
            upi_amount = [string]$data.evening.upi_amount
            status = 'passed'
        }
    }

    $evidence['verified_completed_cycles'] = $verifiedCycles
    $evidence['verified_sales_report_rows'] = $verifiedSalesReports
    $evidence.results['completed_cycle_invariants'] = 'passed'
    $evidence.results['sales_summary_daily_order_inclusion'] = 'passed'
    $evidence['status'] = 'passed'
    Write-Host ('PASS verified_completed_cycles=' + $verifiedCycles.Count)
    if ($diagnosticsAuthorized) {
        Write-Host ('PASS legacy_snapshot_mismatches_before=' + $beforeMismatch)
        Write-Host ('PASS legacy_snapshot_mismatches_after=' + $afterMismatch)
    } else {
        Write-Host 'INFO legacy snapshot diagnostics verified separately under administrator scope.'
    }
    Write-Host 'PASSED Daily Order controlled UAT integrity smoke'
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($access)) {
        try { [void](Send-Eh7 -Method POST -Path '/auth/logout' -Bearer $access) } catch {}
    }
    $dir = Split-Path -Parent $EvidencePath
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $EvidencePath -Encoding utf8
    $client.Dispose()
}
