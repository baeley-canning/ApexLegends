# p34 - DRIVER-PRESENCE DISCRIMINATOR (the test p33 could not answer).
#
# p33 proved the Javelin popup follows the FLAG SOURCE (BCD + SystemStartOptions) and that clearing it
# silences the popup - but its 5 s poll cannot see a ~6 s game exit, so its GREEN verdict was reached
# with alive=False on every trial.
#
# This probe varies ONE variable and samples every second:
#   TA : apexdrv STOPPED  + flag off -> launch -> watch 120 s
#   TB : apexdrv RUNNING  + flag off -> launch -> watch 120 s
#   TA alive, TB dead => our driver's PRESENCE is the killer when the flag is off (fix the load shape).
#   TA dead  too      => the LIVE CI state (boot test mode) is the killer => real signing / manual map.
#   both alive        => ship boot-test-mode + logon scrub.
#
# Also fixed vs p33: process exit code + uptime, ALL Application/System events in the window captured
# verbatim (the in-game EAAC panel and EAAC service errors never match p33's popup regex), EAAC service
# state sampled during the run, driver state asserted and logged before each launch.
#
# Writes: _ritual\p34_matrix.txt     Run: _ritual\run34.cmd
param([switch]$NoRestore)
$ErrorActionPreference = 'Continue'
$rit  = $PSScriptRoot
$adm  = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
$bcd  = 'C:\Windows\System32\bcdedit.exe'
$reg  = 'HKLM:\SYSTEM\CurrentControlSet\Control'
$exe  = 'C:\Program Files\EA Games\Apex\r5apex_dx12.exe'
$proc = 'r5apex_dx12'
$o    = Join-Path $rit 'p34_matrix.txt'

if(-not $adm){
  $ea = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'))
  if($NoRestore){ $ea += '-NoRestore' }
  Start-Process powershell -Verb RunAs -ArgumentList $ea
  exit
}

# single instance: a second p34 launched while the first is still alive makes both of them Clear-Game
# each other's trials (this really happened on the first clean attempt) -> kill earlier instances.
$dup = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'p34_matrix' -and $_.ProcessId -ne $PID })
if($dup.Count){
  foreach($d in $dup){ Stop-Process -Id $d.ProcessId -Force -EA SilentlyContinue }
  Start-Sleep -Seconds 2
}

function W($t){ $t | Add-Content -LiteralPath $o }
function DrvState { (((& sc.exe query apexdrv 2>&1) -join ' ') -match 'RUNNING') }
function SvcState($n){ $s = ((& sc.exe query $n 2>&1) -join ' '); if($s -match 'STATE\s+:\s+\d+\s+(\w+)'){ $Matches[1] } else { 'ABSENT' } }
function Msg240($m){ $c = ($m -replace '\s+',' ').Trim(); $c.Substring(0,[Math]::Min(240,$c.Length)) }

# broad process match: the game itself is 'r5apex_dx12', but EAAntiCheat.GameServiceLauncher also lives in
# the Apex folder, so prefer the game by name and only fall back to the folder path.
function IsGame($p){
  if($p.ProcessName -match 'r5apex|baeley'){ return $true }
  $pt = ''
  try { $pt = $p.Path } catch {}
  return [bool]($pt -like 'C:\Program Files\EA Games\Apex\*')
}
function Get-Game {
  $all = @(Get-Process -EA SilentlyContinue | Where-Object { IsGame $_ })
  if(-not $all.Count){ return $null }
  $g = @($all | Where-Object { $_.ProcessName -match 'r5apex|baeley' })
  if($g.Count){ return $g[0] }
  return $all[0]
}
function GameSet { (@(Get-Process -EA SilentlyContinue | Where-Object { IsGame $_ }) | ForEach-Object { $_.ProcessName + '(' + $_.Id + ')' }) -join ',' }

# every Javelin refusal string we have seen, both families (popup-in-log and in-game panel)
$RX = 'Security Violation|signing integrity checks must be enabled|must be disabled to start|unacceptable configuration|same time as the game'


