$ErrorActionPreference = 'SilentlyContinue'
$root = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$out  = Join-Path $root 'p11_phrase.txt'
function W { param([string]$t) $t | Out-File -FilePath $out -Append -Encoding utf8 }
"=== p11 phrase scan $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -FilePath $out -Encoding utf8

$terms = @(
  'unacceptable configuration','Security Violation','signing integrity','integrity checks must be enabled',
  'driver signing','test signing','testsigning','tampering','cheat-related','EA Javelin Anticheat',
  'unsigned driver','unacceptable policy','boot configuration','memory integrity','bcdedit','nointegritychecks'
)
$roots = @(
  'C:\Program Files\EA\AC',
  'C:\Program Files\EA Games\Apex',
  'C:\Program Files\Electronic Arts',
  'C:\Program Files (x86)\EasyAntiCheat_EOS',
  'C:\ProgramData\eaanticheat'
)
$seen = @{}

$files = @()
foreach ($r in $roots) { if (Test-Path -LiteralPath $r) { $files += Get-ChildItem -LiteralPath $r -Recurse -Force -File } }
W ('files to scan: ' + $files.Count)

foreach ($f in $files) {
  if ($f.Length -gt 400000000) { W ('SKIP too big: ' + $f.FullName); continue }
  W ('--- ' + $f.FullName + '  (' + $f.Length + ' bytes) ---')
  try { $b = [IO.File]::ReadAllBytes($f.FullName) } catch { W '  (read fail)'; continue }
  $pairs = @{ A = [Text.Encoding]::ASCII.GetString($b); W = [Text.Encoding]::Unicode.GetString($b) }
  foreach ($t in $terms) {
    foreach ($k in @('A', 'W')) {
      $txt = $pairs[$k]; $idx = 0; $n = 0
      while ($n -lt 20) {
        $i = $txt.IndexOf($t, $idx, [StringComparison]::OrdinalIgnoreCase)
        if ($i -lt 0) { break }
        $s = [Math]::Max(0, $i - 70); $len = [Math]::Min(200, $txt.Length - $s)
        $ctx = $txt.Substring($s, $len) -replace '[^\x20-\x7E]', ' '
        $ctx = $ctx -replace '\s{2,}', ' '
        $key = ($f.Name + '|' + $t + '|' + $k + '|' + $ctx)
        if (-not $seen.ContainsKey($key)) { $seen[$key] = 1; W ('  [' + $k + '] <' + $t + '> ... ' + $ctx + ' ...') }
        $idx = $i + $t.Length; $n++
      }
    }
  }
  $pairs = $null; $b = $null
}
W ''
W "=== p11 phrase done $(Get-Date -Format 'HH:mm:ss') ==="
