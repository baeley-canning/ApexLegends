# p318_reboot_gc.ps1 - probe #318 (variable: does the working credential survive a reboot)
# #315 set the password, #317 proved it twice plus a negative control. A bench channel is only worth
# anything if it is there on the *next* boot, so: poweroff, boot through the GUI frontend, wait for a
# real desktop, then re-run guestcontrol. Also probes `bcdedit` through guestcontrol - if the GA
# process token is medium integrity it must fail, and that decides whether the channel can read boot
# config or needs an elevated helper.
# Pre-state is recorded first; nothing is mutated (the guest was already password-set).
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VV = 'C:\Program Files\Oracle\VirtualBox\VirtualBoxVM.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p318.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function GCrun([string]$cmd) {
    $o = & $v guestcontrol $VM run --username vboxuser --password vboxuser --timeout 45000 --wait-stdout --wait-stderr --exe 'C:\Windows\System32\cmd.exe' -- cmd /c $cmd 2>&1
    $rc = $LASTEXITCODE
    return @{ rc = $rc; o = (($o -join ' ') -replace '\s+', ' ') }
}
function State { (((& $v showvminfo $VM --machinereadable | Select-String '^VMState=') -replace '.*=', '') -replace '"', '') }
Add-Type -AssemblyName System.Drawing
function Mean($png) { $m = -1
    try { $b = [System.Drawing.Bitmap]::FromFile($png); $sx = [int]($b.Width / 10); $sy = [int]($b.Height / 10); $n = 0; $s = 0
        for ($x = $sx; $x -lt $b.Width; $x += $sx) { for ($y = $sy; $y -lt $b.Height; $y += $sy) { $c = $b.GetPixel($x, $y); $s += ($c.R + $c.G + $c.B) / 3; $n++ } }
        if ($n -gt 0) { $m = [int]($s / $n) }; $b.Dispose() } catch { }
    return $m }
Say 'START'
Say ('pre_state=' + (State))
$pre = GCrun 'whoami'
Say ('pre_gc rc=' + $pre.rc + ' o=' + $pre.o)
& $v controlvm $VM poweroff 2>&1 | Out-Null
Start-Sleep -Seconds 5
Say ('post_poweroff=' + (State))
Start-Process $VV -ArgumentList '--startvm', $VM
Start-Sleep -Seconds 6
Say ('post_start=' + (State))
$up = 0
for ($i = 1; $i -le 40; $i++) {
    Start-Sleep -Seconds 3
    $png = Join-Path $d ('p318_w{0:d2}.png' -f $i)
    & $v controlvm $VM screenshotpng $png 2>&1 | Out-Null
    $m = Mean $png
    Say ('w{0:d2} mean={1}' -f $i, $m)
    if ($m -gt 70) { $up++ } else { $up = 0 }
    if ($up -ge 3) { Say ('desktop_up after w' + $i); break }
}
if ($up -lt 3) { Say 'VERDICT: no desktop after reboot'; Say 'END'; return }
Start-Sleep -Seconds 8
$a = GCrun 'whoami'
Say ('post_gc rc=' + $a.rc + ' o=' + $a.o)
$b = GCrun 'sc query vboxservice | findstr STATE'
Say ('post_svc rc=' + $b.rc + ' o=' + $b.o)
$c = GCrun "bcdedit /enum '{current}' | findstr /i safeboot"
Say ('post_bcdedit rc=' + $c.rc + ' o=' + $c.o)
$e = GCrun 'whoami /groups | findstr /i 12288'
Say ('post_il rc=' + $e.rc + ' o=' + $e.o)
Say 'VERDICT: pass if post_gc rc=0 and post_bcdedit tells us whether boot config is readable'
Say 'END'