$d = $PSScriptRoot
$log = Join-Path $d 'probe.txt'
"probe $(Get-Date -Format s)" | Set-Content -Encoding utf8 $log
function P($s) { Add-Content -Encoding utf8 $log $s }

$dos = @((Join-Path $d '_p25h_S6lan.sys'), (Join-Path $env:SystemRoot 'System32\drivers\apexdrv.sys'), (Join-Path $env:SystemRoot 'System32\drivers\tcpip.sys'))

P '--- store inventory'
foreach ($s in @((Join-Path $env:SystemRoot 'System32\CatRoot'), (Join-Path $env:SystemRoot 'System32\CatRoot2'))) {
    if (Test-Path -LiteralPath $s) {
        $fs = @(Get-ChildItem -LiteralPath $s -Recurse -File -ErrorAction SilentlyContinue)
        $sum = 0; foreach ($x in $fs) { $sum += $x.Length }
        P ("STORE $s files={0} bytes={1}" -f $fs.Count, $sum)
        foreach ($x in $fs) { if ($x.Name -eq 'catdb') { P ("  catdb " + $x.FullName + " size=" + $x.Length + " ts=" + $x.LastWriteTime) } }
        foreach ($x in @($fs | Sort-Object Length -Descending | Select-Object -First 5)) { P ("  big " + $x.FullName + " " + $x.Length) }
    } else { P "STORE MISSING $s" }
}

P '--- OS trust verdict (Get-AuthenticodeSignature)'
foreach ($f in $dos) {
    $sig = Get-AuthenticodeSignature -LiteralPath $f
    $sub = '(none)'; if ($sig.SignerCertificate) { $sub = $sig.SignerCertificate.Subject }
    P ("SIG " + $f + " status=" + $sig.Status + " signer=" + $sub)
}

P '--- raw store scan (engine hashes)'
& (Join-Path $d 'cateng.ps1') -Path $dos -NoApi -ScanStores
Copy-Item -Force (Join-Path $d 'cateng.txt') (Join-Path $d 'cateng_scan.txt')

P '--- OS catalog enum (engine hashes)'
& (Join-Path $d 'cateng.ps1') -Path $dos -NoApi -Lookup
Copy-Item -Force (Join-Path $d 'cateng.txt') (Join-Path $d 'cateng_lookup2.txt')

'probe-complete' | Set-Content -Encoding utf8 (Join-Path $d 'probe_complete.txt')
