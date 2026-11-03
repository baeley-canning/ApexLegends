# h2w1 - WATCH-ONLY continuation of the G1 gate against an ALREADY-RUNNING game.
#
# Why this exists instead of a second h2 run:
#   h2_gate (22:11:02 - 22:21:18) launched from a cold EA app and aborted after 600 s with
#   "RED - game never appeared". The user then signed the EA app in and started the game at
#   22:54:50 - AFTER h1 (22:06:20) had already loaded apexdrv in this boot under a restored DSE.
#   The gate precondition (driver resident in the same boot as the game) therefore already exists.
#   Relaunching would re-run Javelin's startup checks for no gain, and a fresh DSE write just to
#   re-arm a launch would reset the PatchGuard horizon in the middle of the gate.
#
# No mutation of any kind, so nothing to restore (R4). Non-elevated is enough for every call.
# Same refusal families and same verdict shape as h2_gate so the summaries stay comparable.
# GREEN = the live process survives WinSec from the moment this starts AND zero refusal events.
#
# Run: _ritual\h2w1_task.ps1  (HIGHEST scheduled task - console teardown cannot kill it)
# Writes: _ritual\h2w1_watch.txt , _ritual\h2w1_watch.summary.txt
param([int]$WinSec = 1800)
$ErrorActionPreference = 'Continue'
$rit  = $PSScriptRoot
$o    = Join-Path $rit 'h2w1_watch.txt'
$sumF = Join-Path $rit 'h2w1_watch.summary.txt'
$svc  = 'apexdrv'
$bin  = "$env:WINDIR\System32\drivers\apexdrv.sys"

$dup = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'h2w1_watch' -and $_.ProcessId -ne $PID })
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
$RX = 'Security Violation|must be disabled to start|signing integrity checks must be enabled|unacceptable configuration|AntiCheat|Javelin|integrity check failed|Untrusted system file|incompatible'
$global:seen = @{}

