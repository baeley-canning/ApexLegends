# p271_exit.ps1 - leave the WinRE recovery shell: `exit`, watch what the recovery UI does,
# navigate back to the top-level menu with Esc x2 + Enter, and hard-reset only as last resort.
# Reversible: rollback point is snapshot pre-h268. Detached; terminal kill cannot truncate it.
$type = Join-Path $PSScriptRoot 'vm_type.ps1'
$shot = Join-Path $PSScriptRoot 'shot.ps1'
$log  = Join-Path $PSScriptRoot 'p271_exit.log'
$VB   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM   = 'Win11-Test2'
function L($s) { Add-Content -LiteralPath $log -Value ((Get-Date -f 'HH:mm:ss') + ' ' + $s) }
function St { ((& $VB showvminfo $VM --machinereadable 2>&1) | Select-String '^VMState=' | ForEach-Object { $_.Line.Trim() }) }

L 'start'
L ('pre ' + (St))
& powershell -NoProfile -ExecutionPolicy Bypass -File $type -Seq exit
Start-Sleep -Milliseconds 500
& powershell -NoProfile -ExecutionPolicy Bypass -File $type -Seq enter
L 'typed: exit<enter>'

# t+2.5 / t+5 : what did the recovery UI do
Start-Sleep -Milliseconds 2000
& powershell -NoProfile -ExecutionPolicy Bypass -File $shot 'p271_1' | Out-Null
L 'shot p271_1'
Start-Sleep -Milliseconds 2500
& powershell -NoProfile -ExecutionPolicy Bypass -File $shot 'p271_2' | Out-Null
L 'shot p271_2'

# poll to t+40
$i = 3
$menu = $true
foreach ($n in 1..4) {
  Start-Sleep -Seconds 10
  $s = St
  L ('poll ' + $n + ' ' + $s)
  & powershell -NoProfile -ExecutionPolicy Bypass -File $shot ('p271_{0}' -f $i) | Out-Null
  L ('shot p271_' + $i)
  $i++
  if ($s -match 'fromstate|powersoff|poweroff|GURU|aborted') { $menu = $false; break }
}

# t+45 : still on a recovery menu -> Esc back to Advanced options -> Esc to Choose-an-option -> Enter (Continue)
if ($menu) {
  L 'navigate: esc esc enter'
  & powershell -NoProfile -ExecutionPolicy Bypass -File $type -Seq esc
  Start-Sleep -Milliseconds 900
  & powershell -NoProfile -ExecutionPolicy Bypass -File $type -Seq esc
  Start-Sleep -Milliseconds 900
  & powershell -NoProfile -ExecutionPolicy Bypass -File $shot 'p271_b1' | Out-Null
  L 'shot p271_b1'
  & powershell -NoProfile -ExecutionPolicy Bypass -File $type -Seq enter
  L 'entered'
  Start-Sleep -Milliseconds 4000
  & powershell -NoProfile -ExecutionPolicy Bypass -File $shot 'p271_b2' | Out-Null
  L 'shot p271_b2'
}

# watch for 60 s: a normal boot shows a spinner / BIOS-less Windows splash and VMState stays running
foreach ($n in 1..6) {
  Start-Sleep -Seconds 10
  L ('watch ' + $n + ' ' + (St))
  & powershell -NoProfile -ExecutionPolicy Bypass -File $shot ('p271_w{0}' -f $n) | Out-Null
  L ('shot p271_w' + $n)
}

$s = St
L ('after-watch ' + $s)
# last resort: hard reset (p269-proven to land on a normal boot; one-time WinRE boot is consumed)
if ($s -notmatch 'running') { L ('state not running -> startvm'); (& $VB startvm $VM --type headless 2>&1) | ForEach-Object { L ('  ' + $_) } }
else {
  L 'still running -> liveness check via shot only; if boot is stuck a reset is the next tick, not taken here'
}
Start-Sleep -Seconds 3
& powershell -NoProfile -ExecutionPolicy Bypass -File $shot 'p271_final' | Out-Null
L 'shot p271_final'
L 'EXIT-PHASE done'
