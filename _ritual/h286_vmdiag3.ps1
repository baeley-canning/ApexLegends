# h286_vmdiag3.ps1 - read-only round 3: why did the VM processes end (log.1/log.2 tails, reset
# markers), what does the snapshot tree look like, and did the guest OS reset vs VBoxHeadless
# exit. No mutation. Own output file (R5).
$vb  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\h286_vmdiag3.txt'
$vmdir = 'C:\Users\New User\VirtualBox VMs\Win11-Test2'
Remove-Item -LiteralPath $out -Force -EA 0
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) }
W '=== h286 vmdiag3 (read-only) ==='
W '--- snapshot tree ---'
(& $vb snapshot 'Win11-Test2' list 2>&1) | ForEach-Object { if ($_ -match '\S') { W ('  ' + $_.Trim()) } }
foreach ($lf in @('VBox.log.1','VBox.log.2')) {
    $p = "$vmdir\Logs\$lf"
    if (Test-Path $p) {
        W "--- $lf last 18 lines (how that run ended) ---"
        Get-Content $p -Tail 18 | ForEach-Object { $l = $_.Trim(); if ($l) { W ('  ' + $l.Substring(0, [Math]::Min(160, $l.Length))) } }
    }
}
W '--- reset/guru/triple markers across logs ---'
Get-ChildItem "$vmdir\Logs" -Filter 'VBox.log*' | ForEach-Object {
    $hits = Select-String -Path $_.FullName -Pattern 'Guru Meditation|Triple fault|POWERING_OFF|Changing the VM state from .RUNNING. to .RESET|Guest Log:|BSOD|bugcheck' -EA 0
    W ('  ' + $_.Name + ': ' + $hits.Count + ' hits')
    $hits | Select-Object -Last 4 | ForEach-Object { W ('    L' + $_.LineNumber + ': ' + $_.Line.Trim().Substring(0, [Math]::Min(150, $_.Line.Trim().Length))) }
}
W 'VERDICT: diagnostics only'
