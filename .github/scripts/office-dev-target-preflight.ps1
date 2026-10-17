param(
  [Parameter(Mandatory=$true)][string]$CandidateHead,
  [string]$Site = 'https://office.excelherbal.in',
  [string]$ExpectedInstalledHead = 'd599c8d78127b566204e2a1b37f5e2790614d0a4',
  [string]$EvidencePath = 'dist/office-dev-preflight/EVIDENCE.json'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$evidence = [ordered]@{
  schema_version=1
  gate='office_in_place_dev_read_only_preflight'
  target='office.excelherbal.in'
  expected_installed_head=$ExpectedInstalledHead
  candidate_head=$CandidateHead
  checked_at_utc=[DateTime]::UtcNow.ToString('o')
  tests=[ordered]@{}
  data_reset_performed=$false
  session_revocation_performed=$false
  site_mutation_performed=$false
  production_approval=$false
  actual_site_database_backup_verified=$false
  status='pending'
}
$client=$null
try {
  $uri=[Uri]$Site
  if($uri.Scheme -ne 'https' -or $uri.Host -ine 'office.excelherbal.in' -or $uri.AbsolutePath.Trim('/') -ne ''){
    throw 'Only the current office.excelherbal.in HTTPS development site may be checked.'
  }
  if($CandidateHead -notmatch '^[a-f0-9]{40}$' -or $ExpectedInstalledHead -notmatch '^[a-f0-9]{40}$'){
    throw 'Both expected source heads must be exact 40-character commit hashes.'
  }
  if ($env:GITHUB_EVENT_NAME -eq 'pull_request' -and $env:GITHUB_HEAD_REF -ne 'codex/erp-step1-integrated-uat-20261017') {
    throw 'Unexpected PR branch; refusing Office target attestation.'
  }
  $actualCheckout=(& git rev-parse HEAD).Trim()
  if($LASTEXITCODE -ne 0 -or $actualCheckout -ne $CandidateHead){throw 'Checkout does not match intended PR head.'}
  $evidence.tests['candidate_exact_head']='passed'
  $client=[System.Net.Http.HttpClient]::new()
  $client.Timeout=[TimeSpan]::FromSeconds(25)
  $root=$Site.TrimEnd('/')+'/wp-json/excel-herbal-erp/v7'
  $healthResponse=$client.GetAsync($root+'/health').GetAwaiter().GetResult()
  try {
    if([int]$healthResponse.StatusCode -ne 200){throw 'ERP health endpoint did not return HTTP 200.'}
    $healthText=$healthResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    $health=$healthText | ConvertFrom-Json
  } finally {$healthResponse.Dispose()}
  if(-not $health.ok -or -not $health.data){throw 'ERP health payload invalid.'}
  $h=$health.data
  if([string]$h.environment -ne 'staging'){throw 'Office development environment must report staging.'}
  $evidence.tests['office_development_environment']='passed'
  if([string]$h.source_head -ne $ExpectedInstalledHead){
    throw ('Unexpected current backend source commit: '+[string]$h.source_head)
  }
  $evidence.tests['unchanged_original_backend']='passed'
  if([string]$h.host_hardening.status -ne 'passed' -or $h.host_hardening.disallow_file_edit -ne $true){
    throw 'WordPress host hardening failed.'
  }
  $evidence.tests['host_hardening']='passed'
  if(-not $h.schema_installed -or -not $h.web_runtime.present){throw 'Installed ERP schema or web runtime is missing.'}
  $evidence.tests['installed_erp_operational']='passed'
  $contractResp=$client.GetAsync($root+'/app/capabilities').GetAwaiter().GetResult()
  try {
    if([int]$contractResp.StatusCode -ne 200){throw 'ERP contract endpoint returned non-200.'}
    $contract=$contractResp.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
  } finally {$contractResp.Dispose()}
  if(-not $contract.ok -or [string]$contract.data.contract_version -ne [string]$h.api_contract){
    throw 'ERP health and capabilities contracts disagree.'
  }
  $evidence.tests['api_contract_consistency']='passed'
  $evidence.installed_backend_head=[string]$h.source_head
  $evidence.installed_web_head=[string]$h.web_runtime.source_head
  $evidence.installed_erp_version=[string]$h.version
  $evidence.host_environment=[string]$h.environment
  $evidence.active_mobile_sessions_exist=($h.staging_safety.active_mobile_sessions_zero -ne $true)
  $evidence.synthetic_only_uat=($h.uat_bootstrap.synthetic_only -eq $true)
  $evidence.release_note='PASS is read-only site identity/contract verification only. Candidate not deployed. No backup of existing Office database/files verified. Do not deploy without snapshot and rollback proof.'
  $evidence.status='passed_read_only'
  Write-Output ('PASS office_dev_read_only_preflight candidate='+$CandidateHead+' installed='+$h.source_head)
} catch {
  $evidence.status='failed'
  $evidence.failure=[string]$_.Exception.Message
  throw
} finally {
  if($client){$client.Dispose()}
  $parent=Split-Path -Parent $EvidencePath
  if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
  $evidence|ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
}
