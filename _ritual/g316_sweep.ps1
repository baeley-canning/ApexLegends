# g316_sweep.ps1 - GUEST side of the h316 R1 bench. Runs the exact provider ORDER that
# cur_h316_live.ps1 uses (0 first, DirectIo64 14/27 and WinRing0 22 last) against the guest's own
# kdu, with the same durable mark line, and stops at the first provider that answers.
# No DSE write, no driver, no payload: this bench is only "does the ordered read survive".
$ErrorActionPreference = 'Continue'
$d   = 'C:\Users\Public\p37'
$out = Join-Path $d 'g316_sweep.out'
$L = New-Object System.Collections.Generic.List[string]
function W([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Add-Content -LiteralPath $out -Value $line -EA 0 }
Add-Content -LiteralPath $out -Value ('===== g316 sweep ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss') + ' =====') -EA 0
W ('host=' + $env:COMPUTERNAME + ' build=' + (Get-CimInstance Win32_OperatingSystem).BuildNumber + ' boot=' + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('s'))
$kdu = Join-Path $d 'kdu.exe'
if (-not (Test-Path $kdu) -or (Get-Item $kdu -EA 0).Length -lt 400000) {
    W 'kdu missing - fetching from the host relay 10.0.2.2:8080'
    foreach ($n in 'kdu.exe', 'drv64.dll') {
        try { (New-Object Net.WebClient).DownloadFile("http://10.0.2.2:8080/$n", (Join-Path $d $n)) } catch { W ('  fetch ' + $n + ' FAIL ' + $_.Exception.Message) }
    }
}
if (-not (Test-Path $kdu)) { W 'RESULT: FAIL - kdu.exe missing in C:\Users\Public\p37 and not fetchable'; exit 1 }
W ('kdu sha=' + (Get-FileHash $kdu -Algorithm SHA256).Hash.Substring(0, 16) + ' drv64=' + (Test-Path (Join-Path $d 'drv64.dll')))
& $kdu -listcsv (Join-Path $d 'kdu_list.csv') 2>&1 | Out-Null
$ids = @(); $names = @{}
foreach ($row in (Get-Content (Join-Path $d 'kdu_list.csv') -EA 0)) {
    if ($row -match '^\s*"?(\d{1,3})"?,[^,]*,"([^"]*)"') { $ids += [int]$matches[1]; $names[[int]$matches[1]] = $matches[2] }
}
$ids = @($ids | Select-Object -Unique)
$suspect = @(14, 27, 22)
$order = @($ids | Where-Object { $suspect -notcontains $_ }) + @($suspect | Where-Object { $ids -contains $_ })
W ('ids=' + $ids.Count + ' order-head=' + (($order | Select-Object -First 6) -join ',') + ' order-tail=' + (($order | Select-Object -Last 5) -join ','))
$got = ''; $winner = -1; $n = 0
foreach ($id in $order) {
    $n++
    W ('STEP=prov ' + $id + ' ' + $(if ($names.ContainsKey($id)) { $names[$id] } else { '?' }) + ' (' + $n + '/' + $order.Count + ')')
    $o = (& $kdu -prv $id -dse 2>&1) -join "`n"
    if ($o -match 'value:\s*([0-9A-Fa-f]+)') { $got = $matches[1]; $winner = $id; break }
    W ('  no value: [' + (($o -replace '\s+', ' ').Trim()) + ']')
}
if ($winner -ge 0) {
    W ('RESULT: PASS - dse read 0x' + $got + ' via prv ' + $winner + ' (' + $(if ($names.ContainsKey($winner)) { $names[$winner] } else { '?' }) + ') after ' + $n + ' provider(s)')
    W 'VERDICT: BENCH PASS - the ordered read completes in the VM without a bugcheck; suspects untouched on this run'
} else {
    W 'RESULT: FAIL - no provider returned a DSE value'
    W ('VERDICT: BENCH FAIL - all ' + $order.Count + ' providers refused in the VM')
}
