# h316_vmbench.ps1 - R1 bench of the h316 provider ORDER in Win11-Test2 (VirtualBox, headless).
# Snapshot FIRST, then boot, then run g316_sweep.ps1 in the guest over guestcontrol, then pull the
# guest result out and revert the VM to the pre-bench snapshot. Host is not touched (no kdu, no DSE).
# R5: own files only (h316_vmbench.out, g316_sweep_guest.out); the snapshot name carries the time.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h316_vmbench.out'
$vb   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$vm   = 'Win11-Test2'
$snapBase = 'ga-armed'   # p37-ready has GA present but never started (RunLevel 0, guestcontrol unusable); ga-armed runs GA (RunLevel 3, measured 21:59). h286_pre_1106 and that lineage boot to Windows "Automatic Repair".
$gsrc = Join-Path $here 'g316_sweep.ps1'
$gloc = 'C:\Users\Public\p37\g316_sweep.out'
$gout = Join-Path $here 'g316_sweep_guest.out'
$L = New-Object System.Collections.Generic.List[string]
function W([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line; Set-Content -LiteralPath $out -Value ($L -join "`r`n") }
function V([string[]]$a, [int]$cap = 60000) {
    $o = ''; $e = ''
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $vb; $psi.Arguments = (($a | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
        $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $t1 = $p.StandardOutput.ReadToEndAsync(); $t2 = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($cap)) { W ('  VBOX TIMEOUT ' + $cap); try { $p.Kill() } catch { } }
        try { $o = $t1.Result; $e = $t2.Result } catch { }
    } catch { $e = $_.Exception.Message }
    return (($o + ' ' + $e) -replace '\s+', ' ').Trim()
}
function G([string[]]$a, [int]$cap = 60000, [int]$tries = 12) {
    # guestcontrol is flaky in the first minutes after boot/state-restore ("user was not able to
    # logon", "Guest Additions are not ready yet") and then settles; retry with backoff rather than
    # failing the bench on it.
    $last = ''
    for ($k = 1; $k -le $tries; $k++) {
        $last = V $a $cap
        if ($last -notmatch 'VBoxManage\.exe: error|not able to logon|VBOX_E_|Waiting for guest process failed') { return $last }
        W ('  guestcontrol retry ' + $k + '/' + $tries + ' (' + $a[1] + ')')
        Start-Sleep -Seconds 12
    }
    return $last
}
W ('===== h316 vmbench ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss') + ' =====')
W ('vm state=' + (V @('showvminfo', $vm, '--machinereadable') 30000).Substring(0, 40))
try { $relay = (Invoke-WebRequest 'http://127.0.0.1:8080/zapexdrv.sys' -UseBasicParsing -TimeoutSec 8).RawContentLength; W ('relay=' + $relay) } catch { W 'relay=DOWN' }

# --- snapshot first (R1) -------------------------------------------------------------------
$snap = 'h316_pre_' + (Get-Date -f 'HHmmss')
W ('snapshot take ' + $snap + ' :: ' + (V @('snapshot', $vm, 'take', $snap, '--description', 'before h316 provider-order bench (0 first, 14/27/22 last)') 120000))
$snaprb = @((V @('snapshot', $vm, 'list', '--machinereadable') 30000) -split '\s+' | Where-Object { $_ -match 'CurrentSnapshotName' })
W ('snapshot readback: ' + ($snaprb -join ' '))

# --- boot ----------------------------------------------------------------------------------
W ('startvm :: ' + (V @('startvm', $vm, '--type', 'headless') 120000))
$up = 0
for ($i = 1; $i -le 40; $i++) {
    Start-Sleep -Seconds 5
    $r = G @('guestcontrol', $vm, 'run', '--exe', 'C:\Windows\System32\cmd.exe', '--username', 'vboxuser', '--password', 'password', '--wait-stdout', '--', '/c', 'echo READY') 40000 2
    if ($r -match 'READY' -and $r -notmatch 'VBoxManage\.exe: error') { $up++; W ('guest answer ' + $up + '/2 at try ' + $i); if ($up -ge 2) { break } } else { $up = 0 }
    if ($i % 4 -eq 0) { W ('  try ' + $i + ': ' + $r.Substring(0, [Math]::Min(90, $r.Length))) }
}
if ($up -lt 2) { W 'guest never answered guestcontrol - RESULT: FAIL bench (no VM)'; V @('controlvm', $vm, 'poweroff') 60000; V @('snapshot', $vm, 'restore', $snap) 120000; exit 1 }
Start-Sleep -Seconds 15   # let logon tasks settle before the sweep

# --- stage + run the sweep -----------------------------------------------------------------
W ('copyto :: ' + (G @('guestcontrol', $vm, 'copyto', $gsrc, '--target-directory', 'C:\Users\Public\p37', '--username', 'vboxuser', '--password', 'password') 60000))
W ('run sweep :: ' + (G @('guestcontrol', $vm, 'run', '--exe', 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe', '--username', 'vboxuser', '--password', 'password', '--', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\Users\Public\p37\g316_sweep.ps1') 600000))

# --- pull the guest verdict out ------------------------------------------------------------
W ('copyfrom :: ' + (G @('guestcontrol', $vm, 'copyfrom', $gloc, '--target-directory', $here, '--username', 'vboxuser', '--password', 'password') 60000))
if (Test-Path $gout) {
    $g = Get-Content $gout -Raw -EA 0
    W ('guest out bytes=' + $g.Length)
    foreach ($ln in ($g -split "`r?`n" | Where-Object { $_ -match 'RESULT:|VERDICT:|STEP=prov' } | Select-Object -Last 12)) { W ('  | ' + $ln) }
} else { W 'guest out MISSING' }

# --- revert (R4) ---------------------------------------------------------------------------
W ('poweroff :: ' + (V @('controlvm', $vm, 'poweroff') 60000))
Start-Sleep -Seconds 5
W ('snapshot restore ' + $snapBase + ' :: ' + (V @('snapshot', $vm, 'restore', $snapBase) 180000))
W ('final vm state: ' + (V @('showvminfo', $vm, '--machinereadable') 30000).Substring(0, 60))
W ('RESULT: vmbench done - verdict is in ' + $gout)
