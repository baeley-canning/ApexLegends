# h2 - G1 COEXISTENCE GATE (host, milestone 1 close-out).
#
# Runs the game for 1800 s with apexdrv RUNNING (loaded by h1 under a restored DSE) and watches for
# any Javelin refusal. 1 s process poll, refusal events captured verbatim as they appear, 10 s state
# snapshots, stops 20 s after a death. GREEN = game alive the whole window AND zero refusal events.
#
# Driver is left RUNNING and DSE restored - the 577 stop/start proof is a separate deliberate step
# AFTER this gate (see the NEXT lines in the log).
#
# Run: _ritual\run_h2.cmd  (registers a HIGHEST scheduled task, so console teardown cannot kill it)
# Writes: _ritual\h2_gate.txt , _ritual\h2_gate.summary.txt
param([int]$WinSec = 1800, [int]$BootSec = 240)
$ErrorActionPreference = 'Continue'
$rit  = $PSScriptRoot
$o    = Join-Path $rit 'h2_gate.txt'
$sumF = Join-Path $rit 'h2_gate.summary.txt'
$svc  = 'apexdrv'
$exe  = 'C:\Program Files\EA Games\Apex\r5apex_dx12.exe'
$EAD  = @(Get-ChildItem 'C:\Program Files\Electronic Arts' -Recurse -Filter 'EADesktop.exe' -EA SilentlyContinue |
          Where-Object { $_.FullName -notmatch 'compatibility32' } | Select-Object -First 1 -Expand FullName)
$adm  = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if(-not $adm){
  Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-WinSec',"$WinSec",'-BootSec',"$BootSec")
  exit
}
$dup = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'h2_gate' -and $_.ProcessId -ne $PID })
if($dup.Count){ foreach($d in $dup){ Stop-Process -Id $d.ProcessId -Force -EA SilentlyContinue }; Start-Sleep -Seconds 2 }

function W($t){ $t | Add-Content -LiteralPath $o }
function DrvRunning { (((& sc.exe query $svc 2>&1) -join ' ') -match 'STATE\s+:\s+4\s+RUNNING') }
function SvcState($n){ $s = ((& sc.exe query $n 2>&1) -join ' '); if($s -match 'STATE\s+:\s+\d+\s+(\w+)'){ $Matches[1] } else { 'ABSENT' } }
function Short($m){ $c = ($m -replace '\s+',' ').Trim(); $c.Substring(0,[Math]::Min(300,$c.Length)) }
function IsGame($p){ if($p.ProcessName -match 'r5apex|baeley'){ return $true }; $pt=''; try { $pt=$p.Path } catch {}; return [bool]($pt -like 'C:\Program Files\EA Games\Apex\*') }
function GetGame { $a=@(Get-Process -EA SilentlyContinue | Where-Object { IsGame $_ }); if(-not $a.Count){ return $null }; $g=@($a | Where-Object { $_.ProcessName -match 'r5apex|baeley' }); if($g.Count){ return $g[0] }; return $a[0] }
function GameSet { (@(Get-Process -EA SilentlyContinue | Where-Object { IsGame $_ }) | ForEach-Object { $_.ProcessName + '(' + $_.Id + ')' }) -join ',' }
function GetEvents([datetime]$since){
  $hits = @()
  foreach($lg in 'Application','System'){
    $ev = @(Get-WinEvent -FilterHashtable @{LogName=$lg; StartTime=$since} -EA SilentlyContinue |
            Where-Object { ($_.Message -match $RX) -or ($_.ProviderName -match 'Application Popup' -and $_.Id -eq 26) })
    foreach($e in $ev){ if(-not $global:seen.ContainsKey($e.RecordId)){ $global:seen[$e.RecordId] = 1; $hits += $e } }
  }
  return $hits
}

# every refusal family we have seen: p27 BCD/popup strings + p34 in-game panel text + AC service faults
$RX = 'Security Violation|must be disabled to start|signing integrity checks must be enabled|unacceptable configuration|AntiCheat|Javelin|integrity check failed|Untrusted system file|incompatible'
$global:seen = @{}