function SnapState($tag){
  W ("  [$tag] $(Get-Date -f 'HH:mm:ss')  testsigning/nic=" + (((& $bcd /enum '{current}' 2>&1) | Select-String 'testsigning|nointegritychecks') -join ' / '))
  W ("  [$tag] SystemStartOptions = [" + (Get-ItemProperty $reg -Name SystemStartOptions -EA SilentlyContinue).SystemStartOptions + ']')
  W ("  [$tag] apexdrv RUNNING = " + (DrvState) + '   eaanticheat=' + (SvcState 'eaanticheat') + '   EAAntiCheatService=' + (SvcState 'EAAntiCheatService'))
  W ("  [$tag] leftovers: game=" + ((Get-Game | Measure-Object).Count) + '  EADesktop=' + ((Get-Process EADesktop -EA SilentlyContinue | Measure-Object).Count))
}

function Clear-Game {
  Get-Process -EA SilentlyContinue | Where-Object { IsGame $_ } | ForEach-Object { try { $_.Kill() } catch {} }
  for($i=0; $i -lt 30; $i++){ if(-not (Get-Game)){ break }; Start-Sleep -Seconds 1 }
}

# ---- WATCH-GAME -----------------------------------------------------------
function Watch-Game($tag,$sec){
  Clear-Game
  $t0 = Get-Date
  $seen = @{}
  $pobj = $null
  $popups = 0
  Start-Process -FilePath $exe | Out-Null
  W "  [$tag] launched $proc at $($t0.ToString('HH:mm:ss'))  (sampling 1 s, window ${sec}s)"
  $firstSeen = 0; $lastSeen = 0; $died = $false; $up = 0; $pname = ''
  for($el=1; $el -le $sec; $el++){
    Start-Sleep -Seconds 1
    $p = Get-Game
    if($p){
      if(-not $firstSeen){
        $firstSeen = $el; $pobj = $p; $pname = $p.ProcessName
        W ("  [{0}] t+{1}s GAME UP pid={2} name={3}" -f $tag,$el,$p.Id,$p.ProcessName)
      }
      $lastSeen = $el
      if($p.MainWindowTitle -and -not $seen['win']){ $seen['win']=1; W ("  [{0}] t+{1}s window title = {2}" -f $tag,$el,$p.MainWindowTitle) }
    } elseif($firstSeen -and -not $died){
      $died = $true; $up = $lastSeen - $firstSeen
      $code = 'n/a'
      if($pobj){ try { $pobj.Refresh(); if($pobj.HasExited){ $code = '0x{0:X8}' -f $pobj.ExitCode } } catch { $code = 'handle-lost' } }
      W ("  [{0}] t+{1}s GAME DIED after ~{2}s uptime  exit={3}" -f $tag,$el,$up,$code)
    }
    if(($el % 10) -eq 0){
      W ("  [{0}] t+{1}s  apexdrv={2} eaanticheat={3} svc={4} game={5} set=[{6}]" -f $tag,$el,(DrvState),(SvcState 'eaanticheat'),(SvcState 'EAAntiCheatService'),[bool]$p,(GameSet))
    }
    foreach($lg in 'Application','System'){
      foreach($e in @(Get-WinEvent -FilterHashtable @{LogName=$lg; StartTime=(Get-Date).AddSeconds(-2)} -EA SilentlyContinue)){
        $key = "$lg|$($e.RecordId)"
        if($seen[$key]){ continue }
        $seen[$key] = 1
        $isPop = [bool]($e.Message -match $RX)
        if($isPop){ $popups++ }
        if($isPop -or -not ($e.ProviderName -match 'Kernel-PnP|Kernel-General|Winlogon|Service Control|Security-SPP|Defrag|Kernel-Power|Kernel-Boot|Time-Service|EventLog|Application-Experience')){
          $kind = ' EVT '
          if($isPop){ $kind = ' POPUP ' }
          W ('    ' + $tag + $kind + $e.TimeCreated.ToString('HH:mm:ss') + ' ' + $lg + ' id=' + $e.Id + ' src=' + $e.ProviderName + ' :: ' + (Msg240 $e.Message))
        }
      }
    }
    if($died -and $el -ge ($lastSeen + 20)){ W "  [$tag] (stopping 20 s after death)"; break }
  }
  $alive = [bool](Get-Game)
  W ("  [{0}] RESULT alive={1} died={2} uptime={3}s popups={4} name='{5}'  apexdrv_RUNNING={6}  eaanticheat={7}" -f $tag,$alive,$died,$up,$popups,$pname,(DrvState),(SvcState 'eaanticheat'))
  return [pscustomobject]@{ alive=$alive; died=$died; uptime=$up; popups=$popups }
}

