# h286_vmdiag2.ps1 - read-only round 2: screenshot (v1 had a long+string concat bug), VM
# process start time from VBox.log, log rotation, host C: free space (disk-full paused the VM
# earlier today), guest power state clues. No mutation. Own output file (R5).
$vb  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\h286_vmdiag2.txt'
$shot = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\h286_vm2.png'
Remove-Item -LiteralPath $out -Force -EA 0
Remove-Item -LiteralPath $shot -Force -EA 0
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) }
W '=== h286 vmdiag2 (read-only) ==='
$t = (& $vb controlvm 'Win11-Test2' screenshotpng $shot 2>&1 | Out-String)
if (Test-Path $shot) { W ('screenshot OK: ' + (Get-Item $shot).Length.ToString() + ' bytes -> temp\h286_vm2.png') } else { W ('screenshot FAILED: ' + ($t -replace '\s+',' ').Trim()) }
$drive = Get-PSDrive C
W ('host C: free GB = ' + [Math]::Round($drive.Free/1GB,2) + ' used GB = ' + [Math]::Round($drive.Used/1GB,2))
$vmdir = 'C:\Users\New User\VirtualBox VMs\Win11-Test2'
W '--- log files ---'
Get-ChildItem "$vmdir\Logs" -Filter 'VBox.log*' | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object { W ('  ' + $_.Name + ' mtime=' + $_.LastWriteTime.ToString('HH:mm:ss') + ' size=' + $_.Length) }
$log = "$vmdir\Logs\VBox.log"
W '--- current VBox.log first lines (process start time) ---'
Get-Content $log -TotalCount 25 | ForEach-Object { $l = $_.Trim(); if ($l) { W ('  ' + $l.Substring(0, [Math]::Min(150, $l.Length))) } }
W '--- VBox.log last 12 lines ---'
Get-Content $log -Tail 12 | ForEach-Object { W ('  ' + $_.Trim()) }
W 'VERDICT: diagnostics only'