# ---- pre-flight ---------------------------------------------------------------
"=== h2 G1 COEXISTENCE GATE $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') pid=$PID host=$env:COMPUTERNAME win=${WinSec}s ===" | Set-Content -LiteralPath $o
W ''; W '########## A: pre-flight (abort on any FAIL; nothing is launched until all pass) ##########'
$fail = 0
if(DrvRunning){ W '  pass: apexdrv RUNNING' } else { $fail++; W '  FAIL: apexdrv is not RUNNING (run h1 first)' }
# gate on the file the SERVICE maps: `sc qc apexdrv` binPath is \??\C:\apexdrv.sys, so System32\drivers
# (empty on this box) would report MISSING and abort. Hash pin follows the staged v16 build.
$drvBin = 'C:\apexdrv.sys'
$h = (Get-FileHash -LiteralPath $drvBin -Algorithm SHA256 -EA SilentlyContinue).Hash
if($h -like 'A303EFB3AD268DF5*'){ W ('  pass: binPath hash ' + $h.Substring(0,16) + ' = pinned v16 build') } else { $fail++; W ('  FAIL: binPath hash ' + $h) }
$bl = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config' -Name VulnerableDriverBlocklistEnable -EA SilentlyContinue).VulnerableDriverBlocklistEnable
if($bl -eq 0){ W '  pass: blocklist disabled' } else { $fail++; W ('  FAIL: blocklist = ' + $bl) }
$hv = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
$ssr = @((Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -EA SilentlyContinue).SecurityServicesRunning)
if($ssr -contains 1){ $fail++; W ('  FAIL: HVCI running (' + ($ssr -join ',') + ')') } else { W ('  pass: no HVCI (HV present=' + $hv + ', SecurityServicesRunning=' + ($ssr -join ',') + ')') }
$ssot = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions -EA SilentlyContinue).SystemStartOptions
W ('  info: SystemStartOptions = [' + $ssot + ']  (must NOT contain TESTSIGNING)')
if($ssot -match 'TESTSIGNING'){ $fail++; W '  FAIL: kernel booted with TESTSIGNING' }
if(Test-Path -LiteralPath $exe){ W '  pass: game exe present' } else { $fail++; W ('  FAIL: missing ' + $exe) }
$pre = GameSet
if($pre){ $fail++; W ('  FAIL: game process already alive: ' + $pre) } else { W '  pass: no game process alive' }
W ('  info: gdrv3=' + (SvcState 'gdrv3') + '  DBUtilDrv2=' + (SvcState 'DBUtilDrv2'))
W ('  info: popup baseline (6 h) = ' + @(GetEvents (Get-Date).AddHours(-6)).Count)
if($fail){ W ''; W '=== VERDICT ==='; W ('RESULT: ABORT - ' + $fail + ' pre-flight failure(s)'); 'ABORT' | Set-Content -LiteralPath $sumF; Get-Content -LiteralPath $o; return }

# ---- B: launch ----------------------------------------------------------------
W ''; W '########## B: launch ##########'
$ea = @(Get-Process -EA SilentlyContinue | Where-Object { $_.ProcessName -match 'EADesktop|EABackgroundService' })
if(-not $ea.Count){
  if(Test-Path -LiteralPath $EAD){ W '  EA app not running -> starting EADesktop'; Start-Process -FilePath $EAD | Out-Null
    for($i=0; $i -lt 12 -and -not (Get-Process -EA SilentlyContinue | Where-Object { $_.ProcessName -match 'EADesktop' }); $i++){ Start-Sleep 5 }; Start-Sleep 10 }
  else { W ('  !! EA app exe not found: ' + $EAD) }
} else { W ('  EA app already running: ' + (($ea | ForEach-Object { $_.ProcessName }) -join ',')) }
$t0 = Get-Date
[void](GetEvents $t0.AddMinutes(-2))
Start-Process -FilePath $exe | Out-Null
W ('  launched ' + $exe)


