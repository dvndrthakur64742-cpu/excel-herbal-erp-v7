param(
    [Parameter(Mandatory=$true)][string]$ApiBase,
    [Parameter(Mandatory=$true)][string]$Mobile,
    [Parameter(Mandatory=$true)][string]$Password,
    [Parameter(Mandatory=$true)][string]$LimitedMobile,
    [Parameter(Mandatory=$true)][string]$LimitedPassword,
    [string]$ForbiddenProbePath = '/finance/bootstrap',
    [string]$EvidencePath = 'dist/staging-http-auth-smoke/EVIDENCE.json'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$ApiBase = $ApiBase.TrimEnd('/')
$uri = [Uri]$ApiBase
if ($uri.Scheme -ne 'https') { throw 'Staging API must use HTTPS.' }
if (-not $uri.AbsolutePath.TrimEnd('/').EndsWith('/wp-json/excel-herbal-erp/v7')) {
    throw 'API base must end with /wp-json/excel-herbal-erp/v7.'
}

$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.UseCookies = $false
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(30)

function Send-Eh7 {
    param(
        [Parameter(Mandatory=$true)][string]$Method,
        [Parameter(Mandatory=$true)][string]$Path,
        [object]$Body = $null,
        [string]$Bearer = ''
    )
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $ApiBase + $Path)
    try {
        $request.Headers.Accept.ParseAdd('application/json')
        $request.Headers.UserAgent.ParseAdd('EH7-Staging-Auth-Smoke/1.0')
        if (-not [string]::IsNullOrWhiteSpace($Bearer)) {
            $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Bearer)
        }
        if ($null -ne $Body) {
            $json = $Body | ConvertTo-Json -Depth 10 -Compress
            $request.Content = [System.Net.Http.StringContent]::new($json, [System.Text.Encoding]::UTF8, 'application/json')
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
        }
    } finally {
        $request.Dispose()
    }
}

function Assert-Status {
    param([object]$Response,[int]$Expected,[string]$Label,[string]$ExpectedCode='')
    if ($Response.Status -ne $Expected) {
        $actualCode = if ($Response.Json -and $Response.Json.error) { [string]$Response.Json.error.code } else { '' }
        throw "$Label expected HTTP $Expected but got $($Response.Status) code=$actualCode"
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedCode)) {
        $actualCode = if ($Response.Json -and $Response.Json.error) { [string]$Response.Json.error.code } else { '' }
        if ($actualCode -ne $ExpectedCode) { throw "$Label expected error code $ExpectedCode but got $actualCode" }
    }
    Write-Host "PASS $Label http=$Expected"
}

$evidence = [ordered]@{
    schema_version = 1
    target_host = $uri.Host
    api_base = $ApiBase
    tested_at_utc = [DateTime]::UtcNow.ToString('o')
    commit = $env:GITHUB_SHA
    run_id = $env:GITHUB_RUN_ID
    results = [ordered]@{}
}

$primaryAccess = ''
$primaryRefresh = ''
$rotatedAccess = ''
$rotatedRefresh = ''
$limitedAccess = ''

