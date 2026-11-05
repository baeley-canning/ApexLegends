# p320_il.ps1 - probe #320 (variable: what integrity level the guestcontrol token gets)
# #319 proved the credential survives a cold boot but rc=33 on `findstr 12288` means no high-IL marker
# was in `whoami /groups`. rc=33 is *pattern not found*, not access-denied, so this probe resolves the
# ambiguity directly: full group list, `net session` (admin-only, exact rc), and raw `bcdedit /enum`
# output. This decides whether the bench can read boot config over guestcontrol or needs the elevated
# typed-shell path for anything privileged.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p320.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function GCrun([string]$cmd) {
    $o = & $v guestcontrol $VM run --username vboxuser --password vboxuser --timeout 45000 --wait-stdout --wait-stderr --exe 'C:\Windows\System32\cmd.exe' -- cmd /c $cmd 2>&1
    $rc = $LASTEXITCODE
    return @{ rc = $rc; o = (($o -join ' ') -replace '\s+', ' ') }
}
Say 'START'
$g = GCrun 'whoami /groups'
Say ('groups rc=' + $g.rc)
foreach ($p in ($g.o -split ' (?=S-1-16-)')) { Say ('  ' + $p.Substring(0, [Math]::Min(160, $p.Length))) }
$m = GCrun 'net session'
Say ('netsession rc=' + $m.rc + ' o=' + $m.o.Substring(0, [Math]::Min(200, $m.o.Length)))
$b = GCrun "bcdedit /enum '{current}'"
Say ('bcdedit rc=' + $b.rc)
Say ('bcdedit o=' + $b.o.Substring(0, [Math]::Min(700, $b.o.Length)))
$s = GCrun 'sc query vboxservice'
Say ('sc_full rc=' + $s.rc + ' o=' + $s.o.Substring(0, [Math]::Min(200, $s.o.Length)))
$w = GCrun 'sc query w32time'
Say ('sc_svc rc=' + $w.rc + ' o=' + $w.o.Substring(0, [Math]::Min(120, $w.o.Length)))
Say 'VERDICT: pass = groups show 12288 or netsession rc=0 (high/medium+admin); bcdedit o tells if boot config is readable'
Say 'END'