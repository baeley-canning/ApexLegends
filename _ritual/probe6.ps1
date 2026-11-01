# probe6.ps1 - ELEVATED. Make a real target exist, then run the kernel probe
# against it with a real PID (no 120 s wait-for-game stall), and capture the
# report from a redirected file so nothing is hidden by pipeline buffering.
$ErrorActionPreference = 'Continue'
$log = 'C:\qkp\probe6.txt'
function W([string] $t) { $t | Out-File -Encoding utf8 -Append $log }

$b   = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build'
$drv = 'C:\Windows\System32\drivers\apexdrv.sys'
$apexExe = 'C:\Program Files\EA Games\Apex\r5apex_dx12.exe'

"== probe6 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==" | Out-File -Encoding utf8 $log
$bcd = (& bcdedit /enum '{current}' 2>&1 | Out-String)
W "testsigning active : $($bcd -match 'testsigning\s+Yes')"

# --- driver staged + service up -------------------------------------------------
if (-not (Test-Path $drv)) { Copy-Item 'C:\ProgramData\QwenKern\apexdrv.sys' $drv -Force }
W "driver : $((Get-Item $drv).Length) B sig=$((Get-AuthenticodeSignature $drv).Status)"
if (-not ((& sc.exe query apexdrv) 2>&1 | Select-String -SimpleMatch 'SERVICE_NAME')) {
    (& sc.exe create apexdrv binPath= '\??\C:\Windows\System32\drivers\apexdrv.sys' type= kernel start= demand error= normal) 2>&1 |
        ForEach-Object { W "  create| $_" }
}
if ((Get-Service apexdrv -ErrorAction SilentlyContinue).Status -ne 'Running') {
    (& sc.exe start apexdrv) 2>&1 | ForEach-Object { W "  start| $_" }
}
W "service : $((Get-Service apexdrv -ErrorAction SilentlyContinue).Status)"

# --- make a target exist -------------------------------------------------------
if (-not (Get-Process EADesktop -ErrorAction SilentlyContinue)) {
    $ea = @(
        'C:\Program Files\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe',
        'C:\Program Files (x86)\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe',
        (Get-ChildItem 'C:\Program Files','C:\Program Files (x86)' -Filter 'EADesktop.exe' -Recurse -Depth 4 -File -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName)
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if ($ea) { Start-Process -FilePath $ea; W "EA app started: $ea"; Start-Sleep -Seconds 30 }
    else     { W 'EA app not found - launching the game exe anyway' }
}

if (-not (Get-Process r5apex_dx12 -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath $apexExe -WorkingDirectory (Split-Path $apexExe)
    W "apex launched: $apexExe"
}

# --- wait for the process to actually exist (up to 5 min) ----------------------
$pid_ = 0
for ($i = 0; $i -lt 100; $i++) {
    $pid_ = (Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1).Id
    if ($pid_) { break }
    Start-Sleep -Seconds 3
    if ($i % 5 -eq 4) { W "  waiting for r5apex_dx12 ... $((($i + 1) * 3)) s" }
}
W "apex pid : $pid_"
if (-not $pid_) { W 'no target - stopping'; W 'END'; return }

# let the process finish starting (anti-cheat + module load) before poking it
Start-Sleep -Seconds 30
W "apex uptime now : $([int]((Get-Date) - (Get-Process -Id $pid_).StartTime).TotalSeconds) s"

# --- the probe, with a real PID, output straight to a file ---------------------
$out = 'C:\qkp\probe6_out.txt'
$err = 'C:\qkp\probe6_err.txt'
Remove-Item $out, $err -ErrorAction SilentlyContinue
$p = Start-Process -FilePath (Join-Path $b 'apex_launcher.exe') `
                   -ArgumentList @('--kernel-probe', "--pid=$pid_", '--no-wait', "--driver=$drv") `
                   -WorkingDirectory $b -Wait -PassThru `
                   -RedirectStandardOutput $out -RedirectStandardError $err
W "PROBE_EXIT=$($p.ExitCode)"
W '--- probe stdout ---'
if (Test-Path $out) { Get-Content $out | ForEach-Object { W "  | $_" } }
if (Test-Path $err) { Get-Content $err | ForEach-Object { W "  err| $_" } }

W "service after probe : $((Get-Service apexdrv -ErrorAction SilentlyContinue).Status)"
$rep = Join-Path $b 'apexdrv_probe.txt'
W "report : $rep  exists=$((Test-Path $rep))"
if (Test-Path $rep) { W "  tap=$((Get-Item $rep).LastWriteTime.ToString('HH:mm:ss'))"; Get-Content $rep | ForEach-Object { W "  rep| $_" } }
W 'END'
