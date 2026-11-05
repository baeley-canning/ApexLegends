# p314_gui.ps1 - probe #314 (variable: restart the VM WITH a console window, then timed shell)
# ROOT CAUSE: p299_reboot started the VM with --type headless. On Windows a headless VM has no console
# window, so vm_click found no window and every click since the reboot was a no-op - that is why the
# shell never opened and the password reset never ran. This probe fixes the transport, then repeats the
# timed shell / password reset / guestcontrol retest in the same run. Reversible: savestate or poweroff,
# then a GUI startvm; nothing inside the guest is changed except the password.
Add-Type -AssemblyName System.Drawing
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VV = 'C:\Program Files\Oracle\VirtualBox\VirtualBoxVM.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p314.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function K([string[]]$s) { & (Join-Path $d 'vm_type.ps1') -Seq $s | Out-Null }
function Run([string]$c, [int]$w = 3) { K @($c); Start-Sleep -Milliseconds 350; K @('enter'); Start-Sleep -Seconds $w }
function St() { ((& $v showvminfo $VM --machinereadable | Select-String '^VMState=') -replace '.*=', '') -replace '"', '' }
function Mean($png) {
    $m = -1
    try { $b = [System.Drawing.Bitmap]::FromFile($png); $sx = [int]($b.Width / 10); $sy = [int]($b.Height / 10); $n = 0; $s = 0
        for ($x = $sx; $x -lt $b.Width; $x += $sx) { for ($y = $sy; $y -lt $b.Height; $y += $sy) { $c = $b.GetPixel($x, $y); $s += ($c.R + $c.G + $c.B) / 3; $n++ } }
        if ($n -gt 0) { $m = [int]($s / $n) }; $b.Dispose() } catch { }
    return $m }
Say 'START'
Say ('pre_state=' + (St))
& (Join-Path $d 'closewin.ps1') -Pattern 'VirtualBox - Error' | Out-Null
Start-Sleep -Milliseconds 700
# stop the headless session: savestate keeps the desktop, poweroff is the fallback
& $v controlvm $VM savestate 2>&1 | Out-File -FilePath $out -Encoding ascii -Append
Start-Sleep -Seconds 3
if ((St) -notmatch 'saved|poweroff|aborted') { Say 'savestate did not take -> poweroff'; & $v controlvm $VM poweroff 2>&1 | Out-Null; Start-Sleep -Seconds 4 }
Say ('post_stop_state=' + (St))
Start-Process $VV -ArgumentList '--startvm', $VM
Start-Sleep -Seconds 12
Say ('post_start_state=' + (St))
& (Join-Path $d 'wins.ps1') | Out-File -FilePath $out -Encoding ascii -Append
$win = (Select-String -Path $out -Pattern 'Win11-Test2' -SimpleMatch | Where-Object { $_ -match ' :: ' } | Measure-Object).Count
Say ('console_windows=' + $win)
if ($win -lt 1) { Say 'VERDICT: still no console window - clicks cannot land'; Say 'END'; return }
# wait for a real desktop
$up = 0
for ($i = 1; $i -le 40; $i++) {
    Start-Sleep -Seconds 3
    $png = Join-Path $d ('p314_w{0:d2}.png' -f $i)
    & $v controlvm $VM screenshotpng $png 2>&1 | Out-Null
    $m = Mean $png; Say ('w{0:d2} mean={1}' -f $i, $m)
    if ($m -gt 70) { $up++ } else { $up = 0 }
    if ($up -ge 2) { Say ('desktop_up at w' + $i); break }
}
if ($up -lt 2) { Say 'VERDICT: no desktop, abort'; Say 'END'; return }
& (Join-Path $d 'vm_click.ps1') -X 613 -Y 744 | Out-File -FilePath $out -Encoding ascii -Append
Start-Sleep -Seconds 3
& $v controlvm $VM screenshotpng (Join-Path $d 'p314_exp.png') 2>&1 | Out-Null
& (Join-Path $d 'vm_click.ps1') -X 520 -Y 134 | Out-File -FilePath $out -Encoding ascii -Append
Start-Sleep -Milliseconds 900
K @('powershell'); Start-Sleep -Milliseconds 400; K @('enter')
Start-Sleep -Seconds 8
& $v controlvm $VM screenshotpng (Join-Path $d 'p314_ps.png') 2>&1 | Out-Null
Say 'shell attempted'
Run 'whoami' 2
Run 'net user vboxuser' 3
Run 'net user vboxuser vboxuser' 3
Run 'net user vboxuser | findstr /i "active expires"' 3
& $v controlvm $VM screenshotpng (Join-Path $d 'p314_a.png') 2>&1 | Out-Null
Say 'reset done'
Start-Sleep -Seconds 2
$g = & $v guestcontrol $VM run --username vboxuser --password vboxuser --timeout 60000 --wait-stdout --wait-stderr --exe 'C:\Windows\System32\cmd.exe' -- cmd /c echo AFTERRESET 2>&1
Say ('gc_after rc=' + $LASTEXITCODE + ' o=' + ($g -join ' '))
$rl = (& $v guestproperty enumerate $VM 2>&1 | Select-String 'GuestAdditionsRunLevel|GuestAdditionsVersion')
Say ('ga=' + (($rl -join ' ') -replace '\s+', ' '))
Say 'END'