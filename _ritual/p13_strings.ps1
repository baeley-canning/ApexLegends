param([string]$Path, [string]$Tag)
$ErrorActionPreference = 'Continue'
$r = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$o = Join-Path $r ("p13_str_$Tag.txt")
function W($s) { $s | Add-Content -LiteralPath $o }
if (Test-Path $o) { Remove-Item $o -Force }
W ('=== p13 strings ' + $Path + ' | ' + (Get-Date) + ' ===')
$set = New-Object 'System.Collections.Generic.HashSet[string]'
$chunk = 8mb
$buf = New-Object byte[] ($chunk + 2)
$fs = [System.IO.File]::OpenRead($Path)
$carryA = ''
$carryU = ''
while (($n = $fs.Read($buf, 0, $chunk)) -gt 0) {
  if (($n % 2) -eq 1) { if ($fs.Read($buf, $n, 1) -gt 0) { $n = $n + 1 } }
  $a = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
  $w = [Text.Encoding]::Unicode.GetString($buf, 0, $n)
  foreach ($pair in @(@($carryA, $a), @($carryU, $w))) {
    $txt = $pair[0] + $pair[1]
    foreach ($m in [regex]::Matches($txt, '[\x20-\x7E]{6,}')) { [void]$set.Add($m.Value) }
  }
  $carryA = $a.Substring([Math]::Max(0, $a.Length - 24))
  $carryU = $w.Substring([Math]::Max(0, $w.Length - 24))
}
$fs.Close()
W ('unique 6+ char strings: ' + $set.Count)
$kw = $set | Where-Object { $_ -match '(?i)unacceptable|integrity|attest|signing|signatur|policy|secure.?boot|testsign|test.?sign|hvci|vbs|certificat|javelin|skyfall|violation|anticheat|tamper|reboot|whql|attestation' } | Sort-Object -Unique
W ('keyword hits: ' + @($kw).Count)
W ''
foreach ($s in $kw) { W $s }
W ''
W ('=== DONE keyword phase ' + (Get-Date) + ' ===')
$set | Sort-Object | Set-Content -LiteralPath (Join-Path $r ("p13_strall_$Tag.txt"))
W ('=== DONE full dump ' + (Get-Date) + ' ===')
