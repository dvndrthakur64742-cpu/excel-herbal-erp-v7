param(
  [Parameter(Mandatory=$true)][string]$SourceHead,
  [Parameter(Mandatory=$true)][string]$ArchivePath
)
$ErrorActionPreference='Stop'
if($SourceHead -cnotmatch '^[a-f0-9]{40}$'){throw 'Exact source SHA required.'}
$sourceZip=[System.IO.Path]::GetFullPath($ArchivePath)
if(-not(Test-Path -LiteralPath $sourceZip -PathType Leaf)){throw 'V8 certified ZIP missing.'}
if((Get-Item -LiteralPath $sourceZip).Length -gt 52428800){throw 'Web ZIP is above the 50 MiB limit.'}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[System.IO.Compression.ZipFile]::OpenRead($sourceZip)
try {
  $files=@{};$manifest=@{}
  $total=[long]0
  foreach($entry in $archive.Entries){
    $name=[string]$entry.FullName
    if(-not $name -or $name -match '(^/|\\|^[A-Za-z]:|(^|/)\.\.?(/|$))' -or $entry.Name -eq ''){
      throw ('Unsafe ZIP file: '+$name)
    }
    if($files.ContainsKey($name)){throw ('Duplicate ZIP file: '+$name)}
    $total+=[long]$entry.Length
    if($total -gt 104857600){throw 'Uncompressed ZIP exceeds 100 MiB'}
    $files[$name]=$entry
  }
  if(-not $files.ContainsKey('SHA256SUMS.txt')){throw 'Missing internal manifest.'}
  $stream=$files['SHA256SUMS.txt'].Open()
  $reader=New-Object System.IO.StreamReader($stream,[System.Text.Encoding]::UTF8)
  try{$contents=$reader.ReadToEnd()}finally{$reader.Dispose()}
  foreach($line in ($contents -split '[\r\n]+' | Where-Object { $_ -ne '' })){
    if($line -cnotmatch '^([a-f0-9]{64})  (.+)$'){throw 'Invalid manifest row.'}
    $hash=$Matches[1];$name=$Matches[2]
    if($name -eq 'SHA256SUMS.txt' -or -not $files.ContainsKey($name) -or $manifest.ContainsKey($name)){
      throw ('Missing/duplicate manifest file: '+$name)
    }
    $manifest[$name]=$hash
  }
  if($files.Count -ne ($manifest.Count+1)){throw 'ZIP and signed manifest file counts differ.'}
  foreach($required in @('index.html','main.dart.js','flutter_bootstrap.js','.last_build_id')){
    if(-not $manifest.ContainsKey($required)){throw ('Mandatory web file missing: '+$required)}
  }
  $sha=[System.Security.Cryptography.SHA256]::Create()
  try {
    foreach($name in @($manifest.Keys)){
      $part=$files[$name].Open()
      try{$observed=[BitConverter]::ToString($sha.ComputeHash($part)).Replace('-','').ToLowerInvariant()}
      finally{$part.Dispose()}
      if($observed -cne $manifest[$name]){throw ('ZIP source hash mismatch: '+$name)}
    }
  }finally{$sha.Dispose()}
  $idStream=$files['.last_build_id'].Open()
  $idReader=New-Object System.IO.StreamReader($idStream,[System.Text.Encoding]::ASCII)
  try{$id=$idReader.ReadToEnd().Trim()}finally{$idReader.Dispose()}
  if($id -cne $SourceHead){throw 'ZIP does not match the approved source HEAD.'}
  if($env:GITHUB_RUN_ID -notmatch '^\d+$'){throw 'GitHub run ID required.'}
  $attempt=if($env:GITHUB_RUN_ATTEMPT -match '^\d+$'){$env:GITHUB_RUN_ATTEMPT}else{'1'}
  $key=$SourceHead+'-run'+$env:GITHUB_RUN_ID+'-attempt'+$attempt+'-slot-v8-office-preview'
  $dir=Join-Path $env:USERPROFILE ('ERP7-Releases\uat-candidates\'+$key)
  $webDir=Join-Path $dir 'web'
  if(Test-Path -LiteralPath $dir){Remove-Item -LiteralPath $dir -Recurse -Force}
  New-Item -ItemType Directory -Path $webDir -Force | Out-Null
  $dest=Join-Path $dir 'Excel-Herbal-ERP-v7.4.0-Web-Candidate.zip'
  Copy-Item -LiteralPath $sourceZip -Destination $dest -Force
  $part=$files['main.dart.js'].Open()
  $main=Join-Path $webDir 'main.dart.js'
  $out=[System.IO.File]::Open($main,[System.IO.FileMode]::CreateNew)
  try{$part.CopyTo($out)}finally{$out.Dispose();$part.Dispose()}
  [System.IO.File]::WriteAllText((Join-Path $webDir 'SHA256SUMS.txt'),$contents,[System.Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText((Join-Path $webDir '.last_build_id'),$id+[Environment]::NewLine,[System.Text.Encoding]::ASCII)
  if((Get-FileHash -LiteralPath $main -Algorithm SHA256).Hash.ToLowerInvariant() -cne $manifest['main.dart.js']){
    throw 'Main JavaScript hash mismatch after staging.'
  }
  if((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $sourceZip -Algorithm SHA256).Hash){
    throw 'Copied ZIP bytes differ from validated original.'
  }
  Write-Host ('PASS ZIP entries source SHA-256 checked='+$manifest.Count)
  Write-Host ('PASS office_preview_source_head='+$SourceHead)
  Write-Host ('PASS office_preview_main_sha256='+$manifest['main.dart.js'])
  Write-Host 'PASS no_wasm_files_extracted_on_windows=true'
  Write-Host ('PASS staged_uat_candidate='+$dir)
}finally{$archive.Dispose()}
