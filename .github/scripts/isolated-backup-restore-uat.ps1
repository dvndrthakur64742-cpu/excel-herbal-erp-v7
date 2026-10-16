$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repoRoot = (& git rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or -not $repoRoot) { throw 'Cannot resolve repository root.' }
$sourceHead = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $sourceHead -notmatch '^[0-9a-f]{40}$') { throw 'Cannot resolve exact source head.' }

$runId = if ($env:GITHUB_RUN_ID) { $env:GITHUB_RUN_ID } else { [string][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
$attempt = if ($env:GITHUB_RUN_ATTEMPT) { $env:GITHUB_RUN_ATTEMPT } else { '1' }
$outDir = Join-Path $repoRoot 'dist\isolated-backup-restore'
$tempRoot = Join-Path $env:RUNNER_TEMP ("eh7-isolated-restore-" + $runId + "-" + $attempt)
$backupFile = Join-Path $outDir 'isolated-wordpress-backup.sql'
$evidenceFile = Join-Path $outDir 'EVIDENCE.json'
$bootstrapFile = Join-Path $outDir 'bootstrap.json'
$dbServer = $null
$phpServer = $null
$previousPhprc = $env:PHPRC
$previousPhpPath = $env:PATH
$previousWpRoot = $env:EH7_UAT_WP_ROOT

$toolRoot = 'C:\actions-runner\eh7-toolcache'
$phpDir = Join-Path $toolRoot 'php-8.3.33'
$phpExe = Join-Path $phpDir 'php.exe'
$mariaRoot = Join-Path $toolRoot 'mariadb-11.8.9'
$serverExe = Join-Path $mariaRoot 'bin\mariadbd.exe'
$installExe = @((Join-Path $mariaRoot 'bin\mariadb-install-db.exe'), (Join-Path $mariaRoot 'bin\mysql_install_db.exe')) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
$clientExe = Join-Path $mariaRoot 'bin\mariadb.exe'
$adminExe = Join-Path $mariaRoot 'bin\mariadb-admin.exe'
$dumpExe = Join-Path $mariaRoot 'bin\mariadb-dump.exe'
$wpRoot = Join-Path $tempRoot 'wordpress'
$wpCliPhar = Join-Path $tempRoot 'wp-cli.phar'
$phpIni = Join-Path $tempRoot 'php.ini'
$routerFile = Join-Path $tempRoot 'router.php'
$serverError = Join-Path $tempRoot 'mariadb-server.stderr.log'
$serverStdout = Join-Path $tempRoot 'mariadb-server.stdout.log'
$phpServerError = Join-Path $tempRoot 'php-server.stderr.log'
$phpServerOutput = Join-Path $tempRoot 'php-server.stdout.log'
$noTokenFile = Join-Path $tempRoot 'no-token.json'
$invalidTokenFile = Join-Path $tempRoot 'invalid-token.json'
$limitedForbiddenFile = Join-Path $tempRoot 'limited-forbidden.json'
$limitedPostLogoutFile = Join-Path $tempRoot 'limited-post-logout.json'
$inactiveFile = Join-Path $tempRoot 'inactive-download.json'
$healthFile = Join-Path $tempRoot 'health.json'
$preHeaders = Join-Path $tempRoot 'pre-download.headers'
$prePng = Join-Path $tempRoot 'pre-download.png'
$postHeaders = Join-Path $tempRoot 'post-download.headers'
$postPng = Join-Path $tempRoot 'post-download.png'
$curlExe = (Get-Command curl.exe -ErrorAction Stop).Source

$dbName = 'wordpress'
$dbUser = 'eh7wp'
$dbPassword = [Guid]::NewGuid().ToString('N')
$dbRootPassword = [Guid]::NewGuid().ToString('N')
$adminLogin = 'uat-admin'
$adminPassword = 'Eh7Admin!2026-' + [Guid]::NewGuid().ToString('N')
$adminMobile = '9000000001'
$limitedPassword = 'Eh7Field!2026-' + [Guid]::NewGuid().ToString('N')
$limitedMobile = '9000000002'
$webPort = Get-Random -Minimum 20000 -Maximum 29999
$dbPort = Get-Random -Minimum 34000 -Maximum 34999
$baseUrl = "http://127.0.0.1:$webPort"
$api = "$baseUrl/wp-json/excel-herbal-erp/v7"
$fixture = Join-Path $tempRoot 'fixture.png'

function Invoke-CurlText {
    param([string[]]$CurlArgs)
    $result = & $script:curlExe @CurlArgs
    if ($LASTEXITCODE -ne 0) { throw "curl request failed (exit $LASTEXITCODE)." }
    return (($result | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
}

function Invoke-WpCli {
    param([string[]]$CliArgs)
    $result = & $script:phpExe -c $script:phpIni $script:wpCliPhar @CliArgs "--path=$script:wpRoot"
    if ($LASTEXITCODE -ne 0) { throw "WP-CLI command failed: $($CliArgs -join ' ')" }
    return ,$result
}

function Invoke-DbScalar {
    param([string]$Sql)
    $result = & $script:clientExe '--host=127.0.0.1' "--port=$script:dbPort" '--user=root' "--password=$script:dbRootPassword" '-N' '-B' $script:dbName '-e' $Sql
    if ($LASTEXITCODE -ne 0) { throw 'MariaDB scalar query failed.' }
    return (($result | ForEach-Object { [string]$_ }) -join '').Trim()
}

function Test-HttpStatus {
    param([string]$Url, [string]$OutputFile, [string[]]$Headers = @())
    $args = @('-sS', '-o', $OutputFile, '-w', '%{http_code}')
    foreach ($header in $Headers) { $args += @('-H', $header) }
    $args += $Url
    $status = Invoke-CurlText $args
    if ($status -notmatch '^\d{3}$') { throw "Unexpected HTTP status result: $status" }
    return [int]$status
}

function Invoke-Login {
    param([string]$Mobile, [string]$Password, [string]$Device, [string]$DeviceId)
    $body = @{ mobile=$Mobile; password=$Password; device=$Device; device_id=$DeviceId } | ConvertTo-Json -Compress
    $json = Invoke-CurlText @('-fsS','-H','Content-Type: application/json','-d',$body,"$script:api/auth/login")
    return ($json | ConvertFrom-Json)
}

function Get-BearerToken {
    param([string]$Mobile, [string]$Password, [string]$Device, [string]$DeviceId)
    $login = Invoke-Login $Mobile $Password $Device $DeviceId
    if (-not $login.ok -or -not $login.data.access_token) { throw 'Synthetic account login did not return an access token.' }
    return [string]$login.data.access_token
}

function Invoke-NativeInputProcess {
    param([string]$FilePath, [string]$Arguments, [string]$InputFile)
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    if (-not $proc.Start()) { throw 'Could not start MariaDB restore client.' }
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $reader = [System.IO.StreamReader]::new($InputFile, [System.Text.Encoding]::UTF8, $true)
    try {
        while (($line = $reader.ReadLine()) -ne $null) { $proc.StandardInput.WriteLine($line) }
    } finally {
        $reader.Dispose()
        $proc.StandardInput.Close()
    }
    $proc.WaitForExit()
    $stderrText = $stderrTask.Result
    $null = $stdoutTask.Result
    $exitCode = $proc.ExitCode
    $proc.Dispose()
    if ($exitCode -ne 0) { throw "MariaDB restore failed (exit $exitCode). $stderrText" }
}

try {
    if (Test-Path -LiteralPath $outDir) { Remove-Item -LiteralPath $outDir -Recurse -Force }
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    if (-not (Test-Path -LiteralPath $phpExe -PathType Leaf)) {
        New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
        if (Test-Path -LiteralPath $phpDir) { Remove-Item -LiteralPath $phpDir -Recurse -Force }
        $phpArchive = Join-Path $env:RUNNER_TEMP 'eh7-php-8.3.33.zip'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://downloads.php.net/~windows/releases/archives/php-8.3.33-nts-Win32-vs16-x64.zip' -OutFile $phpArchive
        $phpActual = (Get-FileHash -LiteralPath $phpArchive -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($phpActual -ne '534399107056313246f424adbbb7937337e40fbbf6aa7bc26287ba9cfd2e4a2a') { throw 'PHP archive SHA-256 mismatch.' }
        Expand-Archive -LiteralPath $phpArchive -DestinationPath $phpDir -Force
    }
    $env:PATH = "$phpDir;$env:PATH"

    if (-not (Test-Path -LiteralPath $serverExe -PathType Leaf)) {
        New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
        if (Test-Path -LiteralPath $mariaRoot) { Remove-Item -LiteralPath $mariaRoot -Recurse -Force }
        $mariaEndpoint = 'https://downloads.mariadb.org/rest-api/mariadb/11.8.9/mariadb-11.8.9-winx64.zip'
        $mariaMeta = Invoke-RestMethod -UseBasicParsing -Uri ($mariaEndpoint + '/checksum')
        $mariaExpected = ([string]$mariaMeta.response.checksum.sha256sum).ToLowerInvariant()
        if ($mariaExpected -notmatch '^[0-9a-f]{64}$') { throw 'MariaDB checksum metadata unavailable.' }
        $mariaArchive = Join-Path $toolRoot 'mariadb-11.8.9-winx64.zip'
        Invoke-WebRequest -UseBasicParsing -Uri $mariaEndpoint -OutFile $mariaArchive
        $mariaActual = (Get-FileHash -LiteralPath $mariaArchive -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($mariaActual -ne $mariaExpected) { Remove-Item -LiteralPath $mariaArchive -Force; throw 'MariaDB archive SHA-256 mismatch.' }
        $mariaExtract = Join-Path $env:RUNNER_TEMP 'eh7-mariadb-extract'
        if (Test-Path -LiteralPath $mariaExtract) { Remove-Item -LiteralPath $mariaExtract -Recurse -Force }
        Expand-Archive -LiteralPath $mariaArchive -DestinationPath $mariaExtract -Force
        $mariaFound = Get-ChildItem -LiteralPath $mariaExtract -Recurse -Filter mariadbd.exe -File | Select-Object -First 1
        if (-not $mariaFound) { throw 'mariadbd.exe not found in verified archive.' }
        $mariaExpandedRoot = Split-Path (Split-Path $mariaFound.FullName -Parent) -Parent
        Move-Item -LiteralPath $mariaExpandedRoot -Destination $mariaRoot
        Remove-Item -LiteralPath $mariaExtract -Recurse -Force
    }

    $tools = @($serverExe, $installExe, $clientExe, $adminExe, $dumpExe)
    if ($tools | Where-Object { -not $_ -or -not (Test-Path -LiteralPath $_ -PathType Leaf) }) { throw 'Portable MariaDB tools are incomplete.' }

    $extensionDir = Join-Path $phpDir 'ext'
    $requiredExtensions = @('mysqli','openssl','fileinfo','curl','mbstring','dom','xml','simplexml','zip')
    foreach ($ext in $requiredExtensions) {
        if (-not (Test-Path -LiteralPath (Join-Path $extensionDir ("php_" + $ext + ".dll")) -PathType Leaf)) { throw "Required PHP extension file is missing: $ext" }
    }
    $iniLines = @(
        ('extension_dir="' + $extensionDir.Replace('\','/') + '"'),
        'date.timezone=UTC',
        'memory_limit=512M',
        'upload_max_filesize=32M',
        'post_max_size=40M',
        'max_execution_time=120'
    )
    foreach ($extension in $requiredExtensions) { $iniLines += "extension=$extension" }
    if (Test-Path -LiteralPath (Join-Path $extensionDir 'php_pdo_mysql.dll') -PathType Leaf) { $iniLines += 'extension=pdo_mysql' }
    if (Test-Path -LiteralPath (Join-Path $extensionDir 'php_sodium.dll') -PathType Leaf) { $iniLines += 'extension=sodium' }
    Set-Content -LiteralPath $phpIni -Value $iniLines -Encoding ascii

    $script:phpExe = $phpExe
    $script:phpIni = $phpIni
    $script:wpCliPhar = $wpCliPhar
    $script:wpRoot = $wpRoot
    $script:clientExe = $clientExe
    $script:dbPort = $dbPort
    $script:dbRootPassword = $dbRootPassword
    $script:dbName = $dbName
    $script:curlExe = $curlExe
    $script:api = $api
    $script:adminMobile = $adminMobile
    $script:adminPassword = $adminPassword
    $script:limitedMobile = $limitedMobile
    $script:limitedPassword = $limitedPassword
    $script:baseUrl = $baseUrl

    & $phpExe -c $phpIni -r "if (!extension_loaded('mysqli') || !extension_loaded('openssl') || !class_exists('finfo') || !function_exists('curl_init') || !class_exists('DOMDocument') || !class_exists('ZipArchive')) { fwrite(STDERR,'Required PHP extension unavailable'); exit(9); }"
    if ($LASTEXITCODE -ne 0) { throw 'PHP mysqli/OpenSSL/fileinfo/curl/dom/zip extensions are required.' }

    $dbDir = Join-Path $tempRoot 'mariadb-data'
    & $installExe "--datadir=$dbDir" "--password=$dbRootPassword" "--port=$dbPort" --allow-remote-root-access
    if ($LASTEXITCODE -ne 0) { throw 'Isolated MariaDB data directory initialization failed.' }
    $defaultsFile = Join-Path $dbDir 'my.ini'
    if (-not (Test-Path -LiteralPath $defaultsFile -PathType Leaf)) { throw 'MariaDB my.ini was not generated.' }
    $serverError = Join-Path $tempRoot 'mariadb-server.stderr.log'
    $serverStdout = Join-Path $tempRoot 'mariadb-server.stdout.log'
    $dbServer = Start-Process -FilePath $serverExe -ArgumentList @("--defaults-file=$defaultsFile",'--console','--bind-address=127.0.0.1') -PassThru -WindowStyle Hidden -RedirectStandardOutput $serverStdout -RedirectStandardError $serverError
    $dbReady = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 1
        if ($dbServer.HasExited) { break }
        & $adminExe '--host=127.0.0.1' "--port=$dbPort" '--user=root' "--password=$dbRootPassword" 'ping' '--silent' 2>$null
        if ($LASTEXITCODE -eq 0) { $dbReady = $true; break }
    }
    if (-not $dbReady) { throw 'Isolated MariaDB did not become ready.' }

    $createSql = "CREATE DATABASE $dbName CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; CREATE USER '$dbUser'@'127.0.0.1' IDENTIFIED BY '$dbPassword'; GRANT ALL PRIVILEGES ON $dbName.* TO '$dbUser'@'127.0.0.1'; FLUSH PRIVILEGES;"
    & $clientExe '--host=127.0.0.1' "--port=$dbPort" '--user=root' "--password=$dbRootPassword" '-e' $createSql
    if ($LASTEXITCODE -ne 0) { throw 'Unable to create fresh synthetic WordPress database.' }

    $wpZip = Join-Path $tempRoot 'wordpress-latest.zip'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://wordpress.org/latest.zip' -OutFile $wpZip
    $wpExtract = Join-Path $tempRoot 'wp-extract'
    Expand-Archive -LiteralPath $wpZip -DestinationPath $wpExtract -Force
    $wpSource = Join-Path $wpExtract 'wordpress'
    if (-not (Test-Path -LiteralPath (Join-Path $wpSource 'wp-settings.php') -PathType Leaf)) { throw 'Official WordPress archive did not contain expected core.' }
    New-Item -ItemType Directory -Path $wpRoot -Force | Out-Null
    Copy-Item -Path (Join-Path $wpSource '*') -Destination $wpRoot -Recurse -Force

    $wpCliUrl = 'https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar'
    Invoke-WebRequest -UseBasicParsing -Uri $wpCliUrl -OutFile $wpCliPhar
    $wpCliHashText = (Invoke-WebRequest -UseBasicParsing -Uri ($wpCliUrl + '.sha512')).Content.Trim().ToLowerInvariant()
    if ($wpCliHashText -notmatch '^[0-9a-f]{128}$') { throw 'WP-CLI SHA-512 sidecar was invalid.' }
    if ((Get-FileHash -LiteralPath $wpCliPhar -Algorithm SHA512).Hash.ToLowerInvariant() -ne $wpCliHashText) { throw 'WP-CLI SHA-512 mismatch.' }
    Invoke-WpCli @('--info')
    Invoke-WpCli @('core','verify-checksums')

    $pluginDir = Join-Path $wpRoot 'wp-content\plugins\excel-herbal-erp-v7'
    New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
    Copy-Item -Path (Join-Path $repoRoot 'backend\excel-herbal-erp-v7\*') -Destination $pluginDir -Recurse -Force
    $metaText = @(
        '<?php',
        'if(!defined(''ABSPATH''))exit;',
        "define('EH7_SOURCE_HEAD','$sourceHead');",
        "define('EH7_DEPLOY_ENVIRONMENT','staging');"
    )
    Set-Content -LiteralPath (Join-Path $pluginDir 'build-meta.php') -Value $metaText -Encoding ascii

    Invoke-WpCli @('core','config',"--dbname=$dbName","--dbuser=$dbUser","--dbpass=$dbPassword","--dbhost=127.0.0.1:$dbPort",'--dbprefix=wp_','--skip-check')
    Invoke-WpCli @('config','set','WP_ENVIRONMENT_TYPE','staging')
    Invoke-WpCli @('config','set','DISALLOW_FILE_EDIT','true','--raw')
    Invoke-WpCli @('config','set','WP_HOME',$baseUrl)
    Invoke-WpCli @('config','set','WP_SITEURL',$baseUrl)
    Invoke-WpCli @('core','install',"--url=$baseUrl",'--title=EH7-Isolated-Recovery-UAT',"--admin_user=$adminLogin","--admin_password=$adminPassword",'--admin_email=uat@example.invalid','--skip-email')
    Invoke-WpCli @('option','update','permalink_structure','/%postname%/')
    Invoke-WpCli @('rewrite','flush','--hard')
    Invoke-WpCli @('plugin','activate','excel-herbal-erp-v7')

    $env:EH7_UAT_WP_ADMIN_LOGIN = $adminLogin
    $env:EH7_UAT_ADMIN_PASSWORD = $adminPassword
    $env:EH7_UAT_ADMIN_MOBILE = $adminMobile
    $env:EH7_UAT_LIMITED_PASSWORD = $limitedPassword
    $env:EH7_UAT_LIMITED_MOBILE = $limitedMobile
    $env:EH7_UAT_COMPANY_NAME = 'EH7 Isolated Restore UAT'
    $env:EH7_UAT_BRANCH_NAME = 'Isolated UAT Branch'
    $bootstrapOutput = Invoke-WpCli @('eval-file','wp-content/plugins/excel-herbal-erp-v7/tools/fresh-uat-bootstrap.php')
    [System.IO.File]::WriteAllText($bootstrapFile, (($bootstrapOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
    if ((Invoke-DbScalar "SELECT option_value FROM wp_options WHERE option_name='eh7_uat_seed_source_head' LIMIT 1") -ne $sourceHead) { throw 'Bootstrap source marker did not match exact source head.' }
    if ((Invoke-DbScalar "SELECT option_value FROM wp_options WHERE option_name='eh7_uat_seed_mode' LIMIT 1") -ne 'fresh_synthetic') { throw 'Synthetic seed mode marker is missing.' }

    $routerContent = @(
        '<?php',
        '$root = getenv(''EH7_UAT_WP_ROOT'') ?: getcwd();',
        '$path = parse_url($_SERVER[''REQUEST_URI''] ?? ''/'', PHP_URL_PATH) ?: ''/'';',
        '$relative = ltrim(str_replace(''/'', DIRECTORY_SEPARATOR, $path), DIRECTORY_SEPARATOR);',
        '$file = $root . DIRECTORY_SEPARATOR . $relative;',
        'if ($path !== ''/'' && is_file($file)) { return false; }',
        'require $root . DIRECTORY_SEPARATOR . ''index.php'';'
    )
    Set-Content -LiteralPath $routerFile -Value $routerContent -Encoding ascii
    $env:EH7_UAT_WP_ROOT = $wpRoot
    $phpServerOutput = Join-Path $tempRoot 'php-server.stdout.log'
    $phpServerError = Join-Path $tempRoot 'php-server.stderr.log'
    $phpServer = Start-Process -FilePath $phpExe -ArgumentList @('-c',$phpIni,'-S',"127.0.0.1:$webPort",$routerFile) -WorkingDirectory $wpRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput $phpServerOutput -RedirectStandardError $phpServerError

    $healthReady = $false
    for ($i = 0; $i -lt 45; $i++) {
        Start-Sleep -Seconds 1
        if ($phpServer.HasExited) { break }
        $status = Invoke-CurlText @('-sS','-o',$healthFile,'-w','%{http_code}',"$api/health")
        if ($status -eq '200') { $healthReady = $true; break }
    }
    if (-not $healthReady) { throw 'ERP health endpoint did not become ready in isolated PHP server.' }
    $health = Get-Content -LiteralPath $healthFile -Raw | ConvertFrom-Json
    if (-not $health.ok -or $health.data.source_head -ne $sourceHead -or $health.data.environment -ne 'staging' -or -not $health.data.schema_installed -or -not $health.data.uat_bootstrap.seeded -or -not $health.data.uat_bootstrap.synthetic_only) { throw 'Fresh UAT health contract did not match exact-head staging state.' }

    if ((Test-HttpStatus "$api/me" $noTokenFile) -ne 401) { throw 'Missing bearer token did not return HTTP 401.' }
    if ((Test-HttpStatus "$api/me" $invalidTokenFile @('Authorization: Bearer definitely-invalid-token')) -ne 401) { throw 'Invalid bearer token did not return HTTP 401.' }
    $limitedToken = Get-BearerToken $limitedMobile $limitedPassword 'Isolated limited-role UAT' 'isolated-limited-role'
    $limitedMeRaw = Invoke-CurlText @('-fsS','-H',"Authorization: Bearer $limitedToken","$api/me")
    $limitedMe = $limitedMeRaw | ConvertFrom-Json
    if (-not $limitedMe.ok) { throw 'Limited-role account could not access /me.' }
    if ((Test-HttpStatus "$api/administration/diagnostics" $limitedForbiddenFile @("Authorization: Bearer $limitedToken")) -ne 403) { throw 'Limited-role diagnostics did not return HTTP 403.' }
    $limitedForbidden = Get-Content -LiteralPath $limitedForbiddenFile -Raw | ConvertFrom-Json
    if ($limitedForbidden.error.code -ne 'permission_denied') { throw 'Limited-role forbidden response code mismatch.' }
    $null = Invoke-CurlText @('-fsS','-X','POST','-H',"Authorization: Bearer $limitedToken","$api/auth/logout")
    if ((Test-HttpStatus "$api/me" $limitedPostLogoutFile @("Authorization: Bearer $limitedToken")) -ne 401) { throw 'Limited-role token remained valid after logout.' }

    [System.IO.File]::WriteAllBytes($fixture,[Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='))
    $fixtureHash = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToLowerInvariant()
    $adminToken = Get-BearerToken $adminMobile $adminPassword 'Isolated restore UAT' 'isolated-restore-uat'
    $meRaw = Invoke-CurlText @('-fsS','-H',"Authorization: Bearer $adminToken","$api/me")
    $me = $meRaw | ConvertFrom-Json
    $employeeId = [int]$me.data.employee.id
    if ($employeeId -le 0) { throw 'Synthetic admin employee ID is missing.' }

    $uploadRaw = Invoke-CurlText @('-fsS','-H',"Authorization: Bearer $adminToken",'-H',"X-Idempotency-Key: isolated-doc-$runId",'-F','document_type=RESTORE_FIXTURE','-F','title=Isolated backup restore private document fixture','-F',"file=@$fixture;type=image/png;filename=isolated-restore-fixture.png","$api/organization/employees/$employeeId/documents/upload")
    $upload = $uploadRaw | ConvertFrom-Json
    if (-not $upload.ok -or [int]$upload.data.attachment_id -ne 0 -or -not $upload.data.requires_auth) { throw 'Private synthetic document upload contract failed.' }
    $documentId = [int]$upload.data.id

    $null = Invoke-CurlText @('-fsS','-D',$preHeaders,'-o',$prePng,'-H',"Authorization: Bearer $adminToken","$api/organization/employees/$employeeId/documents/$documentId/download")
    if (-not (Get-Content -LiteralPath $preHeaders -Raw | Select-String -Pattern '(?im)^X-EH7-Private-Document:\s*1')) { throw 'Private document header missing before backup.' }
    $preHash = (Get-FileHash -LiteralPath $prePng -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($preHash -ne $fixtureHash) { throw 'Private document bytes mismatch before backup.' }
    $null = Invoke-CurlText @('-fsS','-X','POST','-H',"Authorization: Bearer $adminToken","$api/auth/logout")

    $keyHashBefore = Invoke-DbScalar "SELECT SHA2(option_value,256) FROM wp_options WHERE option_name='eh7_document_key' LIMIT 1"
    if ($keyHashBefore -notmatch '^[0-9A-Fa-f]{64}$') { throw 'Document encryption key hash was not found before backup.' }

    $dumpArgs = "--host=127.0.0.1 --port=$dbPort --user=root --password=$dbRootPassword --single-transaction --quick --skip-lock-tables --default-character-set=utf8mb4 --databases $dbName"
    $dumpPsi = [System.Diagnostics.ProcessStartInfo]::new()
    $dumpPsi.FileName = $dumpExe
    $dumpPsi.Arguments = $dumpArgs
    $dumpPsi.UseShellExecute = $false
    $dumpPsi.CreateNoWindow = $true
    $dumpPsi.RedirectStandardOutput = $true
    $dumpPsi.RedirectStandardError = $true
    $dumpProc = [System.Diagnostics.Process]::new()
    $dumpProc.StartInfo = $dumpPsi
    if (-not $dumpProc.Start()) { throw 'Could not start MariaDB dump process.' }
    $dumpStdoutTask = $dumpProc.StandardOutput.ReadToEndAsync()
    $dumpStderrTask = $dumpProc.StandardError.ReadToEndAsync()
    $dumpProc.WaitForExit()
    $dumpText = $dumpStdoutTask.Result
    $dumpErrorText = $dumpStderrTask.Result
    $dumpExit = $dumpProc.ExitCode
    $dumpProc.Dispose()
    if ($dumpExit -ne 0) { throw "MariaDB backup failed (exit $dumpExit)." }
    [System.IO.File]::WriteAllText($backupFile,$dumpText,[System.Text.UTF8Encoding]::new($false))
    $backupInfo = Get-Item -LiteralPath $backupFile
    if ($backupInfo.Length -le 1024) { throw 'MariaDB backup is unexpectedly small.' }
    $backupHash = (Get-FileHash -LiteralPath $backupFile -Algorithm SHA256).Hash.ToLowerInvariant()

    & $clientExe '--host=127.0.0.1' "--port=$dbPort" '--user=root' "--password=$dbRootPassword" '-e' "DROP DATABASE $dbName;"
    if ($LASTEXITCODE -ne 0) { throw 'Could not drop the disposable synthetic database before restore.' }
    Invoke-NativeInputProcess $clientExe "--host=127.0.0.1 --port=$dbPort --user=root --password=$dbRootPassword" $backupFile

    $keyHashAfter = Invoke-DbScalar "SELECT SHA2(option_value,256) FROM wp_options WHERE option_name='eh7_document_key' LIMIT 1"
    if ($keyHashAfter -ne $keyHashBefore) { throw 'Encryption key hash did not survive database restore.' }
    $postHealthRaw = Invoke-CurlText @('-fsS',"$api/health")
    $postHealth = $postHealthRaw | ConvertFrom-Json
    if (-not $postHealth.ok -or $postHealth.data.source_head -ne $sourceHead -or $postHealth.data.environment -ne 'staging' -or -not $postHealth.data.schema_installed -or -not $postHealth.data.uat_bootstrap.seeded) { throw 'Post-restore health verification failed.' }

    $adminToken = Get-BearerToken $adminMobile $adminPassword 'Isolated restore post-backup' 'isolated-restore-post-backup'
    $null = Invoke-CurlText @('-fsS','-D',$postHeaders,'-o',$postPng,'-H',"Authorization: Bearer $adminToken","$api/organization/employees/$employeeId/documents/$documentId/download")
    if (-not (Get-Content -LiteralPath $postHeaders -Raw | Select-String -Pattern '(?im)^X-EH7-Private-Document:\s*1')) { throw 'Private document header missing after restore.' }
    $postHash = (Get-FileHash -LiteralPath $postPng -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($postHash -ne $fixtureHash) { throw 'Private document bytes mismatch after restore.' }

    $deactivateRaw = Invoke-CurlText @('-fsS','-X','POST','-H',"Authorization: Bearer $adminToken",'-H','Content-Type: application/json','-H',"X-Idempotency-Key: isolated-doc-deactivate-$runId",'-d','{}',"$api/organization/employees/$employeeId/documents/$documentId/deactivate")
    $deactivate = $deactivateRaw | ConvertFrom-Json
    if (-not $deactivate.ok -or $deactivate.data.status -ne 'inactive') { throw 'Synthetic document deactivation failed.' }
    if ((Test-HttpStatus "$api/organization/employees/$employeeId/documents/$documentId/download" $inactiveFile @("Authorization: Bearer $adminToken")) -ne 404) { throw 'Inactive private document was not rejected with HTTP 404.' }
    $inactive = Get-Content -LiteralPath $inactiveFile -Raw | ConvertFrom-Json
    if ($inactive.error.code -ne 'document_not_found') { throw 'Inactive document error code mismatch.' }
    $null = Invoke-CurlText @('-fsS','-X','POST','-H',"Authorization: Bearer $adminToken","$api/auth/logout")

    $evidence = [ordered]@{
        schema_version=1
        gate='host_backup_restore'
        status='passed'
        environment='fresh-isolated-wordpress-mariadb'
        source_head=$sourceHead
        database='MariaDB 11.8.9'
        wordpress='isolated official WordPress archive with PHP 8.3.33 built-in server'
        backup=@{sha256=$backupHash;bytes=[long]$backupInfo.Length;single_transaction=$true}
        synthetic_seed=$true
        private_document=@{
            employee_id=$employeeId
            document_id=$documentId
            fixture_sha256=$fixtureHash
            pre_backup_download_hash_match=$true
            encryption_key_hash_restored=$true
            post_restore_download_hash_match=$true
            deactivation_verified=$true
            inactive_download_rejected=$true
        }
        auth_boundaries=@{
            missing_token_401=$true
            invalid_token_401=$true
            distinct_limited_login_200=$true
            distinct_limited_forbidden_403=$true
            limited_logout_revocation_401=$true
        }
        checks=@{
            exact_head_plugin=$true
            staging_environment=$true
            schema_installed=$true
            fresh_uat_seeded=$true
            database_dump=$true
            database_drop=$true
            database_restore=$true
            document_key_recovery=$true
            authenticated_private_document_after_restore=$true
        }
    }
    $json = $evidence | ConvertTo-Json -Depth 20 -Compress
    [System.IO.File]::WriteAllText($evidenceFile,$json,[System.Text.UTF8Encoding]::new($false))
    Write-Output $json
    Write-Output 'PASS isolated WordPress + MariaDB backup/restore, auth boundaries, and private document-key recovery'
}
catch {
    Write-Error ("ISOLATED_RECOVERY_FAILED: " + $_.Exception.Message)
    if ($serverError -and (Test-Path -LiteralPath $serverError)) { Get-Content -LiteralPath $serverError -Tail 30 | Write-Output }
    if ($phpServerError -and (Test-Path -LiteralPath $phpServerError)) { Get-Content -LiteralPath $phpServerError -Tail 30 | Write-Output }
    throw
}
finally {
    $env:PHPRC = $previousPhprc
    $env:PATH = $previousPhpPath
    $env:EH7_UAT_WP_ROOT = $previousWpRoot
    if ($phpServer -and -not $phpServer.HasExited) {
        Stop-Process -Id $phpServer.Id -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $phpServer.Id -ErrorAction SilentlyContinue
    }
    if ($dbServer -and -not $dbServer.HasExited) {
        Stop-Process -Id $dbServer.Id -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $dbServer.Id -ErrorAction SilentlyContinue
    }
    if ($tempRoot -and (Test-Path -LiteralPath $tempRoot)) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
