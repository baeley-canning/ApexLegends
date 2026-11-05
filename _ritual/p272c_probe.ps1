# p272c - diagnose why the p272b launcher loop matched nothing.
# Lesson: `powershell -File vm_type.ps1 -Seq a,b,c` joins the tokens into ONE string, so the
# detached wrapper must call vm_type.ps1 IN-PROCESS (& script -Seq arr) to get real arrays.
# The guest cmd line currently holds "yback,fsutil fsinfo drives & for %d in (...) do @if exist ..."
# with no Enter; its & split still runs the useful half, so Enter -> FOUND lines reveals the letters.
$base = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$log  = Join-Path $base 'p272c_probe.log'
$shot = Join-Path $base 'shot.ps1'
$vt   = Join-Path $base 'vm_type.ps1'
function L($s) { Add-Content -LiteralPath $log -Value ((Get-Date -f 'HH:mm:ss') + ' ' + $s) }
function T([string[]]$s) { & $vt -Seq $s }
function Shot($n) { & powershell -NoProfile -ExecutionPolicy Bypass -File $shot $n | Out-Null; L ('shot ' + $n) }
if (Test-Path $log) { Remove-Item $log -Force }

L 'start'
T 'enter'
Start-Sleep -Seconds 3
Shot 'p272c_2'
Start-Sleep -Seconds 4
Shot 'p272c_3'
L 'done'
