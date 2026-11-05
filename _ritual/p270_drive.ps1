# p270_drive.ps1 - PART 1: flush pending line, then apply the kill set to WinRE cmd.
# Launched detached (Start-Process -WindowStyle Hidden) so a terminal kill cannot truncate it.
$type = Join-Path $PSScriptRoot 'vm_type.ps1'
$shot = Join-Path $PSScriptRoot 'shot.ps1'
$log  = Join-Path $PSScriptRoot 'p270_drive.log'
function L($s) { Add-Content -LiteralPath $log -Value ((Get-Date -f 'HH:mm:ss') + ' ' + $s) }

$T = 'HKLM\T\ControlSet001\Services'

$cmds = @(
  ('reg add {0}\apexdrv /v Start /t REG_DWORD /d 4 /f' -f $T),
  ('reg add {0}\gdrv3 /v Start /t REG_DWORD /d 4 /f' -f $T),
  'ren C:\Users\Public\p37\WinRing0x64.sys WinRing0x64.sys.bak',
  'ren C:\Users\Public\p37\zapexdrv.sys zapexdrv.sys.bak',
  'ren C:\Users\Public\p37\grdev3.sys grdev3.sys.bak',
  'ren C:\Users\vboxuser\AppData\Local\Temp\p37vm\gdrv3.sys gdrv3.sys.bak',
  'dir C:\Users\Public\p37\*.bak'
)

L 'start'
# flush whatever half-typed line is on the WinRE console
& powershell -NoProfile -ExecutionPolicy Bypass -File $type -Seq enter
Start-Sleep -Milliseconds 800

$i = 91
foreach ($c in $cmds) {
  L ("type: " + $c)
  & powershell -NoProfile -ExecutionPolicy Bypass -File $type -Seq $c
  & powershell -NoProfile -ExecutionPolicy Bypass -File $type -Seq enter
  Start-Sleep -Milliseconds 1200
  $p = Join-Path $PSScriptRoot ("p270_{0}.png" -f $i)
  & powershell -NoProfile -ExecutionPolicy Bypass -File $shot ('p270_{0}' -f $i)
  L ("shot: " + $p)
  $i++
  Start-Sleep -Milliseconds 400
}
L 'PART1 done'
