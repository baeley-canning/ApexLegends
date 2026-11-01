# probe7.ps1 - ELEVATED. Isolation run for the Javelin #95 popup + a CLEAN kernel probe.
#
# Why: probe6's probe ran against a r5apex that Javelin had already killed
# (STATUS_PROCESS_IS_TERMINATING), so "kernel_read=no" measured a dying process.
# This script separates the two open questions:
#   P1: is the #95 popup caused by OUR loaded test-signed driver, or by machine
#       config (testsigning on / Secure Boot off / HVCI off / gdrv3 loaded)?
#       -> launch apex with NO apexdrv loaded at all.
#   P2: on whatever target exists, load apexdrv and probe it from kernel context
#       (clean measurement on a live process).
#   P3: if P1 passed, relaunch apex with the driver loaded -> does #95 return?
#
# Nothing is injected. The driver is stopped+deleted again at the end.
$ErrorActionPreference = 'Continue'

$log      = 'C:\qkp\probe7.txt'
$b        = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build'
$drv      = 'C:\Windows\System32\drivers\apexdrv.sys'
$apexExe  = 'C:\Program Files\EA Games\Apex\r5apex_dx12.exe'
$acDir    = 'C:\Program Files\EA\AC'

function W($t) { ("{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $t) | Out-File -Encoding ascii -Append $log }
function Hdr($t) { W ''; W ("===== $t =====") }

Remove-Item $log -ErrorAction SilentlyContinue
Hdr "probe7 start"
W ("elevated : " + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
W ("apex exe : " + (Get-Item $apexExe -ErrorAction SilentlyContinue).LastWriteTime)
W ("driver   : " + (Get-Item $drv -ErrorAction SilentlyContinue).Length + " B sig=" + (Get-AuthenticodeSignature $drv -ErrorAction SilentlyContinue).Status)

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
function ServState { return ((& sc.exe query apexdrv 2>&1 | Out-String) -match 'SERVICE_NAME') }

function SnapState($tag) {
    $bcd = (& bcdedit /enum 2>&1 | Out-String)
    W "[$tag] testsigning=$($bcd -match 'testsigning\s+Yes')  nointegrity=$($bcd -match 'nointegritychecks\s+Yes')"
    W "[$tag] apexdrv registered=$(ServState)  running=$(((& sc.exe query apexdrv 2>&1 | Out-String) -match 'RUNNING'))"
    $ap = Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1
    W "[$tag] r5apex pid=$($ap.Id)  AC procs=$((Get-Process EAAntiCheat.GameService,EAAntiCheat.GameServiceLauncher,EACefSubProcess -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ',')"
}

function KillGame {
    foreach ($n in 'r5apex_dx12','EAAntiCheat.GameService','EAAntiCheat.GameServiceLauncher') {
        Get-Process $n -ErrorAction SilentlyContinue | ForEach-Object {
            W "  kill $($_.ProcessName) ($($_.Id))"
            try { $_.Kill() } catch { W "  kill failed: $($_.Exception.Message)" }
        }
    }
    Start-Sleep -Seconds 8
}

function DialogUp($tag) {
    $w = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle } |
           Where-Object { $_.MainWindowTitle -match 'Javelin|AntiCheat|Anti-Cheat|Apex' })
    foreach ($p in $w) { W "[$tag] WINDOW $($p.ProcessName): $($p.MainWindowTitle)" }
    if ($w.Count -eq 0) { W "[$tag] no Javelin/Apex window" }
    return [bool]$w.Count
}

# Launch apex and watch it. Returns $true when apex is still alive and no AC
# dialog is up after $seconds (AC passed), $false otherwise.
function LaunchAndWatch($tag, $seconds) {
    $p = Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) {
        Start-Process -FilePath $apexExe -WorkingDirectory (Split-Path $apexExe)
        W "[$tag] apex launched (direct exe, no-wait)"
    } else { W "[$tag] apex already running pid=$($p.Id)" }

    $saw = $false
    $steps = [int]($seconds / 5)
    for ($i = 1; $i -le $steps; $i++) {
        Start-Sleep -Seconds 5
        $p = Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($p) {
            $saw = $true
            $up = [int]((Get-Date) - $p.StartTime).TotalSeconds
            if ($i % 3 -eq 0) { W "[$tag] t=$($i*5)s alive pid=$($p.Id) uptime=${up}s" }
        } elseif ($saw) {
            W "[$tag] t=$($i*5)s apex GONE (was alive) -> AC rejection or crash"
            $null = DialogUp $tag
            return $false
        } else {
            W "[$tag] t=$($i*5)s apex not up yet"
        }
        if ($i % 4 -eq 0) { if (DialogUp $tag) { W "[$tag] -> dialog present at t=$($i*5)s"; return $false } }
    }
    $p = Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p) {
        W "[$tag] VERDICT: apex ALIVE after ${seconds}s (uptime $([int]((Get-Date) - $p.StartTime).TotalSeconds)s), no dialog -> AC PASSED"
        return $true
    }
    W "[$tag] VERDICT: apex never stayed up -> AC BLOCKED"
    return $false
}

