# p321_bcd.ps1 - probe #321 (variable: can a medium-IL guestcontrol token READ boot config)
# #320 pinned the token at S-1-16-8192 (medium) and `net session` -> Access denied, so there is no
# elevation on this channel. #320's bcdedit failed for a quoting reason ("entry type is invalid"),
# not a rights reason, so this probe uses plain keywords and a raw brace argument to separate the two.
# Read-only: bcdedit /enum only.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p321.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function GCrun([string]$cmd) {
    $o = & $v guestcontrol $VM run --username vboxuser --password vboxuser --timeout 45000 --wait-stdout --wait-stderr --exe 'C:\Windows\System32\cmd.exe' -- cmd /c $cmd 2>&1
    $rc = $LASTEXITCODE
    return @{ rc = $rc; o = (($o -join ' ') -replace '\s+', ' ') }
}
Say 'START'
$b = GCrun 'bcdedit /enum active'
Say ('enum_active rc=' + $b.rc + ' o=' + $b.o.Substring(0, [Math]::Min(400, $b.o.Length)))
$c = GCrun 'bcdedit /enum {current}'
Say ('enum_current rc=' + $c.rc + ' o=' + $c.o.Substring(0, [Math]::Min(400, $c.o.Length)))
$e = GCrun 'bcdedit /enum {current} /v | findstr /i "safeboot identifier"'
Say ('vboot_read rc=' + $e.rc + ' o=' + $e.o.Substring(0, [Math]::Min(300, $e.o.Length)))
$f = GCrun 'bcdedit /set {current} description test-medium'
Say ('set_test rc=' + $f.rc + ' o=' + $f.o.Substring(0, [Math]::Min(200, $f.o.Length)))
Say 'VERDICT: enum_active rc=0 means boot config is readable at medium IL; set_test rc!=0 means writes need elevation'
Say 'END'