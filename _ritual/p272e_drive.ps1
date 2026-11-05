# p272e - drive the GA 7.2.2 setup GUI that p272d got past UAC (Welcome page, "Next" focused).
# Welcome -> Enter -> Custom Setup -> Enter (Install is the default button) -> wait -> Finish.
# Every step is a shot before the key so a mis-landed page is visible, not assumed.
# Finish page carries a "Reboot now" checkbox: Enter on Finish reboots the GUEST only, host untouched.
$base = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$log  = Join-Path $base 'p272e_drive.log'
$shot = Join-Path $base 'shot.ps1'
$vt   = Join-Path $base 'vm_type.ps1'
function L($s) { Add-Content -LiteralPath $log -Value ((Get-Date -f 'HH:mm:ss') + ' ' + $s) }
function T([string[]]$s) { & $vt -Seq $s }
function Shot($n) { & powershell -NoProfile -ExecutionPolicy Bypass -File $shot $n | Out-Null; L ('shot ' + $n) }
if (Test-Path $log) { Remove-Item $log -Force }

L 'start'
Shot 'p272e_0'
L 'enter -> Next'
T 'enter'
Start-Sleep -Seconds 3
Shot 'p272e_1'
L 'enter -> Install'
T 'enter'
Start-Sleep -Seconds 4
Shot 'p272e_2'
Start-Sleep -Seconds 12
Shot 'p272e_3'
Start-Sleep -Seconds 15
Shot 'p272e_4'
Start-Sleep -Seconds 15
Shot 'p272e_5'
Start-Sleep -Seconds 20
Shot 'p272e_6'
L 'done'
