# p8.ps1 - ELEVATED. Isolate the Javelin #95 popup from apexdrv, then probe.
#  S0 baseline + popup inventory    S1 launch apex with NO apexdrv at all
#  S2 driverless popup => bisect machine config (TeamViewer, gdrv3/EasyTune)
#  S3 driverless pass => load apexdrv LATE on the live game, watch, probe
# probe7 proved Javelin pops #95 BEFORE r5apex_dx12 ever persists, so the
# popup is a pre-launch verdict and "apex not up" == blocked.
$ErrorActionPreference = 'Continue'
$log     = 'C:\qkp\p8.txt'
$b       = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build'
$drv     = 'C:\Windows\System32\drivers\apexdrv.sys'
$apexExe = 'C:\Program Files\EA Games\Apex\r5apex_dx12.exe'

function W($t) { ("{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $t) | Out-File -Encoding ascii -Append $log }
function Hdr($t) { W ''; W ("===== $t =====") }
Remove-Item $log -ErrorAction SilentlyContinue
Hdr 'p8 start'
W ('elevated : ' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

Add-Type -Namespace U -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
[DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
'@

function WTxt($h) { $sb = New-Object Text.StringBuilder 512; $null = [U.Win]::GetWindowText($h, $sb, 512); $sb.ToString() }
function WCls($h) { $sb = New-Object Text.StringBuilder 256; $null = [U.Win]::GetClassName($h, $sb, 256); $sb.ToString() }
function PName($q) { (Get-Process -Id $q -ErrorAction SilentlyContinue).ProcessName }
$GW_CHILD = 5; $GW_HWNDNEXT = 2; $BM_CLICK = 0xF5
function TopWindows { $h = [U.Win]::GetWindow([U.Win]::GetDesktopWindow(), $GW_CHILD); while ($h -ne [IntPtr]::Zero) { $h; $h = [U.Win]::GetWindow($h, $GW_HWNDNEXT) } }

function PopupInfo($tag) {
    foreach ($h in (TopWindows)) {
        if (-not [U.Win]::IsWindowVisible($h)) { continue }
        $t = WTxt $h; $c = WCls $h; $blob = $t
        if ($c -eq '#32770') {
            $ch = [U.Win]::GetWindow($h, $GW_CHILD)
            while ($ch -ne [IntPtr]::Zero) {
                if ((WCls $ch) -eq 'Static') { $blob += ' | ' + (WTxt $ch) }
                $ch = [U.Win]::GetWindow($ch, $GW_HWNDNEXT)
            }
        }
        if ($blob -match 'Javelin|unacceptable|Security Violation|tampering') {
            $o = 0; $null = [U.Win]::GetWindowThreadProcessId($h, [ref]$o)
            W ("[$tag] POPUP pid=$o proc=$(PName $o) class=$c title=$t")
            W ("[$tag]   body: $blob")
            return $true
        }
    }
    return $false
}
function ClickOk($tag) {
    foreach ($h in (TopWindows)) {
        if ((WCls $h) -ne '#32770' -or -not [U.Win]::IsWindowVisible($h)) { continue }
        $ch = [U.Win]::GetWindow($h, $GW_CHILD)
        while ($ch -ne [IntPtr]::Zero) {
            if (((WCls $ch) -eq 'Button') -and ((WTxt $ch) -match '^\s*&?OK\s*$')) {
                $null = [U.Win]::SendMessage($ch, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
                W "[$tag] clicked OK (dialog $h)"
            }
            $ch = [U.Win]::GetWindow($ch, $GW_HWNDNEXT)
        }
    }
}

function ServState { return ((& sc.exe query apexdrv 2>&1 | Out-String) -match 'SERVICE_NAME') }
function SnapState($tag) {
    $bcd = (& bcdedit /enum 2>&1 | Out-String)
    $run = ((& sc.exe query apexdrv 2>&1 | Out-String) -match 'RUNNING')
    W "[$tag] testsigning=$($bcd -match 'testsigning\s+Yes') nointegrity=$($bcd -match 'nointegritychecks\s+Yes')"
    W "[$tag] apexdrv registered=$(ServState) running=$run"
    W "[$tag] r5apex=$((Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1).Id)"
}
function KillGame {
    foreach ($n in 'r5apex_dx12', 'EAAntiCheat.GameService', 'EAAntiCheat.GameServiceLauncher', 'EACefSubProcess') {
        Get-Process $n -ErrorAction SilentlyContinue | ForEach-Object {
            W "  kill $($_.ProcessName) ($($_.Id))"
            try { $_.Kill() } catch { W "  kill failed: $($_.Exception.Message)" }
        }
    }
    Start-Sleep -Seconds 8
}
function LaunchAndWatch($tag, $seconds) {
    Start-Process -FilePath $apexExe -WorkingDirectory (Split-Path $apexExe)
    W "[$tag] apex launched (direct exe)"
    $steps = [int]($seconds / 5)
    for ($i = 1; $i -le $steps; $i++) {
        Start-Sleep -Seconds 5
        $t = $i * 5
        $p = Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($p) {
            if ($i % 3 -eq 0) { W "[$tag] t=${t}s r5apex pid=$($p.Id) up=$([int]((Get-Date) - $p.StartTime).TotalSeconds)s" }
        } elseif ($i % 6 -eq 0) {
            $ac = (Get-Process EAAntiCheat.GameService, EAAntiCheat.GameServiceLauncher, EACefSubProcess -ErrorAction SilentlyContinue |
                   ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ','
            W "[$tag] t=${t}s no r5apex (ac=$ac)"
        }
        if (PopupInfo $tag) { W "[$tag] POPUP first seen at t=${t}s"; return $false }
    }
    $p = Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p) { W "[$tag] VERDICT PASS: apex alive ${seconds}s, no popup"; return $true }
    W "[$tag] VERDICT BLOCKED: apex never persisted (no popup caught)"; return $false
}

# ========================================================== PHASES
function LoadDrv {
    Copy-Item (Join-Path $b 'apexdrv.sys') $drv -Force
    if (-not (ServState)) {
        (& sc.exe create apexdrv binPath= '\??\C:\Windows\System32\drivers\apexdrv.sys' type= kernel start= demand error= normal 2>&1) | ForEach-Object { W "  create| $_" }
    }
    (& sc.exe start apexdrv 2>&1) | ForEach-Object { W "  start| $_" }
    Start-Sleep -Seconds 2
}
function UnloadDrv {
    (& sc.exe stop apexdrv 2>&1) | Out-Null
    (& sc.exe delete apexdrv 2>&1) | ForEach-Object { W "  delete| $_" }
}

Hdr 'S0 - baseline'
W ('apexdrv registered = ' + (ServState))
PopupInfo 's0' | Out-Null
ClickOk 's0'
KillGame
SnapState 's0'

Hdr 'S1 - launch apex with NO apexdrv loaded (watch 240s)'
$clean = LaunchAndWatch 's1' 240
W "S1 RESULT clean_driverless_pass=$clean"
SnapState 's1'

if (-not $clean) {
    Hdr 'S2a - driverless popup => machine config. Blame test 1: TeamViewer'
    ClickOk 's2a'
    (& sc.exe stop TeamViewer 2>&1) | ForEach-Object { W "  tv| $_" }
    Get-Process TeamViewer, tv_w32, tv_x64 -ErrorAction SilentlyContinue | ForEach-Object { W "  kill $($_.ProcessName) ($($_.Id))"; try { $_.Kill() } catch {} }
    KillGame
    $a = LaunchAndWatch 's2a' 210
    W "S2a RESULT pass_after_stopping_TeamViewer=$a"

    if (-not $a) {
        Hdr 'S2b - still popup. Blame test 2: gdrv3 (Gigabyte) + EasyTune (VBS ON this box)'
        ClickOk 's2b'
        Get-Process EasyTuneEngineService, GTTerminal -ErrorAction SilentlyContinue | ForEach-Object { W "  kill $($_.ProcessName)"; try { $_.Kill() } catch {} }
        (& sc.exe stop EasyTuneEngineService 2>&1) | ForEach-Object { W "  et| $_" }
        (& sc.exe stop gdrv3 2>&1) | ForEach-Object { W "  gdrv3| $_" }
        W ('  gdrv3 running now = ' + (((& sc.exe query gdrv3 2>&1 | Out-String) -match 'RUNNING')))
        KillGame
        $bv = LaunchAndWatch 's2b' 210
        W "S2b RESULT pass_after_unloading_gdrv3=$bv"
        (& sc.exe start gdrv3 2>&1) | ForEach-Object { W "  gdrv3 re| $_" }
        (& sc.exe start TeamViewer 2>&1) | ForEach-Object { W "  tv re| $_" }
    }
}

if (Get-Process r5apex_dx12 -ErrorAction SilentlyContinue) {
    Hdr 'S3 - LIVE target: load apexdrv LATE and watch for the popup'
    LoadDrv
    W ('  driver: ' + ((& sc.exe query apexdrv 2>&1 | Out-String) -match 'RUNNING'))
    $late = $false
    for ($i = 1; $i -le 24; $i++) {
        Start-Sleep -Seconds 5
        if (PopupInfo 's3') { $late = $true; break }
        if (-not (Get-Process r5apex_dx12 -ErrorAction SilentlyContinue)) { W "  apex died at t=$($i*5)s after driver load"; break }
    }
    W "S3 RESULT popup_after_late_driver_load=$late"

    $ap = Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ap -and -not $late) {
        $up = [int]((Get-Date) - $ap.StartTime).TotalSeconds
        W "  target pid=$($ap.Id) uptime=${up}s"
        $out = 'C:\qkp\p8_out.txt'; $err = 'C:\qkp\p8_err.txt'
        Remove-Item $out, $err -ErrorAction SilentlyContinue
        $pr = Start-Process -FilePath (Join-Path $b 'apex_launcher.exe') `
                            -ArgumentList @('--kernel-probe', "--pid=$($ap.Id)", '--no-wait', "--driver=$drv") `
                            -WorkingDirectory $b -Wait -PassThru `
                            -RedirectStandardOutput $out -RedirectStandardError $err
        W "  PROBE_EXIT=$($pr.ExitCode)"
        Get-Content $out -ErrorAction SilentlyContinue | ForEach-Object { W "  | $_" }
        Get-Content $err -ErrorAction SilentlyContinue | ForEach-Object { W "  err| $_" }
        Get-Content (Join-Path $b 'apexdrv_probe.txt') -ErrorAction SilentlyContinue | ForEach-Object { W "  rep| $_" }
    } else { W "  probe skipped (late=$late)" }
} else { W 'S3 skipped - no live apex' }

SnapState 'end'
UnloadDrv
Hdr 'RESULT'
W "clean_driverless_pass = $clean"
if (-not $clean) { W 'driverless run still popped #95 => apexdrv is NOT the trigger; bisect machine config' }
W 'END'