function LoadDrv {
    if (-not (ServState)) {
        (& sc.exe create apexdrv binPath= '\??\C:\Windows\System32\drivers\apexdrv.sys' type= kernel start= demand error= normal 2>&1) | ForEach-Object { W "  create| $_" }
    }
    (& sc.exe start apexdrv 2>&1) | ForEach-Object { W "  start| $_" }
    Start-Sleep -Seconds 2
    W "  service now : $((Get-Service apexdrv -ErrorAction SilentlyContinue).Status)"
}
function UnloadDrv {
    (& sc.exe stop apexdrv 2>&1) | ForEach-Object { W "  stop| $_" }
    (& sc.exe delete apexdrv 2>&1) | ForEach-Object { W "  delete| $_" }
}

# ---------------------------------------------------------------------------
Hdr 'PHASE 0 - snapshot'
SnapState 'p0'
W ("AC dir: " + ((Get-ChildItem $acDir -ErrorAction SilentlyContinue | ForEach-Object { $_.Name + '(' + $_.Length + ')' }) -join ' '))
foreach ($p in (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle })) {
    W "  win $($p.ProcessName): $($p.MainWindowTitle)"
}

# ---------------------------------------------------------------------------
Hdr 'PHASE 1 - NO apexdrv loaded, launch apex, wait for the AC'
KillGame
UnloadDrv
Start-Sleep -Seconds 3
SnapState 'p1'
$cleanPass = LaunchAndWatch 'p1' 120
$null = DialogUp 'p1'
W "PHASE1 RESULT: ac_passed_without_driver=$cleanPass"

