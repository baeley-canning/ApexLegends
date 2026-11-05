# p313_timed.ps1 - probe #313 (variable: self-timed shell - act only once a desktop is actually up)
# Every manual attempt so far typed into a booting or spinning VM. This one watches frames itself,
# waits for a bright, stable desktop, then opens Explorer -> powershell, resets vboxuser's password and
# retests guestcontrol from the host in the same run - so the verdict is attached to the action.
Add-Type -AssemblyName System.Drawing
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p313.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function K([string[]]$s) { & (Join-Path $d 'vm_type.ps1') -Seq $s | Out-Null }
function Run([string]$c, [int]$w = 3) { K @($c); Start-Sleep -Milliseconds 350; K @('enter'); Start-Sleep -Seconds $w }
function Mean($png) {
    $m = -1
    try {
        $bmp = [System.Drawing.Bitmap]::FromFile($png)
        $sx = [int]($bmp.Width / 10); $sy = [int]($bmp.Height / 10); $n = 0; $s = 0
        for ($x = $sx; $x -lt $bmp.Width; $x += $sx) { for ($y = $sy; $y -lt $bmp.Height; $y += $sy) { $c = $bmp.GetPixel($x, $y); $s += ($c.R + $c.G + $c.B) / 3; $n++ } }
        if ($n -gt 0) { $m = [int]($s / $n) }
        $bmp.Dispose()
    } catch { }
    return $m
}
Say 'START'
$up = 0
for ($i = 1; $i -le 60; $i++) {
    Start-Sleep -Seconds 3
    $png = Join-Path $d ('p313_w{0:d2}.png' -f $i)
    & $v controlvm $VM screenshotpng $png 2>&1 | Out-Null
    $m = Mean $png
    Say ('w{0:d2} mean={1}' -f $i, $m)
    if ($m -gt 70) { $up++ } else { $up = 0 }
    if ($up -ge 2) { Say ('desktop_up at w' + $i); break }
}
if ($up -lt 2) { Say 'VERDICT: never saw a desktop, abort'; Say 'END'; return }
& (Join-Path $d 'vm_click.ps1') -X 613 -Y 744 | Out-Null
Start-Sleep -Seconds 3
& (Join-Path $d 'vm_click.ps1') -X 520 -Y 134 | Out-Null
Start-Sleep -Milliseconds 900
K @('powershell'); Start-Sleep -Milliseconds 400; K @('enter')
Start-Sleep -Seconds 8
& $v controlvm $VM screenshotpng (Join-Path $d 'p313_ps.png') 2>&1 | Out-Null
Say 'shell attempted'
Run 'whoami' 2
Run 'net user vboxuser' 3
Run 'net user vboxuser vboxuser' 3
Run 'net user vboxuser | findstr /i "active expires"' 3
& $v controlvm $VM screenshotpng (Join-Path $d 'p313_a.png') 2>&1 | Out-Null
Say 'reset done'
Start-Sleep -Seconds 2
$o = & $v guestcontrol $VM run --username vboxuser --password vboxuser --timeout 60000 --wait-stdout --wait-stderr --exe 'C:\Windows\System32\cmd.exe' -- cmd /c echo AFTERRESET 2>&1
Say ('gc_after rc=' + $LASTEXITCODE + ' o=' + (($o -join ' ')))
Say 'END'