# p270 — build the blind-typed elevated payload for disabling the WinRing0 driver.
# Emits a single ASCII line into p270_payload.txt, meant for `controlvm keyboardputfile`.
$ErrorActionPreference = 'Stop'

# Keep the inner script SHORT: keyboardputfile types it char by char, so every
# character is wall-clock time inside the ~4 min crash window of this guest.
$inner = @'
$s=gwmi win32_systemdriver|?{$_.PathName -match 'WinRing0'}|select -f 1
$n=$s.Name
sc.exe config $n start= disabled
sc.exe stop $n
$r=$LASTEXITCODE
sc.exe qc $n
"N=$n stop=$r"
'@

$b64  = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))
$line = "Start-Process powershell -Verb RunAs -ArgumentList '-NoExit -ExecutionPolicy Bypass -EncodedCommand $b64'"

$out = Join-Path $PSScriptRoot 'p270_payload.txt'
Set-Content -LiteralPath $out -Value $line -NoNewline -Encoding ASCII
"RESULT: wrote $out len=$($line.Length)"
"PREVIEW: $($line.Substring(0,[Math]::Min(70,$line.Length)))..."
