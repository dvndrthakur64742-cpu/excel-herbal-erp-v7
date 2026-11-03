#requires -Version 5.1
# Separate localhost WordPress candidate. Original WordPress and source DB untouched.
param([switch]$DryRun)
$ErrorActionPreference='Stop'
$dev='D:\ERP7-Development'
$src='D:\xampp\htdocs\erp-uat'
$dest='D:\xampp\htdocs\erp-uat-candidate'
$repo='D:\ERP7-UAT-Candidate'
$backup='E:\ERP-Backups\eh7-synthetic-checkpoint-20261103-195121'
$db='eh7_restore_5ec7b1894f7a'
$url='http://127.0.0.1:18880/erp-uat-candidate'
$secrets='D:\ERP-Local-Secrets'
$mysql='D:\xampp\mysql\bin\mysql.exe'
if((Test-Path $dest) -or (Test-Path $repo)){throw 'Candidate path already exists: refusing overwrite'}
foreach($p in @($dev,$src,$backup,$secrets)){
  if(!(Test-Path $p -PathType Container)){throw ('Missing local source '+$p)}
}
$report=Get-Content (Join-Path $backup 'restore-rehearsal.json') -Raw | ConvertFrom-Json
if($report.backup_type -ne 'synthetic_isolated_restore_rehearsal' -or
 $report.original_database -ne 'eh7_local_uat' -or $report.restored_database -ne $db -or
 $report.verified_tables -ne 97 -or $report.all_row_counts_equal -ne $true -or
 $report.original_row_counts_unchanged -ne $true -or $report.isolated_restore_verified -ne $true){
 throw 'Invalid independent restore evidence'
}
$head=(& git -C $dev rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0 -or $head -notmatch '^[a-f0-9]{40}$' -or @(& git -C $dev status --porcelain --untracked-files=no).Count){
 throw 'Development source is not clean and SHA-pinned'
}
$health=Invoke-RestMethod http://127.0.0.1:18880/erp-uat/wp-json/excel-herbal-erp/v7/health -TimeoutSec 12
if($health.ok -ne $true -or $health.data.environment -ne 'staging' -or
 $health.data.uat_bootstrap.synthetic_only -ne $true -or
 $health.data.staging_safety.sanitized -ne $true -or
 $health.data.staging_safety.active_mobile_sessions_zero -ne $true){
 throw 'Original WordPress does not pass safe synthetic staging preflight'
}
foreach($port in @(18880,3306)){
 $connections=@(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction Stop)
 if(!$connections.Count -or @($connections | Where-Object {$_.LocalAddress -ne '127.0.0.1'}).Count){
  throw 'Not a loopback-only UAT port'
 }
}
$secret=Get-Content (Join-Path $secrets 'local-uat-db.json') -Raw | ConvertFrom-Json
if($secret.name -ne 'eh7_local_uat' -or $secret.site_url -ne 'http://127.0.0.1:18880/erp-uat'){
 throw 'Not an approved local synthetic credential identity'
}
Write-Output ('PASS isolated candidate preflight; DB='+$db+'; SHA='+$head.Substring(0,8))
if($DryRun){Write-Output 'DRY RUN: no files or database changes';return}
$adminFile=Join-Path $secrets ('mysql-candidate-'+[guid]::NewGuid().ToString('N')+'.tmp')
try {
 & git clone --quiet --no-hardlinks --no-checkout $dev $repo
 if($LASTEXITCODE -ne 0){throw 'Cannot create independent Git checkout'}
 & git -C $repo checkout --quiet --detach $head
 if($LASTEXITCODE -ne 0 -or (& git -C $repo rev-parse HEAD).Trim() -ne $head){
  throw 'Candidate plugin does not match pinned Git SHA'
 }
 New-Item -Path $dest -ItemType Directory -ErrorAction Stop | Out-Null
 & robocopy $src $dest /E /XD (Join-Path $src 'wp-content') /XF wp-config.php .htaccess /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
 if($LASTEXITCODE -ge 8){throw 'WordPress core copy failed'}
 $contents=Join-Path $dest 'wp-content'
 New-Item $contents -ItemType Directory -ErrorAction Stop | Out-Null
 New-Item (Join-Path $contents 'plugins') -ItemType Directory -ErrorAction Stop | Out-Null
 Copy-Item (Join-Path $src 'wp-content\themes') (Join-Path $contents 'themes') -Recurse -ErrorAction Stop
 $plugin=Join-Path $repo 'plugin\excel-herbal-erp-v7'
 $mount=New-Item -ItemType Junction -Path (Join-Path $contents 'plugins\excel-herbal-erp-v7') -Target $plugin -ErrorAction Stop
 if($mount.LinkType -ne 'Junction'){throw 'Cannot create isolated plugin junction'}
 $rng=[System.Security.Cryptography.RandomNumberGenerator]::Create()
 $bytes=New-Object byte[] 24
 try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
 $password=[Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','A').Replace('/','B')
 $username='eh7cand_'+[guid]::NewGuid().ToString('N').Substring(0,8)
 if($username -notmatch '^eh7cand_[a-f0-9]{8}$' -or $password -notmatch '^[A-Za-z0-9]{25,40}$'){
  throw 'Invalid generated credentials'
 }
 $rootPassword=[string]$secret.root_password
 if($rootPassword -match '["\\\r\n]'){throw 'Unsupported local-only root secret encoding'}
 @('[client]','host=127.0.0.1','port=3306','user=root',('password="'+$rootPassword+'"')) |
   Set-Content -LiteralPath $adminFile -Encoding ASCII -ErrorAction Stop
 $q=[string][char]96
 $sql="CREATE USER '"+$username+"'@'127.0.0.1' IDENTIFIED BY '"+$password+"';"+
 "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP, REFERENCES ON "+$q+$db+$q+".* TO '"+$username+"'@'127.0.0.1';"
 & $mysql "--defaults-extra-file=$adminFile" '--protocol=TCP' '--host=127.0.0.1' '--port=3306' "--execute=$sql" 2>&1 | Out-Null
 if($LASTEXITCODE -ne 0){throw 'Cannot grant candidate-only MariaDB permissions'}
 $cfg=[IO.File]::ReadAllText((Join-Path $src 'wp-config.php'))
 function Swap([string]$key,[string]$value){
   $pattern='(?m)^\s*define\s*\(\s*[''"]'+[regex]::Escape($key)+'[''"]\s*,\s*[''"][^''"]*[''"]\s*\)\s*;'
   if([regex]::Matches($script:cfg,$pattern).Count -ne 1){throw ('Missing one unique config constant '+$key)}
   if($value -notmatch '^[A-Za-z0-9_:/.\-]+$'){throw ('Bad candidate config value '+$key)}
   $script:cfg=[regex]::Replace($script:cfg,$pattern,("define('"+$key+"', '"+$value+"');"))
 }
 Swap 'DB_NAME' $db
 Swap 'DB_USER' $username
 Swap 'DB_PASSWORD' $password
 Swap 'DB_HOST' '127.0.0.1'
 Swap 'WP_HOME' $url
 Swap 'WP_SITEURL' $url
 Swap 'EH7_SOURCE_HEAD' $head
 $anchor="require_once ABSPATH . 'wp-settings.php';"
 if(!$cfg.Contains($anchor)){throw 'Cannot recognize WordPress config bootstrap'}
 $cfg=$cfg.Replace($anchor,"define('DISABLE_WP_CRON', true);"+[Environment]::NewLine+$anchor)
 [IO.File]::WriteAllText((Join-Path $dest 'wp-config.php'),$cfg,(New-Object System.Text.UTF8Encoding $false))
 $ht=@'
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /erp-uat-candidate/
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /erp-uat-candidate/index.php [L]
</IfModule>
'@
 [IO.File]::WriteAllText((Join-Path $dest '.htaccess'),$ht,(New-Object System.Text.UTF8Encoding $false))
 Write-Output ('PASS: candidate WordPress created at '+$url+' with Git '+$head.Substring(0,8)+' and DB '+$db)
 Write-Output 'Source-aware staging/seed markers in cloned database are NOT yet repinned'
} finally {
 Remove-Item -LiteralPath $adminFile -Force -ErrorAction SilentlyContinue
}
