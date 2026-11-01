# p9.ps1 - ELEVATED. Is the Javelin popup FATAL or merely dismissible?
# p8 proved the popup fires with NO apexdrv loaded (everything driverless):
#   t~20s after launch, owner=csrss, class=#32770, body=
#   "Device Driver signing integrity checks must be enabled to start the game."
# probe7 missed it because csrss has no MainWindowTitle.
# p9 clicks OK and KEEPS WATCHING: does apex boot? does the #95 text follow?
# If apex survives -> load apexdrv LATE and probe the live game from kernel.
$ErrorActionPreference = 'Continue'
$log     = 'C:\qkp\p9.txt'
$b       = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build'
$drv     = 'C:\Windows\System32\drivers\apexdrv.sys'
$apexExe = 'C:\Program Files\EA Games\Apex\r5apex_dx12.exe'

function W($t) { ("{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $t) | Out-File -Encoding ascii -Append $log }
function Hdr($t) { W ''; W ("===== $t =====") }
Remove-Item $log -ErrorAction SilentlyContinue
Hdr 'p9 start'
W ('elevated : ' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
$sbstate = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue
W ('secureboot reg UEFISecureBootEnabled = ' + $sbstate.UEFISecureBootEnabled)
$bcd = (& bcdedit /enum 2>&1 | Out-String)
W ('testsigning=' + ($bcd -match 'testsigning\s+Yes') + '  nointegrity=' + ($bcd -match 'nointegritychecks\s+Yes') + '  dse_off_hint=' + ($bcd -match 'Disable Driver Signature'))
W ('cert CN=ApexDrv Dev present in Root = ' + [bool](Get-ChildItem Cert:\LocalMachine\Root -ErrorAction SilentlyContinue | Where-Object { $_.Subject -match 'ApexDrv' }))
W ('cert CN=ApexDrv Dev present in TrustedPublisher = ' + [bool](Get-ChildItem Cert:\LocalMachine\TrustedPublisher -ErrorAction SilentlyContinue | Where-Object { $_.Subject -match 'ApexDrv' }))

Add-Type -Namespace U -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
[DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
'@

function WTxt($h) { $s = New-Object Text.StringBuilder 512; $null = [U.Win]::GetWindowText($h, $s, 512); $s.ToString() }
function WCls($h) { $s = New-Object Text.StringBuilder 256; $null = [U.Win]::GetClassName($h, $s, 256); $s.ToString() }
function PName($q) { (Get-Process -Id $q -ErrorAction SilentlyContinue).ProcessName }
$GW_CHILD = 5; $GW_HWNDNEXT = 2; $BM_CLICK = 0xF5
function TopWindows { $h = [U.Win]::GetWindow([U.Win]::GetDesktopWindow(), $GW_CHILD); while ($h -ne [IntPtr]::Zero) { $h; $h = [U.Win]::GetWindow($h, $GW_HWNDNEXT) } }

$script:seenPopup = @{}
$script:nSigning = 0
$script:nUnacceptable = 0
# log every new popup body once; click OK; keep going
function DialogScan($tag) {
    $hit = $false
    foreach ($h in (TopWindows)) {
        if (-not [U.Win]::IsWindowVisible($h)) { continue }
        $c = WCls $h; if ($c -ne '#32770') { continue }
        $title = WTxt $h; $body = $title
        $ch = [U.Win]::GetWindow($h, $GW_CHILD)
        while ($ch -ne [IntPtr]::Zero) {
            if ((WCls $ch) -eq 'Static') { $body += ' | ' + (WTxt $ch) }
            $ch = [U.Win]::GetWindow($ch, $GW_HWNDNEXT)
        }
        if ($body -notmatch 'Javelin|unacceptable|Security Violation|signing integrity|tampering') { continue }
        $hit = $true
        $key = $body
        if (-not $script:seenPopup.ContainsKey($key)) {
            $script:seenPopup[$key] = 1
            $o = 0; $null = [U.Win]::GetWindowThreadProcessId($h, [ref]$o)
            W ("[$tag] NEW POPUP proc=$(PName $o) class=$c")
            W ("[$tag]   body: $body")
            if ($body -match 'signing integrity') { $script:nSigning++ }
            if ($body -match 'unacceptable') { $script:nUnacceptable++ }
        }
        # click OK and do NOT kill anything
        $ch = [U.Win]::GetWindow($h, $GW_CHILD)
        while ($ch -ne [IntPtr]::Zero) {
            if (((WCls $ch) -eq 'Button') -and ((WTxt $ch) -match '^\s*&?OK\s*$')) {
                $null = [U.Win]::SendMessage($ch, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
                W "[$tag] clicked OK on a Javelin popup (continuing)"
            }
            $ch = [U.Win]::GetWindow($ch, $GW_HWNDNEXT)
        }
    }
    return $hit
}


function ServState { return ((& sc.exe query apexdrv 2>&1 | Out-String) -match 'SERVICE_NAME') }
function SnapState($tag) {
    $n = (Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1)
    $r = ((& sc.exe query apexdrv 2>&1 | Out-String) -match 'RUNNING')
    W "[$tag] r5apex=$($n.Id) apexdrv_registered=$(ServState) running=$r"
}
function KillGame {
    foreach ($n in 'r5apex_dx12', 'EAAntiCheat.GameService', 'EAAntiCheat.GameServiceLauncher', 'EACefSubProcess') {
        Get-Process $n -ErrorAction SilentlyContinue | ForEach-Object { W "  kill $($_.ProcessName) ($($_.Id))"; try { $_.Kill() } catch {} }
    }
    Start-Sleep -Seconds 8
}
function LoadDrv {
    Copy-Item (Join-Path $b 'apexdrv.sys') $drv -Force
    if (-not (ServState)) { (& sc.exe create apexdrv binPath= '\??\C:\Windows\System32\drivers\apexdrv.sys' type= kernel start= demand error= normal 2>&1) | ForEach-Object { W "  create| $_" } }
    (& sc.exe start apexdrv 2>&1) | ForEach-Object { W "  start| $_" }
    Start-Sleep -Seconds 2
}
function UnloadDrv {
    (& sc.exe stop apexdrv 2>&1) | Out-Null
    (& sc.exe delete apexdrv 2>&1) | ForEach-Object { W "  delete| $_" }
}

# ------------------------------------------------------------------ P1
Hdr 'P1 - apex with NO apexdrv, dismiss every Javelin popup, keep watching 300s'
KillGame
W ('[p1] apexdrv registered = ' + (ServState))
Start-Process -FilePath $apexExe -WorkingDirectory (Split-Path $apexExe)
W '[p1] apex launched (direct exe)'
$p1popup = $false
for ($i = 1; $i -le 60; $i++) {
    Start-Sleep -Seconds 5
    $t = $i * 5
    if (DialogScan 'p1') { $p1popup = $true }
    $p = Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p) {
        if ($i % 3 -eq 0) { W "[p1] t=${t}s apex ALIVE pid=$($p.Id) up=$([int]((Get-Date) - $p.StartTime).TotalSeconds)s" }
    } elseif ($i % 6 -eq 0) { W "[p1] t=${t}s no apex process" }
}
$live = Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1
W "P1 RESULT popup_seen=$p1popup apex_alive=$([bool]$live) pid=$($live.Id) popups_sign=$($script:nSigning) popups_unacc=$($script:nUnacceptable)"

# ------------------------------------------------------------------ P2
if ($live) {
    Hdr 'P2 - apex is LIVE driverless: load apexdrv LATE, watch 180s, then probe'
    LoadDrv
    W ('  driver: ' + ((& sc.exe query apexdrv 2>&1 | Out-String) -match 'RUNNING'))
    $late = $false
    for ($i = 1; $i -le 36; $i++) {
        Start-Sleep -Seconds 5
        if (DialogScan 'p2') { $late = $true; W "[p2] popup at t=$($i*5)s AFTER driver load" }
        if (-not (Get-Process r5apex_dx12 -ErrorAction SilentlyContinue)) { W "[p2] apex DIED at t=$($i*5)s after driver load"; break }
    }
    $alive = [bool](Get-Process r5apex_dx12 -ErrorAction SilentlyContinue)
    W "P2 RESULT popup_after_driver_load=$late apex_alive=$alive"
    $ap = Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ap) {
        W "  target pid=$($ap.Id) uptime=$([int]((Get-Date) - $ap.StartTime).TotalSeconds)s"
        $out = 'C:\qkp\p9_out.txt'; $err = 'C:\qkp\p9_err.txt'
        Remove-Item $out, $err -ErrorAction SilentlyContinue
        $pr = Start-Process -FilePath (Join-Path $b 'apex_launcher.exe') `
                            -ArgumentList @('--kernel-probe', "--pid=$($ap.Id)", '--no-wait', "--driver=$drv") `
                            -WorkingDirectory $b -Wait -PassThru `
                            -RedirectStandardOutput $out -RedirectStandardError $err
        W "  PROBE_EXIT=$($pr.ExitCode)"
        Get-Content $out -ErrorAction SilentlyContinue | ForEach-Object { W "  | $_" }
        Get-Content $err -ErrorAction SilentlyContinue | ForEach-Object { W "  err| $_" }
        Get-Content (Join-Path $b 'apexdrv_probe.txt') -ErrorAction SilentlyContinue | ForEach-Object { W "  rep| $_" }
    } else { W '  probe skipped - apex not alive' }
} else { W 'P2 skipped - apex never came up driverless' }

Hdr 'RESULT'
W "popup_with_no_driver     = $p1popup"
W ('apex_alive_driverless    = ' + [bool]$live)
W ('apexdrv blamed for popup = ' + (-not $p1popup))
W "popup_kinds: signing=$($script:nSigning) unacceptable=$($script:nUnacceptable)"
SnapState 'end'
UnloadDrv
W 'END'
