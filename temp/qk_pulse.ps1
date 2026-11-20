# qk_pulse - 19/11: one-shot vitals journal -> temp\pulse_out.txt
# usage: powershell -File temp\qk_pulse.ps1   (no args, no interactivity)
$t='C:\Users\New User\OneDrive\Desktop\cheating\temp'
$o=Join-Path $t 'pulse_out.txt'
('TIME='+$(Get-Date -Format 'HH:mm:ss')) | Set-Content -LiteralPath $o
# -- liveness --
('PROD11932=' + [bool](Get-Process -Id 11932 -EA SilentlyContinue)) | Add-Content -LiteralPath $o
('CONSUMER20652=' + [bool](Get-Process -Id 20652 -EA SilentlyContinue)) | Add-Content -LiteralPath $o
try {
  $va=@(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -EA Stop | Where-Object { $_.CommandLine -match 'qk_va\.py' })
  $lv=@(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -EA Stop | Where-Object { $_.CommandLine -match 'qk_live\.py' })
  ('N_PROD='+$va.Count) | Add-Content -LiteralPath $o
  ('N_CONS='+$lv.Count) | Add-Content -LiteralPath $o
} catch { ('CIM_FAIL='+$_.Exception.Message) | Add-Content -LiteralPath $o }
# -- feed --
$f=Join-Path $t 'qk_feed.json'
if(Test-Path -LiteralPath $f){
  ('FEED_EXISTS=True') | Add-Content -LiteralPath $o
  ('FEED_SZ=' + (Get-Item -LiteralPath $f).Length) | Add-Content -LiteralPath $o
} else {
  ('FEED_EXISTS=False') | Add-Content -LiteralPath $o
}
# -- logs (tails; silent-absent ok) --
'--EMIT2--' | Add-Content -LiteralPath $o
Get-Content (Join-Path $t 'emit_out2.txt') -Tail 6 -EA SilentlyContinue | Add-Content -LiteralPath $o
'--EMIT2ERR--' | Add-Content -LiteralPath $o
Get-Content (Join-Path $t 'emit_err2.txt') -Tail 4 -EA SilentlyContinue | Add-Content -LiteralPath $o
'--E3--' | Add-Content -LiteralPath $o
Get-Content (Join-Path $t 'emit_out3.txt') -Tail 6 -EA SilentlyContinue | Add-Content -LiteralPath $o
'--L3--' | Add-Content -LiteralPath $o
Get-Content (Join-Path $t 'live_out3.txt') -Tail 4 -EA SilentlyContinue | Add-Content -LiteralPath $o
# -- watcher + armer journals --
'--EV2--' | Add-Content -LiteralPath $o
Get-Content (Join-Path $t 'watch2_events.log') -Tail 6 -EA SilentlyContinue | Add-Content -LiteralPath $o
'--W2NOW--' | Add-Content -LiteralPath $o
Get-Content (Join-Path $t 'watch2_now.txt') -Tail 2 -EA SilentlyContinue | Add-Content -LiteralPath $o
'--ARMJ--' | Add-Content -LiteralPath $o
Get-Content (Join-Path $t 'go11_arm_3.txt') -Tail 16 -EA SilentlyContinue | Add-Content -LiteralPath $o
'DONE' | Add-Content -LiteralPath $o
