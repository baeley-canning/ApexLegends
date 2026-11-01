$ErrorActionPreference = 'SilentlyContinue'
$root = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$out  = Join-Path $root 'p12_phrase.txt'
$log  = Join-Path $root 'p12_phrase_status.txt'
function W { param([string]$t) $t | Out-File -FilePath $out -Append -Encoding utf8 }
function S { param([string]$t) $t | Out-File -FilePath $log -Append -Encoding utf8 }
"=== p12 phrase scan START $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -FilePath $out -Encoding utf8

function FindAll {
  param([byte[]]$hay, [byte[]]$needle, [int]$max = 8)
  $res = New-Object System.Collections.ArrayList
  if ($null -eq $hay -or $hay.Length -lt $needle.Length) { return $res }
  $pos = 0
  while ($pos -le $hay.Length - $needle.Length) {
    $i = [Array]::IndexOf($hay, $needle[0], $pos)
    if ($i -lt 0) { break }
    $ok = $true
    for ($j = 1; $j -lt $needle.Length; $j++) { if ($hay[$i + $j] -ne $needle[$j]) { $ok = $false; break } }
    if ($ok) { [void]$res.Add($i); if ($res.Count -ge $max) { break } }
    $pos = $i + 1
  }
  return ,$res
}

function Dump {
  param([byte[]]$b, [int]$hit, [string]$tag)
  $lo = [Math]::Max(0, $hit - 1400); if ($lo % 2 -ne 0) { $lo++ }
  $hi = [Math]::Min($b.Length - 1, $hit + 1400)
  if ($hi -le $lo) { return }
  $win = New-Object byte[] ($hi - $lo + 1)
  [Array]::Copy($b, $lo, $win, 0, $win.Length)
  foreach ($enc in @('W', 'A')) {
    $s = if ($enc -eq 'W') { [Text.Encoding]::Unicode.GetString($win) } else { [Text.Encoding]::ASCII.GetString($win) }
    $runs = [regex]::Matches($s, '[\x20-\x7E\r\n]{5,}') | ForEach-Object { ($_.Value -replace '\s+', ' ') } | Where-Object { $_.Length -ge 5 } | Select-Object -Unique
    if ($runs) { W ('    [' + $enc + ' win ' + $lo + '-' + $hi + '] ' + (($runs | Select-Object -First 90) -join ' ~ ')) }
  }
}

$dirs = @('C:\Program Files\EA\AC', 'C:\Program Files\EA Games\Apex')
$files = @()
foreach ($d in $dirs) {
  if (-not (Test-Path -LiteralPath $d)) { continue }
  $files += Get-ChildItem -LiteralPath $d -Force -File | Where-Object { $_.Name -match '(?i)GameService|preloader|^EAAntiCheat|^r5apex_dx12|launcher' } | ForEach-Object { $_.FullName }
}
$files += @('C:\Windows\System32\drivers\eaanticheat.sys', 'C:\Windows\System32\drivers\apexdrv.sys')
$files = $files | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

$needles = @{
  'POPUP-victim'        = 'Security Violation'
  'SessionID'           = 'Session ID'
  'unacceptable'        = 'unacceptable config'
  'unacceptable-raw'    = 'unacceptable'
  'integrity'           = 'integrity'
  'tamper'              = 'tampering'
  'driver'              = 'driver'
  'kernel'              = 'kernel'
  'attest'              = 'attestation'
  'test-signing'        = 'test signing'
  'testsigning2'        = 'testsigning'
  'bcdedit'             = 'bcdedit'
  'hypervisor'          = 'hypervisor'
  'secureboot'          = 'secure boot'
  'virt'                = 'virtualization'
  'driverfile'          = 'eaanticheat.sys'
  'skyfall'             = 'skyfall'
  'jav-driver'          = 'javelin.sys'
  'suspicious'          = 'suspicious'
  'whql'                = 'WHQL'
  'signature'           = 'Signature'
  'openservice'         = 'OpenService'
  'filterman'           = 'FltRegisterFilter'
  'loader'              = 'ntldr'
  'conflict'            = 'conflict'
  'please'              = 'Please'
  'exception-code'      = '0xFFFF'
}

W ('candidates: ' + $files.Count)
S ("start $(Get-Date -Format 'HH:mm:ss') candidates=" + $files.Count)

foreach ($f in $files) {
  W ''
  W ('================ ' + $f + ' ================')
  S ("reading $f")
  $b = $null
  try { $b = [IO.File]::ReadAllBytes($f) } catch { W '  (read fail)'; continue }
  W ('size ' + $b.Length)
  foreach ($k in ($needles.Keys | Sort-Object)) {
    $n = $needles[$k]
    foreach ($mode in @('W', 'A')) {
      $needle = if ($mode -eq 'W') { [Text.Encoding]::Unicode.GetBytes($n) } else { [Text.Encoding]::ASCII.GetBytes($n) }
      $hits = FindAll -hay $b -needle $needle -max 6
      if ($hits.Count -eq 0) { continue }
      W ('  ### ' + $k + " ['" + $n + "' $mode] hits=" + $hits.Count + ' at ' + (($hits) -join ','))
      foreach ($h in $hits) { Dump -b $b -hit $h -tag $k }
    }
  }
  $b = $null
  S ("done $f  $(Get-Date -Format 'HH:mm:ss')")
}
W ''
W "=== p12 phrase scan DONE $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
S ("DONE $(Get-Date -Format 'HH:mm:ss')")
