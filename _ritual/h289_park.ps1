# h289_park.ps1 - deploy the PARK payload as the guest tick's cur.ps1, then prove the server is
# actually serving those bytes (R3: the read-back is the only verdict - a written file that the
# listener does not serve would park nothing, because once.cmd pulls over HTTP, not from disk).
#
# One variable: cur.ps1 content (h286 driver probe -> read-only park payload). No kernel state,
# no boot config, no scheduled task, no guest mutation of any kind is touched here.
# Reversible (R4): payload\cur_h289_live.ps1 is the exact pre-image; copy it back over cur.ps1
# and the next tick runs the real probe again. Re-runnable: the backup is taken once.
# Own output (R5): _ritual\h289_park.txt.
$vb   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$vm   = 'Win11-Test2'
$doc  = 'C:\p37vm\payload'
$live = Join-Path $doc 'cur.ps1'
$bak  = Join-Path $doc 'cur_h289_live.ps1'
$src  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\h289_park_payload.ps1'
$out  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\h289_park.txt'
Remove-Item -LiteralPath $out -Force -EA 0
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) }
function Hash([string]$p) { if (Test-Path -LiteralPath $p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } else { 'ABSENT' } }
W '=== h289 park: swap cur.ps1 to a read-only park payload (variable: payload content) ==='
if (-not (Test-Path -LiteralPath $src)) { W ('FAIL source missing: ' + $src); W 'RESULT: FAIL - park payload source absent (variable: payload content)'; exit 1 }

# --- pre-state ---
try {
    $mi = & $vb showvminfo $vm --machinereadable 2>&1
    W ('pre vm: ' + ((($mi | Select-String '^VMState=').Line) -replace '"', '') + ' ' + ((($mi | Select-String '^GuestAdditionsRunLevel=').Line) -replace '"', ''))
} catch { W ('pre vm: query failed ' + $_.Exception.Message) }
$lis = @(Get-NetTCPConnection -LocalPort 8080 -State Listen -EA 0)
W ('pre listener 8080: count=' + $lis.Count + ' pid=' + (($lis | ForEach-Object { $_.OwningProcess }) -join ','))
W ('pre cur.ps1: ' + $(if (Test-Path -LiteralPath $live) { (Get-Item -LiteralPath $live).Length.ToString() + 'b ' + (Get-Item -LiteralPath $live).LastWriteTime.ToString('dd/MM HH:mm:ss') } else { 'ABSENT' }) + ' sha=' + (Hash $live))
W ('pre backup: ' + $(if (Test-Path -LiteralPath $bak) { 'exists ' + (Get-Item -LiteralPath $bak).Length + 'b' } else { 'absent (will create)' }))
W ('src park payload: ' + (Get-Item -LiteralPath $src).Length + 'b sha=' + (Hash $src))

# --- backup (R4: taken once, so a re-run never overwrites the true pre-image) ---
if (-not (Test-Path -LiteralPath $bak)) {
    try { Copy-Item -LiteralPath $live -Destination $bak -Force -EA Stop; W ('backup written: cur_h289_live.ps1 sha=' + (Hash $bak)) }
    catch { W ('backup FAILED: ' + $_.Exception.Message); W 'RESULT: FAIL - could not back up cur.ps1, nothing deployed (variable: payload content)'; exit 1 }
} else { W ('backup kept: sha=' + (Hash $bak)) }

# --- deploy: byte copy through the filesystem, then the HTTP read-back decides ---
try { Copy-Item -LiteralPath $src -Destination $live -Force -EA Stop } catch { W ('deploy FAILED: ' + $_.Exception.Message); W 'RESULT: FAIL - copy to cur.ps1 failed (variable: payload content)'; exit 1 }
W ('deployed: cur.ps1 now ' + (Get-Item -LiteralPath $live).Length + 'b sha=' + (Hash $live))
$localHash = Hash $live

# --- read-back 1: what the listener actually hands the guest (this is the only one that counts) ---
$served = 'FAIL'; $servedHash = 'n/a'; $servedLen = 0; $marker = 'no'
for ($i = 1; $i -le 3; $i++) {
    try {
        $wc = New-Object Net.WebClient
        $bytes = $wc.DownloadData('http://127.0.0.1:8080/cur.ps1')
        $servedLen = $bytes.Length
        $servedHash = ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)) -replace '-', '')
        $text = [Text.Encoding]::ASCII.GetString($bytes)
        if ($text -match 'PARK payload') { $marker = 'yes' }
        $served = 'ok'
        break
    } catch { Start-Sleep -Milliseconds 400 }
}
W ('http read-back: ' + $served + ' bytes=' + $servedLen + ' sha=' + $servedHash)
W ('  marker "PARK payload" in served bytes: ' + $marker)
$same = ($servedHash -eq $localHash)
W ('  served == local: ' + $same)

# --- read-back 2: the listener must still be the same process for the next tick ---
$lis2 = @(Get-NetTCPConnection -LocalPort 8080 -State Listen -EA 0)
W ('post listener 8080: count=' + $lis2.Count + ' pid=' + (($lis2 | ForEach-Object { $_.OwningProcess }) -join ','))
W ('revert command: Copy-Item -LiteralPath ''' + $bak + ''' -Destination ''' + $live + ''' -Force')
if ($served -eq 'ok' -and $same -and $marker -eq 'yes' -and $lis2.Count -ge 1) {
    W 'RESULT: PASS - guest tick will now pull the park payload (variable: cur.ps1 content)'
    W 'VERDICT: served bytes hash-match the park payload; listener alive; next boot reports its own crash evidence'
} else {
    W ('RESULT: FAIL - served=' + $served + ' same=' + $same + ' marker=' + $marker + ' listener=' + $lis2.Count + ' (variable: cur.ps1 content)')
    W 'VERDICT: do NOT nudge the guest - a stale payload would re-run the h286 probe and crash-loop again'
    exit 1
}
