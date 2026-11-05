# p310_watch.ps1 - probe #310 (variable: 5 s frames + mean-colour detector to catch the bugcheck screen)
# #309 shot a VirtualBox boot splash: the guest reset on its own at ~09:23:45, 4.5 min after the
# previous boot and right after the second PCA toast round. AutoReboot means the bugcheck screen only
# exists for a second or two, so sample fast and log the frame's mean colour - a blue frame is the
# crash screen and its text is the code we still lack.
Add-Type -AssemblyName System.Drawing
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p310.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
Say 'START'
$prev = 0.0
for ($i = 1; $i -le 72; $i++) {
    Start-Sleep -Seconds 5
    $png = Join-Path $d ('p310_f{0:d2}.png' -f $i)
    & $v controlvm $VM screenshotpng $png 2>&1 | Out-Null
    $r = 0; $g = 0; $b = 0
    if (Test-Path $png) {
        try {
            $bmp = [System.Drawing.Bitmap]::FromFile($png)
            $sx = [int]($bmp.Width / 12); $sy = [int]($bmp.Height / 12)
            $n = 0; $sr = 0; $sg = 0; $sb = 0
            for ($x = $sx; $x -lt $bmp.Width; $x += $sx) {
                for ($y = $sy; $y -lt $bmp.Height; $y += $sy) {
                    $c = $bmp.GetPixel($x, $y); $sr += $c.R; $sg += $c.G; $sb += $c.B; $n++
                }
            }
            if ($n -gt 0) { $r = [int]($sr / $n); $g = [int]($sg / $n); $b = [int]($sb / $n) }
            $bmp.Dispose()
        } catch { }
    }
    $p = Get-Process -Name 'VBoxHeadless' -ErrorAction SilentlyContinue | Sort-Object CPU -Descending | Select-Object -First 1
    $cpu = 0.0; if ($p) { $cpu = $p.CPU }
    $delta = if ($prev -gt 0 -and $cpu -gt 0) { [math]::Round($cpu - $prev, 1) } else { 0 }
    $prev = $cpu
    Say ('f{0:d2} rgb={1},{2},{3} cpudelta={4}' -f $i, $r, $g, $b, $delta)
}
Say 'VERDICT: a frame with blue-dominant rgb and cpudelta~0 after high cpu is the bugcheck screen'
Say 'END'