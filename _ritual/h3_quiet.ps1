# h3_quiet - take the box from "Apex running" back to the h1 pre-flight condition (no r5apex/EAAC/EADesktop).
#
# h1_dse_host aborts while any r5apex*/EAAntiCheat*/EADesktop process is alive, and the G1 sequence
# needs a fresh game launch by h2_gate - so the live session from the h2w proof has to be retired first.
# Host-only, no kernel/boot mutation.
#
# R3: pre-state and post-state both recorded, the post list is the readback and the only verdict.
# R4: nothing to restore - the end state (quiet) is the intended state; re-run safe when already quiet.
# Run: _ritual\h3_quiet.ps1 (self-elevates, one UAC - SYSTEM-owned EAAC needs the elevation) -> h3_quiet.txt / .summary.txt
$ErrorActionPreference = 'Continue'
$rit = $PSScriptRoot
$o   = Join-Path $rit 'h3_quiet.txt'
$sum = Join-Path $rit 'h3_quiet.summary.txt'
$RX  = 'r5apex|EAAntiCheat|eaanticheat|EADesktop'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if(-not $adm){ Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"')); exit }

function W($t){ $t | Add-Content -LiteralPath $o }
function Targets { @(Get-Process -EA SilentlyContinue | Where-Object { $_.ProcessName -match $RX }) }
function List { (@(Targets) | ForEach-Object { $_.ProcessName + '(' + $_.Id + ')' }) -join ',' }
function Drv { $s = ((& sc.exe query apexdrv 2>&1) -join ' '); if($s -match 'STATE\s+:\s+\d+\s+(\w+)'){ $Matches[1] } else { 'ABSENT' } }

"=== h3_quiet $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') pid=$PID admin=$adm ===" | Set-Content -LiteralPath $o
W ''; W '## pre-state'
$pre = List; W ('  alive=[' + $pre + ']  apexdrv=' + (Drv))

# graceful first: CloseMainWindow posts WM_CLOSE, Apex saves its state and EAAC tears down cleanly
$n = 0
foreach($p in (Targets)){ $n += [int]$(try { $p.CloseMainWindow() } catch { $false }) }
W ('  close requested on ' + $n + ' process(es)')
foreach($i in 1..20){ Start-Sleep -Seconds 1; if(-not (Targets).Count){ break } }
W ('  after 20 s grace=[' + (List) + ']')

# force whatever is left, then give EAAC its own teardown window
foreach($p in (Targets)){ W ('  kill ' + $p.ProcessName + '(' + $p.Id + ')'); Stop-Process -Id $p.Id -Force -EA SilentlyContinue }
foreach($i in 1..30){ Start-Sleep -Seconds 1; if(-not (Targets).Count){ break } }
foreach($p in (Targets)){ W ('  kill(late) ' + $p.ProcessName + '(' + $p.Id + ')'); Stop-Process -Id $p.Id -Force -EA SilentlyContinue }
Start-Sleep -Seconds 2

W ''; W '## post-state (readback = verdict)'
$post = List; W ('  alive=[' + $post + ']  apexdrv=' + (Drv))
W ('  EAAntiCheatService=' + ((Get-Service EAAntiCheatService -EA SilentlyContinue).Status))
W ''; W '=== VERDICT ==='
if($post -eq '' -and (Drv) -eq 'STOPPED'){ W 'RESULT: QUIET - no r5apex/EAAC/EADesktop process, driver STOPPED. h1 pre-flight condition met.' }
else { W ('RESULT: NOT QUIET - alive=[' + $post + '] apexdrv=' + (Drv) + '. Clear these before h1.') }
W ('-- h3_quiet END ' + (Get-Date -f 'HH:mm:ss') + ' --')
(@('VERDICT=' + $(if($post -eq '' -and (Drv) -eq 'STOPPED'){'QUIET'}else{'NOT-QUIET'}),'pre=[' + $pre + ']','post=[' + $post + ']','end=' + (Get-Date -f 'dd/MM HH:mm:ss')) -join ' ') | Set-Content -LiteralPath $sum
