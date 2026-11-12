# h329_vmbench.ps1 - R1 bench for g329_readonly.ps1 (driver v14 READ-ONLY survival) in Win11-Test2.
# Snapshot FIRST, boot headless, push {kdu.exe, drv64.dll, zapexdrv.sys, g329_readonly.ps1,
# h328_vadbase.ps1} into the guest p37, run g329 there (it loads the driver, does the notepad
# acceptance, runs h328, +60/+300 survival, tears down), pull g329_readonly.out + h328_vadbase.out
# back, then poweroff + revert to the ga-armed snapshot. Host is NOT touched (no kdu, no DSE).
# R5: own files only (h329_vmbench.out); snapshot name carries the time.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h329_vmbench.out'
$vb   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$vm   = 'Win11-Test2'
$snapBase = 'ga-armed'
$V14 = '317E4A86C1817401F98210434DE9DCDEA623086A46AA1C546A97ED833E0CA83C'
$pushd = 'C:\Users\Public\p37'
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
    # guestcontrol is flaky right after boot/state-restore; retry with backoff instead of failing.
    $last = ''
    for ($k = 1; $k -le $tries; $k++) {
        $last = V $a $cap
        if ($last -notmatch 'VBoxManage\.exe: error|not able to logon|VBOX_E_|Waiting for guest process failed') { return $last }
        W ('  guestcontrol retry ' + $k + '/' + $tries + ' (' + $a[1] + ')')
        Start-Sleep -Seconds 12
    }
    return $last
}
W ('===== h329 vmbench ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss') + ' =====')
W ('vm state=' + (V @('showvminfo', $vm, '--machinereadable') 30000).Substring(0, 40))

# --- payload pre-flight on the host side (refuse to push the wrong build) --------------------
$zs = Join-Path $pushd 'zapexdrv.sys'
$zh = if (Test-Path $zs) { (Get-FileHash $zs -Algorithm SHA256).Hash } else { 'MISSING' }
W ('host p37 zapexdrv.sys sha=' + $zh.Substring(0, [Math]::Min(16, $zh.Length)) + ' len=' + (Get-Item $zs -EA 0).Length)
if ($zh -ne $V14) { W 'RESULT: FAIL - host C:\Users\Public\p37\zapexdrv.sys is not the v14 build; build+stage first'; W 'VERDICT: no bench'; exit 1 }
$push = @($zs, (Join-Path $pushd 'kdu.exe'), (Join-Path $pushd 'drv64.dll'), (Join-Path $here 'g329_readonly.ps1'), (Join-Path $here 'h328_vadbase.ps1'))
foreach ($f in $push) { if (-not (Test-Path $f)) { W ('RESULT: FAIL - push source missing: ' + $f); exit 1 } }

# --- snapshot first (R1) --------------------------------------------------------------------
$snap = 'h329_pre_' + (Get-Date -f 'HHmmss')
W ('snapshot take ' + $snap + ' :: ' + (V @('snapshot', $vm, 'take', $snap, '--description', 'before h329 readonly bench (load v14, notepad acceptance, h328, +60/+300, teardown)') 120000))

# --- boot -----------------------------------------------------------------------------------
W ('startvm :: ' + (V @('startvm', $vm, '--type', 'headless') 120000))
$up = 0
for ($i = 1; $i -le 40; $i++) {
    Start-Sleep -Seconds 5
    $r = G @('guestcontrol', $vm, 'run', '--exe', 'C:\Windows\System32\cmd.exe', '--username', 'vboxuser', '--password', 'password', '--wait-stdout', '--', '/c', 'echo READY') 40000 2
    if ($r -match 'READY' -and $r -notmatch 'VBoxManage\.exe: error') { $up++; W ('guest answer ' + $up + '/2 at try ' + $i); if ($up -ge 2) { break } } else { $up = 0 }
    if ($i % 4 -eq 0) { W ('  try ' + $i + ': ' + $r.Substring(0, [Math]::Min(90, $r.Length))) }
}
if ($up -lt 2) { W 'guest never answered guestcontrol - RESULT: FAIL bench (no VM)'; V @('controlvm', $vm, 'poweroff') 60000; V @('snapshot', $vm, 'restore', $snap) 120000; exit 1 }
Start-Sleep -Seconds 15   # let logon tasks settle

# --- push payload + run g329 ----------------------------------------------------------------
W ('copyto :: ' + (G (@('guestcontrol', $vm, 'copyto') + $push + @('--target-directory', $pushd, '--username', 'vboxuser', '--password', 'password')) 120000))
$gr = G @('guestcontrol', $vm, 'run', '--exe', 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe', '--username', 'vboxuser', '--password', 'password', '--', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $pushd 'g329_readonly.ps1')) 900000
W ('guest run said :: ' + $gr.Substring(0, [Math]::Min(120, $gr.Length)))

# --- pull the guest verdicts out ------------------------------------------------------------
foreach ($gf in 'g329_readonly.out', 'h328_vadbase.out') {
    W ('copyfrom ' + $gf + ' :: ' + (G @('guestcontrol', $vm, 'copyfrom', (Join-Path $pushd $gf), '--target-directory', $here, '--username', 'vboxuser', '--password', 'password') 60000))
}
$g329o = Join-Path $here 'g329_readonly.out'
$verdict = 'MISSING'
if (Test-Path $g329o) {
    $g = Get-Content $g329o -Raw -EA 0
    W ('guest g329 out bytes=' + $g.Length)
    foreach ($ln in ($g -split "`r?`n" | Where-Object { $_ -match 'RESULT:|VERDICT:|ACCEPT |SURVIVAL|teardown:' } | Select-Object -Last 14)) { W ('  | ' + $ln) }
    $v = ($g -split "`r?`n" | Where-Object { $_ -match 'VERDICT: g329 ' } | Select-Object -Last 1)
    if ($v) { $verdict = $v }
} else { W 'guest g329 out MISSING' }

# --- revert (R4) ----------------------------------------------------------------------------
W ('poweroff :: ' + (V @('controlvm', $vm, 'poweroff') 60000))
Start-Sleep -Seconds 5
W ('snapshot restore ' + $snapBase + ' :: ' + (V @('snapshot', $vm, 'restore', $snapBase) 180000))
W ('final vm state: ' + (V @('showvminfo', $vm, '--machinereadable') 30000).Substring(0, 60))
W ('RESULT: vmbench done - guest verdict: ' + $verdict + ' (details in g329_readonly.out / h328_vadbase.out)')