# ---- RUN ------------------------------------------------------------------
"=== p34 DRIVER-PRESENCE DISCRIMINATOR $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') admin=$adm ===" | Set-Content -LiteralPath $o
W '  hypothesis: with the flag already off, the game dies BECAUSE apexdrv is loaded.'
W '  TA stops the driver, TB starts it; nothing else changes.'
W ''
SnapState 'pre'
W ''
W '########## TA: apexdrv STOPPED + flag off (vanilla comparison) ##########'
if(DrvState){ W ('  sc stop apexdrv : ' + (((& sc.exe stop apexdrv 2>&1)) -join ' ')) }
Start-Sleep -Seconds 3
W ('  apexdrv RUNNING now = ' + (DrvState))
$ra = Watch-Game 'TA' 120
W ''
W '########## TB: apexdrv RUNNING + flag off (the configuration under test) ##########'
if(-not (DrvState)){ W ('  sc start apexdrv : ' + (((& sc.exe start apexdrv 2>&1)) -join ' ')) }
Start-Sleep -Seconds 2
W ('  apexdrv RUNNING now = ' + (DrvState))
$rb = Watch-Game 'TB' 120
W ''
W '########## VERDICT ##########'
W ("  TA driver-stopped : alive={0} died={1} uptime={2}s popups={3}" -f $ra.alive,$ra.died,$ra.uptime,$ra.popups)
W ("  TB driver-running : alive={0} died={1} uptime={2}s popups={3}" -f $rb.alive,$rb.died,$rb.uptime,$rb.popups)
if($ra.alive -and $rb.alive){
  W '  *** GREEN: the game survives either way -> boot test mode + logon scrub SHIPS.'
  W '      Next: run28 / apex_launcher --method=kernel against a live game.'
} elseif(-not $ra.alive -and -not $rb.alive -and $ra.popups -eq 0 -and $rb.popups -eq 0){
  W '  *** INCONCLUSIVE: no Javelin refusal AND no game process seen in either trial.'
  W '      Read the GAME UP / name lines: if a process name that is not the game matched Get-Game, fix the'
  W '      match; if nothing launched at all, it is the EA handshake - relaunch EADesktop and retry.'
} elseif($ra.alive -and -not $rb.alive){
  W "  *** AMBER: our driver's PRESENCE is the killer while the flag is off (not the signature, not CI)."
  W '      Next: vary the load, one variable at a time - load AFTER the game is up, unique service name,'
  W '      drop the MajorFunction overwrite, shared-memory comm, no unbacked system thread, device path.'
} elseif(-not $ra.alive -and -not $rb.alive){
  W '  *** RED: the box refuses the game even with our driver STOPPED and the flag strings clean.'
  W '      => the refusal follows the LIVE kernel state (this boot is test mode), not the flag string.'
  W '      Next: real chain (EV -> attestation signing) or BYOVD manual map; or ship external-only.'
  W '      Confirm once on a normal reboot (testsigning off, never test mode) before spending on signing.'
} else {
  W '  *** ODD: TA dead but TB alive - suspect residue from the stop/start (check EAAC service + device).'
}
W ''
W ("-- p34 END $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') --")
W '  (driver left running by default so an injector can attach)'
Get-Content -LiteralPath $o

