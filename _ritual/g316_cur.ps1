# g316_cur.ps1 - VM BENCH payload for h316, deployed as C:\p37vm\payload\cur.ps1 so the guest tick
# (p37tick -> run.cmd -> once.cmd -> cur.ps1) pulls and runs it. No guest additions involved: the
# guestcontrol path is dead on this VM (GA RunLevel 3 but session start fails).
# It runs the ORDER h316 uses in the probe (0 first, DirectIo64 14/27 + WinRing0 22 last) with a
# per-provider durable POST, and stops at the first provider that answers. No DSE write, no driver.
# Boot-gated like every cur.ps1: one run per boot, so a re-firing tick cannot repeat the sweep.
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::Expect100Continue = $false
$base = 'http://10.0.2.2:8080'
$d    = 'C:\Users\Public\p37'
$tag  = 'g316'
$done = "$d\g316.done"
$L    = New-Object System.Collections.ArrayList
function W([string]$s) { [void]$L.Add(((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s)) }
function Post {
    $body = if ($L.Count -gt 150) { ('...' + ($L.Count - 150) + ' earlier lines not uploaded') + "`r`n" + (($L | Select-Object -Last 150) -join "`r`n") } else { $L -join "`r`n" }
    for ($k = 1; $k -le 2; $k++) {
        try { [void](Invoke-WebRequest -Uri "$base/log?vm=$tag" -Method Post -Body ("## $tag`r`n" + $body) -TimeoutSec 10 -UseBasicParsing -EA Stop); break }
        catch { Start-Sleep -Milliseconds 400 }
    }
}
md $d -Force | Out-Null
$os = Get-CimInstance Win32_OperatingSystem
$bootId = $os.LastBootUpTime.Ticks
if (Test-Path $done) {
    $old = @(Get-Content -LiteralPath $done -EA 0)
    if ($old.Count -ge 1 -and [long]$old[0] -eq $bootId) { exit 0 }
}
Set-Content -LiteralPath $done -Value ($bootId, (Get-Date).ToFileTime())
W ('alive build=' + $os.BuildNumber + ' boot=' + $os.LastBootUpTime.ToString('dd/MM HH:mm:ss'))
$kdu = Join-Path $d 'kdu.exe'
if (-not (Test-Path $kdu) -or (Get-Item $kdu -EA 0).Length -lt 400000) {
    W 'kdu missing - fetching from the relay'
    foreach ($n in 'kdu.exe', 'drv64.dll') {
        try { (New-Object Net.WebClient).DownloadFile("$base/$n", (Join-Path $d $n)) } catch { W ('  fetch ' + $n + ' FAIL ' + $_.Exception.Message) }
    }
}
if (-not (Test-Path $kdu)) { W 'RESULT: FAIL - no kdu in the guest and not fetchable'; Post; exit 1 }
W ('kdu sha=' + (Get-FileHash $kdu -Algorithm SHA256).Hash.Substring(0, 16))
& $kdu -listcsv (Join-Path $d 'kdu_list.csv') 2>&1 | Out-Null
$ids = @(); $names = @{}
foreach ($row in (Get-Content (Join-Path $d 'kdu_list.csv') -EA 0)) {
    if ($row -match '^\s*"?(\d{1,3})"?,[^,]*,"([^"]*)"') { $ids += [int]$matches[1]; $names[[int]$matches[1]] = $matches[2] }
}
$ids = @($ids | Select-Object -Unique)
$suspect = @(14, 27, 22)
$order = @($ids | Where-Object { $suspect -notcontains $_ }) + @($suspect | Where-Object { $ids -contains $_ })
W ('STEP=order ids=' + $ids.Count + ' head=' + (($order | Select-Object -First 6) -join ',') + ' tail=' + (($order | Select-Object -Last 5) -join ','))
$got = ''; $winner = -1; $n = 0
foreach ($id in $order) {
    $n++
    W ('STEP=prov ' + $id + ' ' + $(if ($names.ContainsKey($id)) { $names[$id] } else { '?' }) + ' (' + $n + '/' + $order.Count + ')')
    Post
    $o = (& $kdu -prv $id -dse 2>&1) -join "`n"
    if ($o -match 'value:\s*([0-9A-Fa-f]+)') { $got = $matches[1]; $winner = $id; break }
    W ('  no value: [' + (($o -replace '\s+', ' ').Trim()) + ']')
}
if ($winner -ge 0) {
    W ('RESULT: PASS - dse read 0x' + $got + ' via prv ' + $winner + ' (' + $(if ($names.ContainsKey($winner)) { $names[$winner] } else { '?' }) + ') after ' + $n + ' provider(s)')
    W 'VERDICT: BENCH PASS - ordered read completes in the VM, no bugcheck, suspects ' + $(if ($order.IndexOf($winner) -ge ($order.Count - 3)) { 'WERE reached' } else { 'untouched' })
} else {
    W 'RESULT: FAIL - no provider returned a DSE value (' + $order.Count + ' tried)'
    W 'VERDICT: BENCH FAIL - every provider refused in the VM'
}
Post
Set-Content -LiteralPath "$d\g316.report" -Value ($L -join "`r`n")
exit 0
