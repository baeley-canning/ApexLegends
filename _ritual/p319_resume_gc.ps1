# p319_resume_gc.ps1 - probe #319 (variable: guestcontrol survives a cold boot)
# #318 got the reboot going but the host disk filled to 0 bytes, VirtualBox paused the VM and every
# screenshot failed (mean=-1). Space was freed by pruning probe PNGs / VBox logs / TEMP (~1.3 GB back,
# `free.txt`). This resumes the paused VM, waits for a real desktop (with a bounded login fallback in
# case a cold boot lands on the lock screen), then re-runs the guestcontrol checks that #318 could not
# reach. Boot config read is the point: it decides whether the channel can replace the p37tick task.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p319.txt'
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
if ((State) -eq 'paused') { & $v controlvm $VM poweroff 2>&1 | Out-Null; Start-Sleep -Seconds 5; Say ('after_poweroff=' + (State)) }
if ((State) -eq 'poweroff' -or (State) -eq 'aborted' -or (State) -eq 'saved') {
    Start-Process 'C:\Program Files\Oracle\VirtualBox\VirtualBoxVM.exe' -ArgumentList '--startvm', $VM
    Start-Sleep -Seconds 8
    Say ('after_start=' + (State))
} else {
    $ui = & (Join-Path $d 'ensure_ui.ps1') -VM $VM
    $ui | ForEach-Object { Say $_ }
}
Start-Sleep -Seconds 3
$up = 0; $mid = 0; $lk = 0
for ($i = 1; $i -le 40; $i++) {
    Start-Sleep -Seconds 3
    $png = Join-Path $d ('p319_w{0:d2}.png' -f $i)
    & $v controlvm $VM screenshotpng $png 2>&1 | Out-Null
    $m = Mean $png
    Say ('w{0:d2} mean={1}' -f $i, $m)
    if ($m -gt 70) { $up++ } else { $up = 0; if ($m -ge 45 -and $m -le 70) { $mid++ } else { $mid = 0 } }
    if ($up -ge 3) { Say ('desktop_up after w' + $i); break }
    if ($m -eq -1 -and (State) -eq 'paused') { & $v controlvm $VM resume 2>&1 | Out-Null; Say 're-resumed' }
    if ($mid -ge 5 -and $lk -eq 0) {
        $lk = 1; Say 'login-screen guess: click + type password'
        & (Join-Path $d 'vm_click.ps1') -X 512 -Y 400 | Out-File -FilePath $out -Encoding ascii -Append
        & (Join-Path $d 'vm_type.ps1') -Seq 'vboxuser','enter' | Out-Null
    }
}
if ($up -lt 3) { Say 'VERDICT: no desktop'; Say 'END'; return }
Start-Sleep -Seconds 10
$a = GCrun 'whoami'
Say ('post_gc rc=' + $a.rc + ' o=' + $a.o)
$b = GCrun 'sc query vboxservice | findstr STATE'
Say ('post_svc rc=' + $b.rc + ' o=' + $b.o)
$c = GCrun "bcdedit /enum '{current}' | findstr /i safeboot"
Say ('post_bcdedit rc=' + $c.rc + ' o=' + $c.o)
$e = GCrun 'whoami /groups | findstr /i 12288'
Say ('post_il rc=' + $e.rc + ' o=' + $e.o)
Say ('ver=')
$f = GCrun 'ver'
Say ('post_ver rc=' + $f.rc + ' o=' + $f.o)
Say 'VERDICT: pass if post_gc rc=0 after a cold boot; post_bcdedit shows whether boot config is readable'
Say 'END'