try {
    $r = Send-Eh7 -Method GET -Path '/me'
    Assert-Status $r 401 'missing_token_401' 'not_authenticated'
    $evidence.results['missing_token_401'] = 'passed'

    $r = Send-Eh7 -Method GET -Path '/me' -Bearer ('invalid-' + [Guid]::NewGuid().ToString('N'))
    Assert-Status $r 401 'invalid_token_401' 'not_authenticated'
    $evidence.results['invalid_token_401'] = 'passed'

    $deviceId = 'gha-auth-' + [Guid]::NewGuid().ToString('N')
    $login = Send-Eh7 -Method POST -Path '/auth/login' -Body @{mobile=$Mobile;password=$Password;device='GitHub staging auth smoke';device_id=$deviceId}
    Assert-Status $login 200 'primary_login'
    $primaryAccess = [string]$login.Json.data.access_token
    $primaryRefresh = [string]$login.Json.data.refresh_token
    if ([string]::IsNullOrWhiteSpace($primaryAccess) -or [string]::IsNullOrWhiteSpace($primaryRefresh)) { throw 'Login did not return both tokens.' }
    $evidence.results['primary_login'] = 'passed'

    $me = Send-Eh7 -Method GET -Path '/me' -Bearer $primaryAccess
    Assert-Status $me 200 'bearer_me_200'
    if (-not $me.Json.ok) { throw '/me response is not ok.' }
    $evidence.results['bearer_me_200'] = 'passed'

    $refresh = Send-Eh7 -Method POST -Path '/auth/refresh' -Body @{refresh_token=$primaryRefresh;device='GitHub staging auth smoke';device_id=$deviceId}
    Assert-Status $refresh 200 'refresh_rotation'
    $rotatedAccess = [string]$refresh.Json.data.access_token
    $rotatedRefresh = [string]$refresh.Json.data.refresh_token
    if ([string]::IsNullOrWhiteSpace($rotatedAccess) -or [string]::IsNullOrWhiteSpace($rotatedRefresh)) { throw 'Refresh did not return rotated tokens.' }
    if ($rotatedAccess -eq $primaryAccess -or $rotatedRefresh -eq $primaryRefresh) { throw 'Token rotation reused an old token.' }
    $evidence.results['refresh_rotation'] = 'passed'

    $r = Send-Eh7 -Method GET -Path '/me' -Bearer $primaryAccess
    Assert-Status $r 401 'old_access_revoked_401' 'not_authenticated'
    $evidence.results['old_access_revoked_401'] = 'passed'

    $r = Send-Eh7 -Method POST -Path '/auth/refresh' -Body @{refresh_token=$primaryRefresh;device='GitHub staging auth smoke';device_id=$deviceId}
    Assert-Status $r 401 'old_refresh_revoked_401' 'refresh_invalid'
    $evidence.results['old_refresh_revoked_401'] = 'passed'

    $me2 = Send-Eh7 -Method GET -Path '/me' -Bearer $rotatedAccess
    Assert-Status $me2 200 'rotated_access_me_200'
    $evidence.results['rotated_access_me_200'] = 'passed'

    $limitedDeviceId = 'gha-limited-' + [Guid]::NewGuid().ToString('N')
    $limitedLogin = Send-Eh7 -Method POST -Path '/auth/login' -Body @{mobile=$LimitedMobile;password=$LimitedPassword;device='GitHub staging limited smoke';device_id=$limitedDeviceId}
    Assert-Status $limitedLogin 200 'limited_login'
    $limitedAccess = [string]$limitedLogin.Json.data.access_token
    if ([string]::IsNullOrWhiteSpace($limitedAccess)) { throw 'Limited login did not return an access token.' }
    $evidence.results['limited_login'] = 'passed'

    $forbidden = Send-Eh7 -Method GET -Path $ForbiddenProbePath -Bearer $limitedAccess
    Assert-Status $forbidden 403 'limited_user_403'
    $evidence.results['limited_user_403'] = 'passed'
    $evidence['forbidden_probe_path'] = $ForbiddenProbePath
    $evidence['forbidden_error_code'] = if ($forbidden.Json -and $forbidden.Json.error) { [string]$forbidden.Json.error.code } else { '' }

    $logout = Send-Eh7 -Method POST -Path '/auth/logout' -Bearer $rotatedAccess
    Assert-Status $logout 200 'logout_200'
    $evidence.results['logout_200'] = 'passed'

    $r = Send-Eh7 -Method GET -Path '/me' -Bearer $rotatedAccess
    Assert-Status $r 401 'logout_revocation_401' 'not_authenticated'
    $evidence.results['logout_revocation_401'] = 'passed'

    $limitedLogout = Send-Eh7 -Method POST -Path '/auth/logout' -Bearer $limitedAccess
    Assert-Status $limitedLogout 200 'limited_logout_cleanup'
    $evidence.results['limited_logout_cleanup'] = 'passed'
    $evidence['status'] = 'passed'
} finally {
    foreach ($token in @($rotatedAccess,$primaryAccess,$limitedAccess)) {
        if (-not [string]::IsNullOrWhiteSpace($token)) {
            try { [void](Send-Eh7 -Method POST -Path '/auth/logout' -Bearer $token) } catch {}
        }
    }
    $dir = Split-Path -Parent $EvidencePath
    if (-not [string]::IsNullOrWhiteSpace($dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $evidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $EvidencePath -Encoding utf8
    $client.Dispose()
}

Write-Host 'PASSED real HTTPS staging auth smoke suite'
