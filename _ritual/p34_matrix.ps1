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

function W($t){ $t | Add-Content -LiteralPath $o }
function DrvState { (((& sc.exe query apexdrv 2>&1) -join ' ') -match 'RUNNING') }
function SvcState($n){ $s = ((& sc.exe query $n 2>&1) -join ' '); if($s -match 'STATE\s+:\s+\d+\s+(\w+)'){ $Matches[1] } else { 'ABSENT' } }
function Msg240($m){ $c = ($m -replace '\s+',' ').Trim(); $c.Substring(0,[Math]::Min(240,$c.Length)) }

function SnapState($tag){
  W ("  [$tag] $(Get-Date -f 'HH:mm:ss')  testsigning/nic=" + (((& $bcd /enum '{current}' 2>&1) | Select-String 'testsigning|nointegritychecks') -join ' / '))
  W ("  [$tag] SystemStartOptions = [" + (Get-ItemProperty $reg -Name SystemStartOptions -EA SilentlyContinue).SystemStartOptions + ']')
  W ("  [$tag] apexdrv RUNNING = " + (DrvState) + '   eaanticheat=' + (SvcState 'eaanticheat') + '   EAAntiCheatService=' + (SvcState 'EAAntiCheatService'))
  W ("  [$tag] leftovers: r5apex_dx12=" + ((Get-Process $proc -EA SilentlyContinue | Measure-Object).Count) + '  EADesktop=' + ((Get-Process EADesktop -EA SilentlyContinue | Measure-Object).Count))
}

function Clear-Game {
  Get-Process $proc -EA SilentlyContinue | ForEach-Object { try { $_.Kill() } catch {} }
  for($i=0; $i -lt 30; $i++){ if(-not (Get-Process $proc -EA SilentlyContinue)){ break }; Start-Sleep -Seconds 1 }
}

# ---- WATCH-GAME -----------------------------------------------------------
function Watch-Game($tag,$sec){
  Clear-Game
  $t0 = Get-Date
  $seen = @{}
  $pobj = $null
  Start-Process -FilePath $exe | Out-Null
  W "  [$tag] launched $proc at $($t0.ToString('HH:mm:ss'))  (sampling 1 s, window ${sec}s)"
  $firstSeen = 0; $lastSeen = 0; $died = $false; $up = 0
  for($el=1; $el -le $sec; $el++){
    Start-Sleep -Seconds 1
    $p = Get-Process $proc -EA SilentlyContinue
    if($p){
      if(-not $firstSeen){ $firstSeen = $el; $pobj = $p; W ("  [{0}] t+{1}s GAME UP pid={2}" -f $tag,$el,$p.Id) }
      $lastSeen = $el
      if($p.MainWindowTitle -and -not $seen['win']){ $seen['win']=1; W ("  [{0}] t+{1}s window title = {2}" -f $tag,$el,$p.MainWindowTitle) }
    } elseif($firstSeen -and -not $died){
      $died = $true; $up = $lastSeen - $firstSeen
      $code = 'n/a'
      if($pobj){ try { $pobj.Refresh(); if($pobj.HasExited){ $code = '0x{0:X8}' -f $pobj.ExitCode } } catch { $code = 'handle-lost' } }
      W ("  [{0}] t+{1}s GAME DIED after ~{2}s uptime  exit={3}" -f $tag,$el,$up,$code)
    }
    if(($el % 10) -eq 0){
      W ("  [{0}] t+{1}s  apexdrv={2} eaanticheat={3} svc={4}" -f $tag,$el,(DrvState),(SvcState 'eaanticheat'),(SvcState 'EAAntiCheatService'))
    }
    foreach($lg in 'Application','System'){
      foreach($e in @(Get-WinEvent -FilterHashtable @{LogName=$lg; StartTime=(Get-Date).AddSeconds(-2)} -EA SilentlyContinue)){
        if($e.ProviderName -match 'Kernel-PnP|Kernel-General|Winlogon|Service Control|Security-SPP|Defrag|Kernel-Power|Kernel-Boot|Time-Service'){ continue }
        $key = "$lg|$($e.RecordId)"
        if(-not $seen[$key]){
          $seen[$key] = 1
          W ('    ' + $tag + ' EVT ' + $e.TimeCreated.ToString('HH:mm:ss') + ' ' + $lg + ' id=' + $e.Id + ' src=' + $e.ProviderName + ' :: ' + (Msg240 $e.Message))
        }
      }
    }
    if($died -and $el -ge ($lastSeen + 20)){ W "  [$tag] (stopping 20 s after death)"; break }
  }
  $alive = [bool](Get-Process $proc -EA SilentlyContinue)
  W ("  [{0}] RESULT alive={1} died={2} uptime={3}s  apexdrv_RUNNING={4}  eaanticheat={5}" -f $tag,$alive,$died,$up,(DrvState),(SvcState 'eaanticheat'))
  return [pscustomobject]@{ alive=$alive; died=$died; uptime=$up }
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
W ("  TA driver-stopped : alive={0} died={1} uptime={2}s" -f $ra.alive,$ra.died,$ra.uptime)
W ("  TB driver-running : alive={0} died={1} uptime={2}s" -f $rb.alive,$rb.died,$rb.uptime)
if($ra.alive -and $rb.alive){
  W '  *** GREEN: the game survives either way -> boot test mode + logon scrub SHIPS.'
  W '      Next: run28 / apex_launcher --method=kernel against a live game.'
} elseif($ra.alive -and -not $rb.alive){
  W "  *** AMBER: our driver's PRESENCE is the killer while the flag is off (not the signature, not CI)."
  W '      Next: vary the load, one variable at a time - load AFTER the game is up, unique service name,'
  W '      drop the MajorFunction overwrite, shared-memory comm, no unbacked system thread, device path.'
} elseif(-not $ra.alive -and -not $rb.alive){
  W '  *** RED: the game dies even with the driver STOPPED while the flag is off => LIVE CI state is fatal.'
  W '      Next: real chain (EV -> attestation signing) or BYOVD manual map; or ship external-only.'
  W '      Also verify: does a REBOOT with testsigning off (never test mode) behave the same?'
} else {
  W '  *** ODD: TA dead but TB alive - suspect residue from the stop/start (check EAAC service + device).'
}
W ''
W ("-- p34 END $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') --")
W '  (driver left running by default so an injector can attach)'
Get-Content -LiteralPath $o

