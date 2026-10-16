param(
    [Parameter(Mandatory=$true)][string]$ApiBase,
    [Parameter(Mandatory=$true)][string]$Mobile,
    [Parameter(Mandatory=$true)][string]$Password,
    [int]$EmployeeId = 0,
    [string]$EvidencePath = 'dist/staging-private-document/EVIDENCE.json'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$ApiBase = $ApiBase.TrimEnd('/')
$uri = [Uri]$ApiBase
if ($uri.Scheme -ne 'https') { throw 'Staging API must use HTTPS.' }
if (-not $uri.AbsolutePath.TrimEnd('/').EndsWith('/wp-json/excel-herbal-erp/v7')) {
    throw 'API base must end with /wp-json/excel-herbal-erp/v7.'
}

$client = [System.Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromSeconds(60)
$access = ''
$tempFile = Join-Path $env:RUNNER_TEMP ('eh7-private-document-' + [Guid]::NewGuid().ToString('N') + '.png')

function Read-JsonResponse {
    param([System.Net.Http.HttpResponseMessage]$Response)
    $text = $Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    $json = $null
    if (-not [string]::IsNullOrWhiteSpace($text)) {
        try { $json = $text | ConvertFrom-Json } catch { $json = $null }
    }
    [pscustomobject]@{ Status=[int]$Response.StatusCode; Json=$json; Text=$text }
}

function Send-Json {
    param([string]$Method,[string]$Path,[object]$Body=$null,[string]$Bearer='',[string]$IdempotencyKey='')
    $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $ApiBase + $Path)
    try {
        $req.Headers.Accept.ParseAdd('application/json')
        $req.Headers.UserAgent.ParseAdd('EH7-Staging-Private-Document/1.0')
        if ($Bearer) { $req.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$Bearer) }
        if ($IdempotencyKey) { $req.Headers.Add('X-Idempotency-Key',$IdempotencyKey) }
        if ($null -ne $Body) {
            $json = $Body | ConvertTo-Json -Depth 10 -Compress
            $req.Content = [System.Net.Http.StringContent]::new($json,[System.Text.Encoding]::UTF8,'application/json')
        }
        $resp = $client.SendAsync($req).GetAwaiter().GetResult()
        return Read-JsonResponse $resp
    } finally { $req.Dispose() }
}

function Assert-Status {
    param([object]$Response,[int]$Expected,[string]$Label,[string]$ExpectedCode='')
    if ($Response.Status -ne $Expected) {
        $actual = if ($Response.Json -and $Response.Json.error) { [string]$Response.Json.error.code } else { '' }
        throw "$Label expected HTTP $Expected but got $($Response.Status) code=$actual"
    }
    if ($ExpectedCode) {
        $actual = if ($Response.Json -and $Response.Json.error) { [string]$Response.Json.error.code } else { '' }
        if ($actual -ne $ExpectedCode) { throw "$Label expected error code $ExpectedCode but got $actual" }
    }
    Write-Host "PASS $Label http=$Expected"
}

$evidence = [ordered]@{
    schema_version = 1
    gate = 'hr_multipart_private_document'
    target_host = $uri.Host
    api_base = $ApiBase
    employee_id = $EmployeeId
    tested_at_utc = [DateTime]::UtcNow.ToString('o')
    commit = $env:GITHUB_SHA
    run_id = $env:GITHUB_RUN_ID
    results = [ordered]@{}
}