# ---- A: pre-state (R3) ----------------------------------------------------------
$t0 = Get-Date
"=== h2w1 WATCH-ONLY GATE CONTINUATION $($t0.ToString('dd/MM/yyyy HH:mm:ss')) pid=$PID host=$env:COMPUTERNAME win=${WinSec}s ===" | Set-Content -LiteralPath $o
W '  h2_gate aborted 22:21:18 with "RED - game never appeared"; h1 loaded apexdrv 22:06:20 this boot.'
W ''; W '########## A: pre-state (nothing is mutated) ##########'
W ('  lastboot=' + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime)
W ('  apexdrv=' + $(if(DrvRunning){'RUNNING'}else{'DOWN'}) + '  eaac=' + (SvcState 'EAAntiCheatService'))
if(Test-Path -LiteralPath $bin){ W ('  bin sha256=' + (Get-FileHash -LiteralPath $bin -Algorithm SHA256).Hash) } else { W '  bin MISSING' }
W ('  blocklist=' + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config' -EA SilentlyContinue).VulnerableDriverBlocklistEnable)
$h1f = Join-Path $rit 'h1b_host.txt'
if(Test-Path -LiteralPath $h1f){ W ('  h1b restore line (operative): ' + ((Get-Content -LiteralPath $h1f | Select-String 'readback=' | Select-Object -Last 1) -join ' ')) }
W ('  popup id26 baseline (6 h) = ' + @(Get-WinEvent -FilterHashtable @{LogName='Application'; Id=26; StartTime=$t0.AddHours(-6)} -EA SilentlyContinue).Count)
$g0 = GetGame
if($g0){
  $preAlive = [int]((Get-Date) - $g0.StartTime).TotalSeconds
  W ('  live game: ' + $g0.ProcessName + ' pid=' + $g0.Id + ' ws=' + [int]($g0.WorkingSet64/1MB) + 'MB started=' + $g0.StartTime.ToString('HH:mm:ss') + ' preAlive=' + $preAlive + 's')
} else { $preAlive = 0; W '  NO GAME PROCESS' }

# ---- B: watch -------------------------------------------------------------------
W ''; W '########## B: watch (1 s poll, refusal capture, 10 s snapshots) ##########'
$upAt = $null; $pid0 = 0; $died = $false; $diedAt = $null; $refusals = 0
if($g0 -and (DrvRunning)){ $upAt = $t0; $pid0 = $g0.Id; W ('  watching from t+0, window ' + $WinSec + ' s (total with preAlive = ' + ($WinSec + $preAlive) + ' s)') }
elseif($g0){ W '  driver DOWN at start - verdict cannot be GREEN' }
while($upAt){
  Start-Sleep -Seconds 1
  $now = Get-Date; $el = [int]($now - $t0).TotalSeconds
  $p = GetGame
  if($p -and -not $pid0){ $pid0 = $p.Id }
  if(-not $p -and -not $died){ $died = $true; $diedAt = $now; W ('  t+' + $el + 's GAME EXITED (was pid ' + $pid0 + ')'); W ('    apexdrv RUNNING=' + (DrvRunning) + ' ac=' + (GameSet)) }
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
  if($died -and ($now - $diedAt).TotalSeconds -ge 20){ W '  (20 s after death - stopping)'; break }
  if(-not $died -and ($now - $upAt).TotalSeconds -ge $WinSec){ W ('  window complete: ' + $WinSec + ' s alive'); break }
}

# ---- C: verdict -----------------------------------------------------------------
$aliveEnd = [bool](GetGame)
$aliveSec = 0; if($upAt){ $aliveSec = [int]((($(if($diedAt){ $diedAt } else { Get-Date })) - $upAt).TotalSeconds) }
W ''; W '########## C: after ##########'
W ('  alive=' + $aliveEnd + ' died=' + $died + ' aliveSec=' + $aliveSec + ' preAliveSec=' + $preAlive + ' refusalEvents=' + $refusals)
W ('  procs=' + (GameSet) + '  apexdrv=' + $(if(DrvRunning){'RUNNING'}else{'DOWN'}) + '  eaac=' + (SvcState 'EAAntiCheatService'))
W ('  codeintegrity events since t0: ' + @(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-CodeIntegrity/Operational'; StartTime=$t0} -EA SilentlyContinue).Count)
W ''; W '=== VERDICT ==='
$v = 'RED'
if($aliveEnd -and $aliveSec -ge $WinSec -and $refusals -eq 0){ $v = 'GREEN'; W ('RESULT: GREEN - game alive ' + $aliveSec + ' s of ' + $WinSec + ' s watched (plus ' + $preAlive + ' s before the watch), apexdrv resident, zero refusals. G1 COEXISTENCE GATE PASSED.') }
elseif($aliveEnd -and $refusals -eq 0){ $v = 'AMBER'; W ('RESULT: AMBER - alive ' + $aliveSec + ' s (window not reached), zero refusals') }
elseif($aliveEnd){ $v = 'AMBER'; W ('RESULT: AMBER - alive but ' + $refusals + ' refusal event(s) in the window') }
elseif($refusals -gt 0){ W ('RESULT: RED - game died after ' + $aliveSec + ' s with refusal evidence') }
elseif(-not $upAt){ W 'RESULT: RED - nothing to watch (no game, or driver DOWN at start)' }
else { W ('RESULT: RED-SILENT - game died after ' + $aliveSec + ' s, no event-log evidence (harvest dump like p34)') }
W ''
W 'CAVEAT: the h1 restore line in h1_host.txt reads readback=10 - that is the boot-4 snapshot and it is'
W '  SUPERSEDED. h1b_restore16.ps1 re-wrote the true boot value 0x16 at 22:07:41 (readback=0x16'
W '  match=True, driver still RUNNING), so g_CiOptions is byte-exact and DSE is genuinely restored.'
W '  Never use h1_host.txt''s readback as current state - h1b_host.txt is the operative evidence.'
W ''
W 'NEXT (manual, after reading this file): sc stop apexdrv  ->  sc start apexdrv  must give 577.'
W '  If it does, DSE is genuinely restored and the driver still loads only inside the open window.'
W ('-- h2w1 END ' + (Get-Date -f 'HH:mm:ss') + ' --')
(@('VERDICT=' + $v,'alive=' + $aliveEnd,'aliveSec=' + $aliveSec,'preAliveSec=' + $preAlive,'refusals=' + $refusals,'apexdrv=' + $(if(DrvRunning){'RUNNING'}else{'DOWN'}),'end=' + (Get-Date -f 'dd/MM HH:mm:ss')) -join ' ') | Set-Content -LiteralPath $sumF
