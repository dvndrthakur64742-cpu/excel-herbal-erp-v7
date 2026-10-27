param(
  [Parameter(Mandatory=$true)][string]$SourceHead,
  [Parameter(Mandatory=$true)][string]$TransportDir,
  [Parameter(Mandatory=$true)][string]$OutputZip
)
$ErrorActionPreference='Stop'
if($SourceHead -cnotmatch '^[a-f0-9]{40}$'){throw 'Exact source SHA required.'}
$manifestFile=Join-Path $TransportDir 'transport-sha256.txt'
if(-not(Test-Path -LiteralPath $manifestFile -PathType Leaf)){throw 'GitHub text transport manifest missing.'}
$rows=@(Get-Content -LiteralPath $manifestFile)
if($rows.Count -ne 4){throw 'Transport manifest must have 4 exact lines.'}
if($rows[0] -cnotmatch '^SOURCE ([a-f0-9]{40})$'){throw 'Transport manifest invalid source.'}
$source=$Matches[1]
if($source -cne $SourceHead){throw 'Source-head mismatch in transport.'}
if($rows[1] -cnotmatch '^ZIP_SHA256 ([a-f0-9]{64})$'){throw 'Transport manifest invalid ZIP SHA-256.'}
$expectedHash=$Matches[1]
if($rows[2] -cnotmatch '^ZIP_BYTES ([0-9]+)$'){throw 'Transport manifest invalid byte count.'}
$expectedBytes=[long]$Matches[1]
if($expectedBytes -le 0 -or $expectedBytes -gt 52428800){throw 'ZIP transport size out of bounds.'}
if($rows[3] -cnotmatch '^CHUNKS ([0-9]+)$'){throw 'Transport manifest invalid chunk count.'}
$count=[int]$Matches[1]
if($count -le 0 -or $count -gt 200){throw 'Transport chunk count out of bounds.'}
$chunks=@(Get-ChildItem -LiteralPath $TransportDir -File -Filter 'part-*.txt')
if($chunks.Count -ne $count){throw 'Transport chunk file count mismatch.'}
$extra=@(Get-ChildItem -LiteralPath $TransportDir -File | Where-Object {
  $_.Name -ne 'transport-sha256.txt' -and $_.Name -notmatch '^part-[0-9]{4}\.txt$'
})
if($extra.Count -gt 0){throw 'Unexpected file in immutable ZIP transport.'}
$parent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($OutputZip))
if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force | Out-Null}
if(Test-Path -LiteralPath $OutputZip){Remove-Item -LiteralPath $OutputZip -Force}
$out=[IO.File]::Open($OutputZip,[IO.FileMode]::CreateNew)
try{
  for($i=0;$i -lt $count;$i++){
    $name=('part-{0:D4}.txt' -f $i)
    $file=Join-Path $TransportDir $name
    if(-not(Test-Path -LiteralPath $file -PathType Leaf)){throw ('Transport chunk missing: '+$name)}
    $base64=[IO.File]::ReadAllText($file,[Text.Encoding]::ASCII).Trim()
    if($base64 -cnotmatch '^[A-Za-z0-9+/]+={0,2}$'){throw ('Corrupted base64 transport chunk: '+$name)}
    $bytes=[Convert]::FromBase64String($base64)
    $out.Write($bytes,0,$bytes.Length)
  }
}finally{$out.Dispose()}
$size=(Get-Item -LiteralPath $OutputZip).Length
if($size -ne $expectedBytes){throw ('Reassembled WordPress ZIP size mismatch: '+$size)}
$sha=(Get-FileHash -LiteralPath $OutputZip -Algorithm SHA256).Hash.ToLowerInvariant()
if($sha -cne $expectedHash){throw 'Reassembled WordPress ZIP SHA-256 mismatch.'}
Write-Host ('PASS original_linux_nested_zip_sha256='+$sha)
Write-Host ('PASS verified_reassembled_zip_bytes='+$size+' chunks='+$count)
