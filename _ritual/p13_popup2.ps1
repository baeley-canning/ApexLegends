$ErrorActionPreference = 'Continue'
$src = 'C:\Program Files\EA\AC\EAAntiCheat.GameService.exe'
$o = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p13_popup.txt'

$sw = [System.IO.StreamWriter]::new($o, $false, [System.Text.Encoding]::UTF8)
function W($s) { $sw.WriteLine($s) }

W ('=== p13 popup window dump v2 ' + (Get-Date) + ' ===')
W ('src=' + $src + ' len=' + (Get-Item $src).Length)

$kwRe = 'Violation|Session|Error|code|0x|driver|rivers|kernel|integrity|please|Please|attest|sign|boot|Boot|hyper|tamper|blocked|root|cert|Certificate|policy|resides|physical|PHYSICAL'

$fs = [System.IO.File]::Open($src, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
try {
  $len = $fs.Length
  foreach ($c in @(17125050, 17050000, 17200000, 17300000)) {
    $start = [Math]::Max(0, $c - 20000)
    $count = [Math]::Min(40000, $len - $start)
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
    $asc = $ab.ToString() -replace '\|{2,}', ' ~ '
    $uni = $ub.ToString() -replace '\|{2,}', ' ~ '

    W ''
    W ('########## center=' + $c + ' ##########')
    W '---- ASCII ----'
    W $asc
    W '---- UTF16 ----'
    W $uni

    W ('---- keyword fragments around center=' + $c + ' ----')
    foreach ($frag in ($uni -split ' ~ ')) {
      if ($frag.Length -ge 4 -and $frag -match $kwRe) { W ('U: ' + $frag) }
    }
    foreach ($frag in ($asc -split ' ~ ')) {
      if ($frag.Length -ge 4 -and $frag -match $kwRe) { W ('A: ' + $frag) }
    }
  }
}
finally { $fs.Close() }

W ('=== DONE ' + (Get-Date) + ' ===')
$sw.Flush()
$sw.Close()