# ---- C: watch -----------------------------------------------------------------
W ''; W '########## C: watch (1 s poll, refusal capture, 10 s snapshots) ##########'
$upAt = $null; $pid0 = 0; $died = $false; $diedAt = $null; $refusals = 0; $launchDeadline = $t0.AddSeconds($BootSec)
while($true){
  Start-Sleep -Seconds 1
  $now = Get-Date; $el = [int]($now - $t0).TotalSeconds
  $p = GetGame
  if($p -and -not $upAt){ $upAt = $now; $pid0 = $p.Id; W ('  t+' + $el + 's GAME UP pid=' + $pid0 + ' name=' + $p.ProcessName + ' ws=' + [int]($p.WorkingSet64/1MB) + 'MB') }
  if($upAt -and -not $p -and -not $died){ $died = $true; $diedAt = $now; W ('  t+' + $el + 's GAME EXITED (was pid ' + $pid0 + ')'); W ('    apexdrv RUNNING=' + (DrvRunning) + ' ac=' + (GameSet)) }
  foreach($e in @(GetEvents $now.AddSeconds(-8))){
    $refusals++
    $kind = 'EVT'; if($e.ProviderName -match 'Application Popup' -or $e.Message -match $RX){ $kind = 'REFUSAL' }
    W ('    ' + $kind + ' ' + $e.TimeCreated.ToString('HH:mm:ss') + ' ' + $e.LogName + ' id=' + $e.Id + ' src=' + $e.ProviderName + ' :: ' + (Short $e.Message))
  }
  if(($el % 10) -eq 0 -and $el -gt 0){
    $g = GetGame; $ws = 0; $th = 0
    if($g){ try { $ws = [int]($g.WorkingSet64/1MB); $th = $g.Threads.Count } catch {} }
    W ('    SNAP t+' + $el + 's proc=[' + (GameSet) + '] ws=' + $ws + 'MB th=' + $th + ' apexdrv=' + $(if(DrvRunning){'RUNNING'}else{'DOWN'}) + ' eaac=' + (SvcState 'EAAntiCheatService'))
  }
  if(-not $upAt -and $now -gt $launchDeadline){ W ('  NO GAME after ' + $BootSec + ' s - aborting watch'); break }
  if($died -and ($now - $diedAt).TotalSeconds -ge 20){ W '  (20 s after death - stopping)'; break }
  if($upAt -and -not $died -and ($now - $upAt).TotalSeconds -ge $WinSec){ W ('  window complete: ' + $WinSec + ' s alive'); break }
}

# ---- D: verdict ---------------------------------------------------------------
$aliveEnd = [bool](GetGame)
$aliveSec = 0; if($upAt){ $aliveSec = [int]((($(if($diedAt){ $diedAt } else { Get-Date })) - $upAt).TotalSeconds) }
W ''; W '########## D: after ##########'
W ('  alive=' + $aliveEnd + ' died=' + $died + ' aliveSec=' + $aliveSec + ' refusalEvents=' + $refusals)
W ('  procs=' + (GameSet) + '  apexdrv=' + $(if(DrvRunning){'RUNNING'}else{'DOWN'}) + '  eaac=' + (SvcState 'EAAntiCheatService'))
W ('  codeintegrity events since launch: ' + @(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-CodeIntegrity/Operational'; StartTime=$t0} -EA SilentlyContinue).Count)
W ''; W '=== VERDICT ==='
$v = 'RED'
if($aliveEnd -and $aliveSec -ge $WinSec -and $refusals -eq 0){ $v = 'GREEN'; W ('RESULT: GREEN - game alive ' + $aliveSec + ' s of ' + $WinSec + ' s, apexdrv resident, zero refusals. G1 COEXISTENCE GATE PASSED.') }
elseif($aliveEnd -and $refusals -eq 0){ $v = 'AMBER'; W ('RESULT: AMBER - alive ' + $aliveSec + ' s (window not reached), zero refusals') }
elseif($aliveEnd){ $v = 'AMBER'; W ('RESULT: AMBER - alive but ' + $refusals + ' refusal event(s) in the window') }
elseif($refusals -gt 0){ W ('RESULT: RED - game died after ' + $aliveSec + ' s with refusal evidence') }
elseif(-not $upAt){ W 'RESULT: RED - game never appeared' }
else { W ('RESULT: RED-SILENT - game died after ' + $aliveSec + ' s, no event-log evidence (harvest dump like p34)') }
W ''
W 'NEXT (manual, after reading this file): sc stop apexdrv  ->  sc start apexdrv  must give 577.'
W '  If it does, DSE is genuinely restored and the driver still loads only inside the open window.'
W ('-- h2 END ' + (Get-Date -f 'HH:mm:ss') + ' --')
(@('VERDICT=' + $v,'alive=' + $aliveEnd,'aliveSec=' + $aliveSec,'refusals=' + $refusals,'apexdrv=' + $(if(DrvRunning){'RUNNING'}else{'DOWN'}),'end=' + (Get-Date -f 'dd/MM HH:mm:ss')) -join ' ') | Set-Content -LiteralPath $sumF
Get-Content -LiteralPath $o

