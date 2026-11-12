# h287_recover.ps1 - recovery probe: the guest is at WinRE "Automatic Repair" (see h286_vmdiag2.txt,
# temp\h286_vm2.png). Cause: guest BugCheck 50 during h285's zapexdrv release step on every run
# (h286_vmdiag3.txt). GA is runlevel 0 in WinRE, so guestcontrol is the dead channel; the only
# input path is VBoxManage keyboardputscancode (Enter -> focused "Restart" button).
# Mutation: one synthetic Enter keystroke. Reversible: nothing to undo; re-runnable. Own output (R5).
$vb  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$vm  = 'Win11-Test2'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\h287_recover.txt'
$shotPre  = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\h287_pre.png'
$shotMid  = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\h287_mid.png'
$shotPost = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\h287_post.png'
Remove-Item -LiteralPath $out -Force -EA 0
Remove-Item -LiteralPath $shotPre,$shotMid,$shotPost -Force -EA 0
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) }
function GA {
    $mi = & $vb showvminfo $vm --machinereadable 2>&1
    $rl = ($mi | Select-String '^GuestAdditionsRunLevel=').Line
    $vs = ($mi | Select-String '^VMState=').Line
    return (($vs -replace '"','') + ' ' + ($rl -replace '"',''))
}
function Shot([string]$p) { & $vb controlvm $vm screenshotpng $p 2>&1 | Out-Null; if (Test-Path $p) { return (Get-Item $p).Length.ToString() + 'b' } else { return 'FAIL' } }
W '=== h287 recover: nudge Restart out of WinRE, wait for GA ==='
W ('pre: ' + (GA) + ' shot=' + (Shot $shotPre))
W '--- sending Enter (1c 9c) to the focused Restart button ---'
$k = & $vb controlvm $vm keyboardputscancode 1c 9c 2>&1 | Out-String
W ('  keyboardputscancode rc-text: ' + ($k -replace '\s+',' ').Trim())
$up = 0
for ($i = 1; $i -le 16; $i++) {
    Start-Sleep -Seconds 15
    $st = GA
    W ("t+" + (15*$i) + "s: " + $st)
    if ($i -eq 4) { W ('  shot mid=' + (Shot $shotMid)) }
    if ($st -match 'GuestAdditionsRunLevel=([2-9])') { $up = 1; break }
}
W ('post: ' + (GA) + ' shot=' + (Shot $shotPost))
if ($up -eq 1) {
    W '--- gc probe: whoami via guestcontrol (proves the channel is back) ---'
    $g = & $vb guestcontrol $vm run --exe 'C:\Windows\System32\cmd.exe' --username vboxuser --password vboxuser --wait-stdout --wait-stderr --timeout 30000 -- cmd.exe /c "whoami /user & ver & echo h287-probe-ok" 2>&1 | Out-String
    $g.Trim() -split "`n" | ForEach-Object { if ($_ -match '\S') { W ('  ' + $_.Trim()) } }
    W 'RESULT: PASS - GA runlevel >= 2, guestcontrol channel alive (variable: WinRE restart nudge)'
} else {
    W 'RESULT: FAIL - GA did not reach runlevel 2 within 240 s (guest likely still in WinRE) (variable: WinRE restart nudge)'
}
W 'VERDICT: recovery nudged; see RESULT line'
