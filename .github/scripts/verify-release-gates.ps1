param(
    [ValidateSet('ci','production')]
    [string]$Mode = 'ci',
    [string]$GateFile = 'release-gates/v7.4.0.json'
)

$ErrorActionPreference = 'Stop'

function Read-RequiredJsonEvidence {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$GateId
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Gate $GateId is marked passed but evidence file is missing: $Path"
    }
    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        throw "Gate $GateId evidence is not valid JSON: $Path"
    }
}

function Assert-RequiredText {
    param(
        [Parameter(Mandatory=$true)][object]$Value,
        [Parameter(Mandatory=$true)][string]$Message
    )
    if ([string]::IsNullOrWhiteSpace([string]$Value)) { throw $Message }
}

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

$gateRoot = Split-Path -Parent $GateFile
$evidenceRoot = Join-Path $gateRoot 'evidence'

if ([string]$byId['environment_hardening'].status -eq 'passed') {
    $hostEvidence = Read-RequiredJsonEvidence -Path (Join-Path $evidenceRoot 'host-hardening-2026-10-07.json') -GateId 'environment_hardening'
    if ([string]$hostEvidence.status -ne 'passed') {
        throw 'environment_hardening is marked passed but host-hardening evidence status is not passed.'
    }
    if ([string]$hostEvidence.passed.wp_environment_type -ne 'staging') {
        throw 'environment_hardening requires evidence that WP_ENVIRONMENT_TYPE resolves to staging.'
    }
    if ($hostEvidence.passed.disallow_file_edit -ne $true) {
        throw 'environment_hardening requires evidence that DISALLOW_FILE_EDIT is true.'
    }
    foreach ($property in @($hostEvidence.blockers.PSObject.Properties)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            throw ("environment_hardening evidence still contains blocker {0}: {1}" -f $property.Name,$property.Value)
        }
    }
}

if ([string]$byId['business_report_review'].status -eq 'passed') {
    $reportEvidence = Read-RequiredJsonEvidence -Path (Join-Path $evidenceRoot 'business-report-review-2026-10-07.json') -GateId 'business_report_review'
    if ([string]$reportEvidence.status -ne 'passed') {
        throw 'business_report_review is marked passed but report evidence status is not passed.'
    }
    if ([string]$reportEvidence.human_review.status -ne 'passed') {
        throw 'business_report_review requires a passed named Accounts human review.'
    }
    Assert-RequiredText -Value $reportEvidence.human_review.reviewer_name -Message 'business_report_review requires reviewer_name.'
    Assert-RequiredText -Value $reportEvidence.human_review.reviewer_role -Message 'business_report_review requires reviewer_role.'
    Assert-RequiredText -Value $reportEvidence.human_review.reviewed_at -Message 'business_report_review requires reviewed_at.'
}

if ([string]$byId['pilot_signoff'].status -eq 'passed') {
    $signoffEvidence = Read-RequiredJsonEvidence -Path (Join-Path $evidenceRoot 'pilot-signoff-2026-10-07.json') -GateId 'pilot_signoff'
    if ([string]$signoffEvidence.status -ne 'passed') {
        throw 'pilot_signoff is marked passed but sign-off evidence status is not passed.'
    }
    if (@($signoffEvidence.open_gates).Count -gt 0) {
        throw ('pilot_signoff evidence still lists open gates: ' + (@($signoffEvidence.open_gates) -join ', '))
    }
    foreach ($role in @('operational_owner','hr','accounts')) {
        $record = $signoffEvidence.signoffs.$role
        if ($null -eq $record) { throw "pilot_signoff is missing required sign-off role: $role" }
        if ([string]$record.status -ne 'passed') {
            throw "pilot_signoff requires passed status for $role."
        }
        Assert-RequiredText -Value $record.name -Message "pilot_signoff requires a signer name for $role."
        Assert-RequiredText -Value $record.date -Message "pilot_signoff requires a sign-off date for $role."
    }
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
