# h286_vmdiag.ps1 - read-only VM diagnostics after gc refused with "Guest Additions are not
# installed or not ready (yet)" at 15:01 (they WERE ready at 10:45 per p318-p322). No mutation:
# showvminfo + log tail + screenshot. Output file per R5.
$vb  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\h286_vmdiag.txt'
$shot = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\h286_vm.png'
Remove-Item -LiteralPath $out -Force -EA 0
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) }
W '=== h286 vmdiag (read-only) ==='
foreach ($args2 in @(@('showvminfo','Win11-Test2'), @('showvminfo','Win11-Test2','--machinereadable'))) {
    $t = (& $vb @args2 2>&1 | Out-String)
    foreach ($line in ($t -split "`r?`n")) {
        if ($line -match 'VMState|AdditionsVersion|GuestAdditions|name=|Snapshots|Current snapshot|addons') { W ('  ' + $line.Trim()) }
    }
}
try { [void](& $vb controlvm 'Win11-Test2' screenshotpng $shot 2>&1); W ('screenshot rc=' + $LASTEXITCODE + ' -> ' + $(if (Test-Path $shot) { (Get-Item $shot).Length + ' bytes' } else { 'FAILED' })) } catch { W ('screenshot ex: ' + $_.Exception.Message) }
$log = "$env:USERPROFILE\VirtualBox VMs\Win11-Test2\Logs\VBox.log"
if (-not (Test-Path $log)) { $log = 'C:\Users\New User\VirtualBox VMs\Win11-Test2\Logs\VBox.log' }
if (Test-Path $log) {
    W '--- VBox.log tail (GA/session/error lines) ---'
    Get-Content $log -Tail 400 | Where-Object { $_ -match 'Guest|Addition|GA:|VBoxService|session|ERROR|error' } | Select-Object -Last 25 | ForEach-Object { W ('  ' + $_.Trim()) }
} else { W 'VBox.log not found at either path' }
W 'VERDICT: diagnostics only'