# ---------------------------------------------------------------------------
Hdr 'PHASE 2 - kernel probe against the live target (driver loaded now)'
LoadDrv
$ap = Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($ap) {
    $up = [int]((Get-Date) - $ap.StartTime).TotalSeconds
    W "  target: pid=$($ap.Id) uptime=${up}s (short uptime => measuring a dying process again)"
    $out = 'C:\qkp\probe7_out.txt'
    $err = 'C:\qkp\probe7_err.txt'
    Remove-Item $out,$err -ErrorAction SilentlyContinue
    $pr = Start-Process -FilePath (Join-Path $b 'apex_launcher.exe') `
                        -ArgumentList @('--kernel-probe', "--pid=$($ap.Id)", '--no-wait', "--driver=$drv") `
                        -WorkingDirectory $b -Wait -PassThru `
                        -RedirectStandardOutput $out -RedirectStandardError $err
    W "  PROBE_EXIT=$($pr.ExitCode)"
    Get-Content $out -ErrorAction SilentlyContinue | ForEach-Object { W "  | $_" }
    Get-Content $err -ErrorAction SilentlyContinue | ForEach-Object { W "  err| $_" }
    Get-Content (Join-Path $b 'apexdrv_probe.txt') -ErrorAction SilentlyContinue | ForEach-Object { W "  rep| $_" }
    SnapState 'p2'
} else { W '  no live apex - probe skipped' }

# ---------------------------------------------------------------------------
# PHASE 2b - if the AC already popped in P1, that target was dying.  Take the
# measurement again inside the early window (apex up, AC has not decided yet).
if (-not $cleanPass) {
    Hdr 'PHASE 2b - early-window probe on a fresh launch (healthy target)'
    KillGame
    Start-Process -FilePath $apexExe -WorkingDirectory (Split-Path $apexExe)
    W '  apex relaunched, waiting 30 s (before the AC verdict)'
    Start-Sleep -Seconds 30
    $ap2 = Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ap2) {
        W "  target: pid=$($ap2.Id) uptime=$([int]((Get-Date) - $ap2.StartTime).TotalSeconds)s"
        LoadDrv
        $out2 = 'C:\qkp\probe7b_out.txt'
        $err2 = 'C:\qkp\probe7b_err.txt'
        Remove-Item $out2,$err2 -ErrorAction SilentlyContinue
        $pr2 = Start-Process -FilePath (Join-Path $b 'apex_launcher.exe') `
                             -ArgumentList @('--kernel-probe', "--pid=$($ap2.Id)", '--no-wait', "--driver=$drv") `
                             -WorkingDirectory $b -Wait -PassThru `
                             -RedirectStandardOutput $out2 -RedirectStandardError $err2
        W "  PROBE_EXIT=$($pr2.ExitCode)"
        Get-Content $out2 -ErrorAction SilentlyContinue | ForEach-Object { W "  | $_" }
        Get-Content (Join-Path $b 'apexdrv_probe.txt') -ErrorAction SilentlyContinue | ForEach-Object { W "  rep| $_" }
        $ap2b = Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1
        W "  target still alive after probe: $([bool]$ap2b)"
    } else { W '  apex not up in the early window' }
}

# ---------------------------------------------------------------------------
Hdr 'PHASE 3 - is the popup caused by the driver being LOADED at AC init?'
$driverBlamed = $false
if ($cleanPass) {
    LoadDrv
    KillGame
    SnapState 'p3'
    $pass2 = LaunchAndWatch 'p3' 120
    $null = DialogUp 'p3'
    $driverBlamed = (-not $pass2)
    W "PHASE3 RESULT: ac_passed_with_driver_loaded=$pass2  => driver_blamed=$driverBlamed"
} else {
    W 'phase1 was already blocked WITH NO DRIVER LOADED'
    W '=> trigger is machine config (testsigning / VBS / HVCI / 3rd-party drivers), not apexdrv'
}

# ---------------------------------------------------------------------------
Hdr 'EVIDENCE - CodeIntegrity + Application errors'
Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 10 -ErrorAction SilentlyContinue |
    ForEach-Object { W ("  {0} id={1} {2}" -f $_.TimeCreated.ToString('MM-dd HH:mm:ss'), $_.Id, ($_.Message -replace '\s+', ' ')) }
Get-WinEvent -FilterHashtable @{LogName='Application'; Level=2} -MaxEvents 8 -ErrorAction SilentlyContinue |
    ForEach-Object { W ("  {0} id={1} {2} :: {3}" -f $_.TimeCreated.ToString('MM-dd HH:mm:ss'), $_.Id, $_.ProviderName, ($_.Message -replace '\s+', ' ')) }

# leave the machine in the least-invasive config for a manual launch
UnloadDrv

Hdr 'RESULT'
W "ac_passed_without_driver          = $cleanPass"
W "driver_blamed_for_popup           = $driverBlamed"
if ($cleanPass -and $driverBlamed) {
    W 'A: a LOADED test-signed apexdrv is what Javelin #95 objects to.'
    W '   -> fix signing (cross-signed/attestation) or keep the driver unloaded at AC init.'
} elseif (-not $cleanPass) {
    W 'B: #95 appears with NO driver of ours loaded -> machine config. Fix that first:'
    W '   testsigning on, Secure Boot off, HVCI off, gdrv3/EasyTune + TeamViewer present.'
} else {
    W 'C: driver tolerated at launch -> the popup was transient; re-probe and continue to reads.'
}
W 'END'
