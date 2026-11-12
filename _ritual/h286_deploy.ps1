# h286_deploy.ps1 - host side, VM-first (R1): snapshot the guest, then serve the v13 build and
# fire the p37tick. Gates BEFORE any copy: the source build must match the pinned v13 hash/size,
# or nothing is served. Read-back AFTER the copy: the SERVED files are re-hashed (R3) and the
# tick is fired only if every gate passed. Own output file per R5: _ritual\h286_deploy.txt.
$ErrorActionPreference = 'Continue'
$repo   = 'C:\Users\New User\OneDrive\Desktop\cheating'
$pay    = 'C:\p37vm\payload'
$out    = "$repo\_ritual\h286_deploy.txt"
$vb     = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$finger = 'CDB6BFAE8CC1867A4EDAE842D640DDF5C54D30EDDF086584CC03F075B53C5431'  # v13 apexdrv.sys
$exeLen = 473600                                                              # v13 apex_launcher.exe
Remove-Item -LiteralPath $out -Force -EA 0
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) }
W '=== h286 deploy: snapshot guest -> serve v13 -> fire tick ==='

# --- pre-state (R3: both halves before mutating anything) ---
$vmState = (& $vb showvminfo 'Win11-Test2' --machinereadable 2>$null | Select-String '^VMState=')
W ('pre vm: ' + $vmState)
$listen = @(Get-NetTCPConnection -LocalPort 8080 -State Listen -EA 0).Count
W ('pre listen8080=' + $listen)
foreach ($f in @('cur.ps1','zapexdrv.sys','apex_launcher.exe','apxprobe.dll','kdu.exe','drv64.dll','active.txt')) {
    $i = Get-Item -LiteralPath "$pay\$f" -EA 0
    if ($i) { W ('pre ' + $f + ' len=' + $i.Length + ' mtime=' + $i.LastWriteTime.ToString('MM-dd HH:mm:ss')) }
    else    { W ('pre ' + $f + ' MISSING') }
}
W ('pre guest-h286.log: ' + $(if (Test-Path 'C:\p37vm\guest-h286.log') { 'EXISTS (stale!)' } else { 'absent (fresh)' }))

# --- gate A: source build matches the pin (refuse to serve a stale/mismatched image) ---
$srcSys = "$repo\QwenKernPremium\build\apexdrv.sys"
$srcExe = "$repo\QwenKernPremium\build\apex_launcher.exe"
$srcCur = "$repo\_ritual\h286_cur.ps1"
if (-not ((Test-Path $srcSys) -and (Test-Path $srcExe) -and (Test-Path $srcCur))) {
    W ('RESULT: FAIL - source build missing: ' + "$srcSys / $srcExe / $srcCur"); exit 1
}
$h = (Get-FileHash $srcSys -Algorithm SHA256).Hash
$el = (Get-Item $srcExe).Length
W ('source apexdrv.sys sha=' + $h + ' (' + $(if ($h -eq $finger) { 'MATCH' } else { 'MISMATCH' }) + ') size=' + (Get-Item $srcSys).Length)
W ('source apex_launcher.exe len=' + $el + ' (' + $(if ($el -eq $exeLen) { 'MATCH' } else { 'MISMATCH' }) + ')')
if ($h -ne $finger -or $el -ne $exeLen) { W 'RESULT: FAIL - source gate mismatch, nothing served'; exit 1 }

# --- step 1: snapshot the guest BEFORE anything else (R1 rollback point) ---
$snap = & $vb snapshot 'Win11-Test2' take 'h286_pre_1106' --description 'pre h286 v13 verdict-plumbing run' 2>&1
W ('snapshot rc=' + $LASTEXITCODE + ' out=[' + (($snap | Out-String).Trim() -replace '\s+', ' ') + ']')
if ($LASTEXITCODE -ne 0) { W 'RESULT: FAIL - snapshot refused, no rollback point, nothing served'; exit 1 }

# --- step 2: backups of what is being replaced (reversibility, R4) ---
foreach ($p in @(@('cur.ps1','cur_h285_bak.ps1'), @('zapexdrv.sys','zapexdrv_h285_bak.sys'), @('apex_launcher.exe','apex_launcher_h285_bak.exe'))) {
    if (Test-Path -LiteralPath "$pay\$($p[0])") {
        Copy-Item -LiteralPath "$pay\$($p[0])" -Destination "$pay\$($p[1])" -Force
        W ('backup ' + $p[0] + ' -> ' + $p[1])
    }
}
Copy-Item -LiteralPath "$pay\cur.ps1" -Destination "$pay\cur.ps1.prev" -Force -EA 0

# --- step 3: serve ---
Copy-Item -LiteralPath $srcCur -Destination "$pay\cur.ps1" -Force
Copy-Item -LiteralPath $srcSys -Destination "$pay\zapexdrv.sys" -Force
Copy-Item -LiteralPath $srcExe -Destination "$pay\apex_launcher.exe" -Force
Set-Content -LiteralPath "$pay\active.txt" -Value 'h286' -Encoding ascii
W 'served cur.ps1 + zapexdrv.sys + apex_launcher.exe; active.txt=h286'

# --- step 4: read-back of the SERVED files (R3: the read-back is the only verdict) ---
$h2 = (Get-FileHash "$pay\zapexdrv.sys" -Algorithm SHA256).Hash
$e2 = (Get-Item "$pay\apex_launcher.exe").Length
$c2 = (Get-FileHash "$pay\cur.ps1" -Algorithm SHA256).Hash
$cS = (Get-FileHash $srcCur -Algorithm SHA256).Hash
$listen2 = @(Get-NetTCPConnection -LocalPort 8080 -State Listen -EA 0).Count
W ('served sys sha=' + $(if ($h2 -eq $finger) { 'MATCH' } else { 'MISMATCH ' + $h2 }))
W ('served exe len=' + $e2 + ' (' + $(if ($e2 -eq $exeLen) { 'MATCH' } else { 'MISMATCH' }) + ')')
W ('served cur.ps1 sha=' + $(if ($c2 -eq $cS) { 'MATCH' } else { 'MISMATCH' }) + ' len=' + (Get-Item "$pay\cur.ps1").Length)
W ('post listen8080=' + $listen2)
if ($h2 -ne $finger -or $e2 -ne $exeLen -or $c2 -ne $cS -or $listen2 -lt 1) {
    W 'RESULT: FAIL - served-file read-back mismatch, tick NOT fired'; exit 1
}

# --- step 5: fire (one manual schtasks /run per rung; password per HANDOFF, fallback vboxuser) ---
$r1 = & schtasks.exe /run /tn p37tick /s 192.168.56.101 /u vboxuser /p password 2>&1
W ('fire[pw1] rc=' + $LASTEXITCODE + ' out=[' + (($r1 | Out-String).Trim() -replace '\s+', ' ') + ']')
if ($LASTEXITCODE -ne 0) {
    $r2 = & schtasks.exe /run /tn p37tick /s 192.168.56.101 /u vboxuser /p vboxuser 2>&1
    W ('fire[pw2] rc=' + $LASTEXITCODE + ' out=[' + (($r2 | Out-String).Trim() -replace '\s+', ' ') + ']')
    if ($LASTEXITCODE -ne 0) { W 'RESULT: DEPLOYED but tick fire FAILED - poll guest-h286.log anyway, then reset/revive'; exit 2 }
}
W 'RESULT: DEPLOYED + FIRED - poll C:\p37vm\guest-h286.log (run window up to ~5 min, inject cap 180 s)'
W 'VERDICT: pending guest-h286.log'
