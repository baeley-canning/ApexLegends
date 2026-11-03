# h2w2 - post-gate proof that DSE is genuinely restored: stop + start apexdrv must FAIL with 577.
#
# 577 = ERROR_INVALID_IMAGE_HASH: the loader refused an unsigned image because DSE is armed again.
# If it appears, the only reason the driver is RUNNING is the open window h1 created, and h1b's
# byte-exact 0x16 readback is confirmed from the other side. If start returns 0, DSE is still open
# and the gate proves nothing about a normal boot - that is the FAIL case.
#
# Mutation: service stop/start only. Nothing to write back; the end state is recorded instead of
# restored (R4: driver ends STOPPED unless this script retires it to RUNNING because 577 did not fire).
# Re-run safe: if the driver is already STOPPED the stop is skipped.
# Run: _ritual\h2w2_577.ps1 (self-elevates, one UAC)  ->  writes h2w2_577.txt / .summary.txt
$ErrorActionPreference = 'Continue'
$rit = $PSScriptRoot
$o   = Join-Path $rit 'h2w2_577.txt'
$sum = Join-Path $rit 'h2w2_577.summary.txt'
$svc = 'apexdrv'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if(-not $adm){ Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"')); exit }

function W($t){ $t | Add-Content -LiteralPath $o }
function St { $s = ((& sc.exe query $svc 2>&1) -join ' '); if($s -match 'STATE\s+:\s+\d+\s+(\w+)'){ $Matches[1] } else { 'ABSENT' } }
function LastExit { $s = ((& sc.exe query $svc 2>&1) -join ' '); if($s -match 'WIN32_EXIT_CODE\s+:\s+(\d+)'){ $Matches[1] } else { 'n/a' } }

"=== h2w2 DSE-RESTORED PROOF $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') pid=$PID admin=$adm ===" | Set-Content -LiteralPath $o
W '  premise: h1b_host.txt restored g_CiOptions to the boot value 0x16 with readback match=True.'
W ''
W '## pre-state'
W ('  driver=' + (St) + '  lastExit=' + (LastExit))
$g = @(Get-Process r5apex_dx12 -EA SilentlyContinue)
W ('  game=' + $(if($g.Count){ 'ALIVE pid=' + $g[0].Id + ' up=' + [int](((Get-Date)-$g[0].StartTime).TotalMinutes) + 'min' } else { 'not running' }))
$b4 = Join-Path $rit 'h1b_host.txt'
if(Test-Path -LiteralPath $b4){ W ('  h1b proof: ' + (((Get-Content -LiteralPath $b4 | Select-String 'match=') -join ' ')).Trim()) }
else { W '  h1b proof MISSING - verdict is weaker' }
W ('  blocklist=' + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config' -EA SilentlyContinue).VulnerableDriverBlocklistEnable)

$pre = St
if($pre -eq 'RUNNING'){
  W ''; W '## step 1: sc stop (expect 0)'
  $null = & sc.exe stop $svc 2>&1 | ForEach-Object { W ('  | ' + $_) }
  Start-Sleep -Seconds 2
  $stopNow = St; W ('  state after stop=' + $stopNow)
} else { $stopNow = $pre; W ''; W ('## step 1 skipped, driver already ' + $pre) }

W ''; W '## step 2: sc start (expect 577 = DSE armed)'
$out = (& sc.exe start $svc 2>&1); $rc = $LASTEXITCODE
foreach($l in $out){ W ('  | ' + $l) }
W ('  start rc=' + $rc)
Start-Sleep -Seconds 1
$after = St; $le = LastExit
W ('  state after start=' + $after + '  lastExit=' + $le)

W ''; W '=== VERDICT ==='
$v = 'FAIL'
if($rc -eq 577){ $v = 'PASS' }
W $(if($rc -eq 577){ 'RESULT: PASS - stop rc 0, start rc 577. DSE is genuinely restored; apexdrv only loads inside the open window (h1) and h1b''s 0x16 readback is confirmed. Milestone 1 gate closed.' } else { 'RESULT: FAIL - start rc=' + $rc + ' (not 577): DSE is still open, or the service/bin changed. Do not claim the gate.' })
W ('  end state: driver=' + $after + ' (expected STOPPED)  game=' + $(if(@(Get-Process r5apex_dx12 -EA SilentlyContinue).Count){'alive'}else{'gone'}))
W ('-- h2w2 END ' + (Get-Date -f 'HH:mm:ss') + ' --')
(@('VERDICT=' + $v,'startRc=' + $rc,'driverEnd=' + $after,'lastExit=' + $le,'end=' + (Get-Date -f 'dd/MM HH:mm:ss')) -join ' ') | Set-Content -LiteralPath $sum
