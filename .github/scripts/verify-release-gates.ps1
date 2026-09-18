param(
    [ValidateSet('ci','production')]
    [string]$Mode = 'ci',
    [string]$GateFile = 'release-gates/v7.4.0.json'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $GateFile -PathType Leaf)) {
    throw "Release gate file not found: $GateFile"
}

$gate = Get-Content -LiteralPath $GateFile -Raw | ConvertFrom-Json
if ([int]$gate.schema_version -ne 1) { throw 'Unsupported release-gate schema version.' }
if ([string]$gate.release_version -ne '7.4.0') { throw 'Release gate file is not for v7.4.0.' }
if ([string]$gate.automated_certification.status -ne 'passed') {
    throw 'Automated certification must be recorded as passed before release-gate evaluation.'
}
if (@($gate.automated_certification.evidence).Count -lt 1) {
    throw 'Automated certification requires at least one evidence reference.'
}

$requiredIds = @(
    'host_backup_restore',
    'environment_hardening',
    'real_http_bearer_401_403',
    'android_physical_gps',
    'hr_multipart_private_document',
    'business_report_review',
    'pilot_signoff'
)
$allowedStatuses = @('pending','blocked','passed')
$byId = @{}
foreach ($item in @($gate.manual_gates)) {
    $id = [string]$item.id
    if ([string]::IsNullOrWhiteSpace($id)) { throw 'Manual release gate has no id.' }
    if ($byId.ContainsKey($id)) { throw "Duplicate manual release gate id: $id" }
    $status = [string]$item.status
    if ($allowedStatuses -notcontains $status) { throw "Invalid status '$status' for gate $id." }
    if ($status -eq 'passed' -and @($item.evidence).Count -lt 1) {
        throw "Gate $id is marked passed without evidence."
    }
    $byId[$id] = $item
}
foreach ($id in $requiredIds) {
    if (-not $byId.ContainsKey($id)) { throw "Required release gate is missing: $id" }
    if ($byId[$id].required -ne $true) { throw "Required release gate is not marked required: $id" }
}

$open = @($requiredIds | Where-Object { [string]$byId[$_].status -ne 'passed' })

if ($gate.production_approved -eq $true) {
    if ($open.Count -gt 0) {
        throw ('production_approved=true while required gates remain open: ' + ($open -join ', '))
    }
    if ([string]::IsNullOrWhiteSpace([string]$gate.approval.approved_by) -or
        [string]::IsNullOrWhiteSpace([string]$gate.approval.approved_at) -or
        [string]::IsNullOrWhiteSpace([string]$gate.approval.change_ticket)) {
        throw 'Production approval requires approved_by, approved_at and change_ticket.'
    }
}

if ($Mode -eq 'production') {
    if ($gate.production_approved -ne $true) {
        throw ('Production release is BLOCKED. Open gates: ' + ($open -join ', '))
    }
    if ($open.Count -gt 0) {
        throw ('Production release is BLOCKED. Open gates: ' + ($open -join ', '))
    }
    Write-Host 'PASS production_release_gates'
    Write-Host ('Approval: ' + [string]$gate.approval.approved_by + ' / ' + [string]$gate.approval.change_ticket)
    exit 0
}

if ($gate.production_approved -eq $true) {
    Write-Host 'PASS release_gate_policy production-approved evidence is internally consistent'
} else {
    Write-Host 'PASS release_gate_policy fail-closed'
    Write-Host ('INFO production_release_blocked_by=' + ($open -join ','))
}
