# p297_bcd2.ps1 - probe #297 (variable: Enter after each command)
# #296 concatenated cls + all three commands into one unexecuted edit line - the enters were missing.
# ESC first clears that line (PSReadLine revert), then one command + Enter at a time.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p297.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function K([string[]]$s) { & (Join-Path $d 'vm_type.ps1') -Seq $s | Out-Null }
function Run([string]$c, [int]$w = 4) { K @($c); Start-Sleep -Milliseconds 400; K @('enter'); Start-Sleep -Seconds $w }
Say 'START'
K @('esc'); Start-Sleep -Milliseconds 600
Run 'cls' 1
Say 'A: entries with safeboot'
Run 'bcdedit /enum all | sls "safeboot|descr"' 5
Say 'B: current'
Run "bcdedit /enum '{current}'" 4
Say 'C: default'
Run "bcdedit /enum '{default}'" 4
& $v controlvm $VM screenshotpng (Join-Path $d 'p297_a.png') 2>&1 | Out-Null
Say 'shot a'
Start-Sleep -Seconds 4
& $v controlvm $VM screenshotpng (Join-Path $d 'p297_b.png') 2>&1 | Out-Null
Say 'END'