try {
    # 1x1 PNG fixture; controlled non-business test content.
    $fixtureBytes = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
    [IO.File]::WriteAllBytes($tempFile,$fixtureBytes)
    $fixtureHash = ([Security.Cryptography.SHA256]::Create().ComputeHash($fixtureBytes) | ForEach-Object ToString x2) -join ''
    $evidence['fixture_sha256'] = $fixtureHash

    $login = Send-Json -Method POST -Path '/auth/login' -Body @{mobile=$Mobile;password=$Password;device='GitHub private-document smoke';device_id=('gha-doc-' + [Guid]::NewGuid().ToString('N'))}
    Assert-Status $login 200 'login'
    $access = [string]$login.Json.data.access_token
    if (-not $access) { throw 'Login did not return access token.' }
    $evidence.results['login'] = 'passed'

    if ($EmployeeId -lt 1) {
        $me = Send-Json -Method GET -Path '/me' -Bearer $access
        Assert-Status $me 200 'resolve_employee'
        $EmployeeId = [int]$me.Json.data.employee.id
        if ($EmployeeId -lt 1) { throw '/me did not return a valid authenticated employee id.' }
        $evidence['employee_id'] = $EmployeeId
        $evidence.results['employee_auto_resolve'] = 'passed'
        Write-Host "PASS employee_auto_resolve id=$EmployeeId"
    }

    $uploadPath = "/organization/employees/$EmployeeId/documents/upload"
    $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, $ApiBase + $uploadPath)
    try {
        $req.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$access)
        $req.Headers.Add('X-Idempotency-Key',('doc-' + [Guid]::NewGuid().ToString('N')))
        $multi = [System.Net.Http.MultipartFormDataContent]::new()
        $multi.Add([System.Net.Http.StringContent]::new('STAGING_FIXTURE'),'document_type')
        $multi.Add([System.Net.Http.StringContent]::new('Controlled staging private document fixture'),'title')
        $bytes = [System.Net.Http.ByteArrayContent]::new($fixtureBytes)
        $bytes.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('image/png')
        $multi.Add($bytes,'file','eh7-staging-fixture.png')
        $req.Content = $multi
        $resp = $client.SendAsync($req).GetAwaiter().GetResult()
        $upload = Read-JsonResponse $resp
    } finally {
        if ($multi) { $multi.Dispose() }
        $req.Dispose()
    }
    Assert-Status $upload 200 'multipart_upload'
    $docId = [int]$upload.Json.data.id
    if ($docId -lt 1) { throw 'Upload did not return a document id.' }
    if ([int]$upload.Json.data.attachment_id -ne 0) { throw 'Private upload unexpectedly created a WordPress attachment.' }
    if ($upload.Json.data.requires_auth -ne $true) { throw 'Private upload did not declare authenticated access.' }
    $downloadUrl = [string]$upload.Json.data.url
    if ($downloadUrl -notmatch '/wp-json/excel-herbal-erp/v7/organization/employees/.+/documents/.+/download') {
        throw 'Private upload returned an unexpected download URL.'
    }
    $evidence['document_id'] = $docId
    $evidence.results['multipart_upload'] = 'passed'
    $evidence.results['no_public_attachment'] = 'passed'

    $downloadReq = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $ApiBase + "/organization/employees/$EmployeeId/documents/$docId/download")
    try {
        $downloadReq.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$access)
        $downloadResp = $client.SendAsync($downloadReq).GetAwaiter().GetResult()
        if ([int]$downloadResp.StatusCode -ne 200) { throw "Authenticated document download failed HTTP $([int]$downloadResp.StatusCode)." }
        $downloadBytes = $downloadResp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        $privateHeader = @($downloadResp.Headers.GetValues('X-EH7-Private-Document')) -join ','
        if ($privateHeader -ne '1') { throw 'Private-document response marker is missing.' }
        $downloadHash = ([Security.Cryptography.SHA256]::Create().ComputeHash($downloadBytes) | ForEach-Object ToString x2) -join ''
    } finally {
        if ($downloadResp) { $downloadResp.Dispose() }
        $downloadReq.Dispose()
    }
    if ($downloadHash -ne $fixtureHash) { throw 'Downloaded document SHA-256 does not match the uploaded fixture.' }
    $evidence['download_sha256'] = $downloadHash
    $evidence.results['authenticated_download_hash_match'] = 'passed'

    $deactivate = Send-Json -Method POST -Path "/organization/employees/$EmployeeId/documents/$docId/deactivate" -Body @{} -Bearer $access -IdempotencyKey ('deactivate-' + [Guid]::NewGuid().ToString('N'))
    Assert-Status $deactivate 200 'deactivate'
    if ([string]$deactivate.Json.data.status -ne 'inactive') { throw 'Document did not become inactive.' }
    $evidence.results['deactivate'] = 'passed'

    $after = Send-Json -Method GET -Path "/organization/employees/$EmployeeId/documents/$docId/download" -Bearer $access
    Assert-Status $after 404 'inactive_download_rejected' 'document_not_found'
    $evidence.results['inactive_download_rejected'] = 'passed'

    $logout = Send-Json -Method POST -Path '/auth/logout' -Bearer $access
    Assert-Status $logout 200 'logout'
    $access = ''
    $evidence.results['logout'] = 'passed'
    $evidence['status'] = 'passed'
} finally {
    if ($access) {
        try { [void](Send-Json -Method POST -Path '/auth/logout' -Bearer $access) } catch {}
    }
    if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile -Force }
    $dir = Split-Path -Parent $EvidencePath
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $evidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $EvidencePath -Encoding utf8
    $client.Dispose()
}

Write-Host 'PASSED staging private-document multipart smoke suite'
