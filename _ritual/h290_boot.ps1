# h290_boot.ps1 - nudge the guest out of WinRE "Automatic Repair" with the ONE keystroke proven in
# h287_recover (Enter on the focused Restart button), then wait for GA and harvest the park
# report the guest posts to the host (guest-h289p.log).
# Mutation: one synthetic Enter scancode. Nothing on the guest is changed by this script itself;
# the tick it wakes does the rest. Re-runnable (R4): the same keystroke re-nudges if the guest
# is still parked. Own output (R5): _ritual\h290_boot.txt.
$vb   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$vm   = 'Win11-Test2'
$out  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\h290_boot.txt'
$shotPre  = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\h290_pre.png'
$shotMid  = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\h290_mid.png'
$shotPost = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\h290_post.png'
$glog = 'C:\p37vm\guest-h289p.log'
Remove-Item -LiteralPath $out -Force -EA 0
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) }
function GA {
    $mi = & $vb showvminfo $vm --machinereadable 2>&1
    $rl = ($mi | Select-String '^GuestAdditionsRunLevel=').Line
    $vs = ($mi | Select-String '^VMState=').Line
    return (($vs -replace '"', '') + ' ' + ($rl -replace '"', ''))
}
function Shot([string]$p) { & $vb controlvm $vm screenshotpng $p 2>&1 | Out-Null; if (Test-Path $p) { return (Get-Item $p).Length.ToString() + 'b' } else { return 'FAIL' } }
W '=== h290 boot: Enter out of WinRE with the park payload armed ==='
W ('pre: ' + (GA) + ' shot=' + (Shot $shotPre))
$logLinesPre = 0
if (Test-Path $glog) { $logLinesPre = (Get-Content -LiteralPath $glog).Count }
W ('pre guest-h289p.log: ' + $(if (Test-Path $glog) { (Get-Item $glog).Length.ToString() + 'b lines=' + $logLinesPre } else { 'absent (no park report yet, expected)' }))
W '--- sending Enter (1c 9c) ---'
$k = & $vb controlvm $vm keyboardputscancode 1c 9c 2>&1 | Out-String
W ('  keyboardputscancode rc-text: ' + ($k -replace '\s+', ' ').Trim())
$up = 0
for ($i = 1; $i -le 16; $i++) {
    Start-Sleep -Seconds 15
    $st = GA
    W ('t+' + (15 * $i) + 's: ' + $st)
    if ($i -eq 4) { W ('  shot mid=' + (Shot $shotMid)) }
    if ($st -match 'GuestAdditionsRunLevel=([2-9])') { $up = 1; break }
}
W ('post: ' + (GA) + ' shot=' + (Shot $shotPost))
if ($up -ne 1) {
    W 'RESULT: FAIL - GA did not reach runlevel 2 within 240 s; guest likely still in WinRE (variable: WinRE restart nudge)'
    W 'VERDICT: nudge again or inspect temp\h290_post.png; nothing was mutated beyond the keystroke'
    exit 1
}
W '--- guestcontrol channel probe ---'
$g = & $vb guestcontrol $vm run --exe 'C:\Windows\System32\cmd.exe' --username vboxuser --password vboxuser --wait-stdout --wait-stderr --timeout 30000 -- cmd.exe /c "whoami & ver & echo h290-probe-ok" 2>&1 | Out-String
$g.Trim() -split "`n" | ForEach-Object { if ($_ -match '\S') { W ('  ' + $_.Trim()) } }
# the park report is posted by the tick ~30-60 s after boot; wait for it rather than assume
for ($i = 1; $i -le 12; $i++) {
    if ((Test-Path $glog) -and ((Get-Content -LiteralPath $glog).Count -gt $logLinesPre)) { break }
    Start-Sleep -Seconds 10
}
$have = (Test-Path $glog) -and ((Get-Content -LiteralPath $glog).Count -gt $logLinesPre)
if ($have) {
    $lines = @(Get-Content -LiteralPath $glog)
    W ('--- guest-h289p.log: ' + $lines.Count + ' lines, park report from line ' + ($logLinesPre + 1) + ' ---')
    $lines[([Math]::Max(0, $logLinesPre - 2))..($lines.Count - 1)] | ForEach-Object { W ('  p ' + $_) }
} else {
    W '--- no park POST arrived within 120 s of GA level 2 ---'
    W ('  guest-h289p.log lines=' + $(if (Test-Path $glog) { (Get-Content -LiteralPath $glog).Count } else { 'absent' }))
}
W ('booted: ' + $(if ($have) { 'park report received - guest survived the tick' } else { 'GA up but no report yet' }) + ' (variable: WinRE restart nudge + park payload)')
W 'VERDICT: see RESULT and the p-prefixed park lines above'
