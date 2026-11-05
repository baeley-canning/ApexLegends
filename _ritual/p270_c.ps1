# p270_c.ps1 - PART 3 (final): .bak the stage-2-only payloads, append revert, unload hive.
$type = Join-Path $PSScriptRoot 'vm_type.ps1'
$shot = Join-Path $PSScriptRoot 'shot.ps1'
$log  = Join-Path $PSScriptRoot 'p270_c.log'
function L($s) { Add-Content -LiteralPath $log -Value ((Get-Date -f 'HH:mm:ss') + ' ' + $s) }

$block = @'
dir C:\Users\Public\p37\*.sys
ren C:\Users\Public\p37\gdrv3.sys gdrv3.sys.bak
ren C:\Users\Public\p37\apexdrv_v3.sys apexdrv_v3.sys.bak
ren C:\Users\Public\p37\cur.ps1 cur.ps1.bak
echo ALSO RENAMED ^(stage-2 payloads; not referenced by any service ImagePath^): p37\gdrv3.sys apexdrv_v3.sys cur.ps1 >> C:\wr_revert.txt
type C:\wr_revert.txt
dir C:\Users\Public\p37\*.bak
reg unload HKLM\T
reg query HKLM\T
'@

$lines = @($block -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
L ('count=' + $lines.Count)
$i = 1
foreach ($c in $lines) {
  L ("type: " + $c)
  & powershell -NoProfile -ExecutionPolicy Bypass -File $type -Seq $c
  & powershell -NoProfile -ExecutionPolicy Bypass -File $type -Seq enter
  Start-Sleep -Milliseconds 1100
  & powershell -NoProfile -ExecutionPolicy Bypass -File $shot ('p270c_{0}' -f $i)
  L ('shot p270c_{0}' -f $i)
  $i++
  Start-Sleep -Milliseconds 300
}
L 'PART3 done'
