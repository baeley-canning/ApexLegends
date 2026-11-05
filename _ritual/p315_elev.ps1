# p315_elev.ps1 - probe #315 (variable: elevated shell - error 5 was why no reset ever took)
# #314 proved the transport works and that the console shell is NOT elevated ("System error 5 has
# occurred. Access is denied." on net user vboxuser vboxuser). This probe gets a high-integrity shell
# via Win+X -> Terminal (Admin) and auto-consents the UAC prompt with Alt+Y, verifies the integrity
# level before touching anything, then sets a known password and retests guestcontrol.
Add-Type -AssemblyName System.Drawing
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p315.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function K([string[]]$s) { & (Join-Path $d 'vm_type.ps1') -Seq $s | Out-Null }
function Run([string]$c, [int]$w = 3) { K @($c); Start-Sleep -Milliseconds 350; K @('enter'); Start-Sleep -Seconds $w }
function Shot($n) { & $v controlvm $VM screenshotpng (Join-Path $d ('p315_' + $n + '.png')) 2>&1 | Out-Null }
Say 'START'
$ui = & (Join-Path $d 'ensure_ui.ps1') -VM $VM
$ui | ForEach-Object { Say $_ }
if ($LASTEXITCODE -ne 0) { Say 'VERDICT: no console window, abort'; Say 'END'; return }
# a window is not a desktop: restoring shows the splash and eats input. Wait for a bright, stable frame.
function Mean($png) { $m = -1
    try { $b = [System.Drawing.Bitmap]::FromFile($png); $sx = [int]($b.Width / 10); $sy = [int]($b.Height / 10); $n = 0; $s = 0
        for ($x = $sx; $x -lt $b.Width; $x += $sx) { for ($y = $sy; $y -lt $b.Height; $y += $sy) { $c = $b.GetPixel($x, $y); $s += ($c.R + $c.G + $c.B) / 3; $n++ } }
        if ($n -gt 0) { $m = [int]($s / $n) }; $b.Dispose() } catch { }
    return $m }
$up = 0
for ($i = 1; $i -le 40; $i++) {
    Start-Sleep -Seconds 3
    Shot ('w{0:d2}' -f $i)
    $m = Mean (Join-Path $d ('p315_w{0:d2}.png' -f $i))
    Say ('w{0:d2} mean={1}' -f $i, $m)
    if ($m -gt 70) { $up++ } else { $up = 0 }
    if ($up -ge 3) { Say ('desktop_up after w' + $i); break }
}
if ($up -lt 3) { Say 'VERDICT: no desktop, abort'; Say 'END'; return }
Shot 'k0'
& (Join-Path $d 'vm_click.ps1') -X 600 -Y 600 | Out-File -FilePath $out -Encoding ascii -Append
Start-Sleep -Milliseconds 500
K @('winx'); Start-Sleep -Milliseconds 1600; Shot 'k1'
K @('a'); Start-Sleep -Seconds 5; Shot 'k2'
K @('alty'); Start-Sleep -Milliseconds 800; K @('enter'); Start-Sleep -Seconds 6; Shot 'k3'
Run 'whoami /groups | findstr /i Mandatory' 4
Shot 'k4'
Run '"HIGH-CHECK-ABOVE"' 2
Run 'net user vboxuser vboxuser' 4
Run 'net user vboxuser vboxuser' 4
& $v controlvm $VM screenshotpng (Join-Path $d 'p315_a.png') 2>&1 | Out-Null
Say 'reset attempted'
Start-Sleep -Seconds 2
$g = & $v guestcontrol $VM run --username vboxuser --password vboxuser --timeout 60000 --wait-stdout --wait-stderr --exe 'C:\Windows\System32\cmd.exe' -- cmd /c echo AFTERRESET 2>&1
Say ('gc_after rc=' + $LASTEXITCODE + ' o=' + (($g -join ' ') -replace '\s+', ' '))
Say 'END'