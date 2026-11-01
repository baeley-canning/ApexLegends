$ErrorActionPreference = 'Continue'
$src = 'C:\Program Files\EA\AC\EAAntiCheat.GameService.exe'
$o = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p13_popup.txt'
if (Test-Path $o) { Remove-Item $o -Force }
function W($s) { $s | Add-Content -LiteralPath $o }

W ('=== p13 popup window dump ' + (Get-Date) + ' ===')
W ('src=' + $src + ' len=' + (Get-Item $src).Length)

$centers = @(17125050, 17116000, 17134000)
$fs = [System.IO.File]::Open($src, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
try {
  $len = $fs.Length
  foreach ($c in $centers) {
    $start = [Math]::Max(0, $c - 24000)
    $count = [Math]::Min(48000, $len - $start)
    $fs.Position = $start
    $buf = [byte[]]::new($count)
    [void]$fs.Read($buf, 0, $count)

    $ab = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $count; $i++) {
      $b = $buf[$i]
      if ($b -ge 32 -and $b -lt 127) { [void]$ab.Append([char]$b) } else { [void]$ab.Append('|') }
    }
    $ub = [System.Text.StringBuilder]::new()
    for ($i = 0; $i + 1 -lt $count; $i += 2) {
      $cp = [int]$buf[$i] + ([int]$buf[$i+1] -shl 8)
      if ($cp -ge 32 -and $cp -lt 127) { [void]$ub.Append([char]$cp) } else { [void]$ub.Append('|') }
    }
    W ''
    W ('########## center=' + $c + ' start=' + $start + ' count=' + $count + ' ##########')
    W '---- ASCII ----'
    W $ab.ToString()
    W '---- UTF16 ----'
    W $ub.ToString()
  }
}
finally { $fs.Close() }

# keyword lines only, for quick eyeballing
W ''
W '########## lines with keywords ##########'
Get-Content -LiteralPath $o | Where-Object { $_ -match 'Violation|Session|Error|error|code|0x|driver|Driver|kernel|integrity|please|attest|sign|Sign|boot|Boot|hyper|tamper|blocked' } |
  ForEach-Object { W ('KW: ' + $_) }
W ('=== DONE ' + (Get-Date) + ' ===')
