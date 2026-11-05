# p270_b.ps1 - PART 2 (v2): inventory, rename kdu.exe, write+show revert file, read-back.
# Command list built from a here-string and split on newlines, so no -f/comma pitfalls.
$type = Join-Path $PSScriptRoot 'vm_type.ps1'
$shot = Join-Path $PSScriptRoot 'shot.ps1'
$log  = Join-Path $PSScriptRoot 'p270_b.log'
function L($s) { Add-Content -LiteralPath $log -Value ((Get-Date -f 'HH:mm:ss') + ' ' + $s) }

$d1 = 'C:\Users\Public\p37'
$d2 = 'C:\Users\vboxuser\AppData\Local\Temp\p37vm'
$T  = 'HKLM\T\ControlSet001\Services'

$block = @'
dir D1
dir D2
ren D1\kdu.exe kdu.exe.bak
set F=C:\wr_revert.txt
echo p269 driver kill - Win11-Test2 - 2026-11-05 > %F%
echo. >> %F%
echo KILLED BY RENAME (durable switch): >> %F%
echo   D1\run.cmd  ^(task p37tick action; task itself still enabled^) >> %F%
echo   loader is 2-stage: run.cmd -> cur.ps1 re-fetches every payload by hash >> %F%
echo. >> %F%
echo SERVICES SET TO START 0x4 BY US ^(was 0x3^): >> %F%
echo   apexdrv  ImagePath \??\D1\zapexdrv.sys >> %F%
echo   gdrv3    ImagePath \??\D2\gdrv3.sys >> %F%
echo. >> %F%
echo FILES RENAMED TO ^*.bak in D1 : run.cmd WinRing0x64.sys zapexdrv.sys kdu.exe >> %F%
echo FILES RENAMED TO ^*.bak in D2 : gdrv3.sys >> %F%
echo NOTE: grdev3.sys was NOT present in p37 at kill time. >> %F%
echo. >> %F%
echo RESTORE: rename each ^*.bak back, then set Start back to 3: >> %F%
echo   reg add T\apexdrv /v Start /t REG_DWORD /d 3 /f >> %F%
echo   reg add T\gdrv3 /v Start /t REG_DWORD /d 3 /f >> %F%
echo. >> %F%
echo Unload hive before exit: reg unload HKLM\T >> %F%
type %F%
reg query T\apexdrv
reg query T\gdrv3
dir D1\*.bak
dir D2\*.bak
'@

$lines = @($block -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
$cmds = foreach ($l in $lines) {
  $l.Replace('D1', $d1).Replace('D2', $d2).Replace('T\', $T + '\')
}

L ('count=' + @($cmds).Count)
$i = 1
foreach ($c in $cmds) {
  L ("type: " + $c)
  & powershell -NoProfile -ExecutionPolicy Bypass -File $type -Seq $c
  & powershell -NoProfile -ExecutionPolicy Bypass -File $type -Seq enter
  Start-Sleep -Milliseconds 1100
  & powershell -NoProfile -ExecutionPolicy Bypass -File $shot ('p270b_{0}' -f $i)
  L ('shot p270b_{0}' -f $i)
  $i++
  Start-Sleep -Milliseconds 300
}
L 'PART2 done'

