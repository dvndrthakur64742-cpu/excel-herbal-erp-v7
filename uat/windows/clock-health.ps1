#requires -Version 5.1
<#
Read-only Windows local-clock integrity diagnostic. Compares UTC system clock to
the Date header from a public HTTPS endpoint before date-sensitive ERP UAT.
Does NOT start Windows Time service, set time, touch WP, DB or Git.
#>
param([ValidateRange(1,120)][int]$MaxSkewMinutes=5)
$ErrorActionPreference='Stop'
if(!(Test-Path 'D:\ERP7-Development\uat\windows' -PathType Container)){
  throw 'Not the authorized Windows ERP development computer'
}
$started=[DateTimeOffset]::UtcNow
$uri='https://api.github.com'
try {
  $response=Invoke-WebRequest -Uri $uri -Method Head -TimeoutSec 15 -UseBasicParsing
} catch {
  throw 'Could not verify local clock against external HTTPS Date header; date-sensitive ERP UAT is blocked'
}
$finished=[DateTimeOffset]::UtcNow
$header=[string]$response.Headers['Date']
if(!$header){throw 'External HTTPS response supplied no Date header; time UAT remains blocked'}
$reference=[DateTimeOffset]::Parse($header,[System.Globalization.CultureInfo]::InvariantCulture,[System.Globalization.DateTimeStyles]::AssumeUniversal)
$middle=$started.AddTicks([long](($finished-$started).Ticks/2))
$skewMinutes=[Math]::Round([Math]::Abs(($reference-$middle).TotalMinutes),1)
Write-Output ('WINDOWS UTC: '+$middle.ToString('yyyy-MM-ddTHH:mm:ssZ'))
Write-Output ('HTTPS REFERENCE UTC: '+$reference.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ'))
Write-Output ('WINDOWS LOCAL TIME ZONE: '+(Get-TimeZone).Id)
Write-Output ('ABSOLUTE CLOCK SKEW: '+$skewMinutes+' minutes')
$timeSource=(& w32tm /query /source 2>&1) -join ' '
Write-Output ('WINDOWS TIME SOURCE: '+$timeSource)
if($skewMinutes -gt $MaxSkewMinutes){
  Write-Warning ('BLOCKED: Windows clock differs by '+$skewMinutes+' minutes. Do not approve Attendance/GPS/business-date/settlement UAT until time synchronization is verified. This script makes no changes.')
  exit 2
}
Write-Output ('PASS: Local clock within '+$MaxSkewMinutes+' minutes of HTTPS reference; this does not certify the ERP release')
