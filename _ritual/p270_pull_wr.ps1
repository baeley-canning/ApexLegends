# p270_pull_wr.ps1 - read-only: pull the crashing driver image out of the guest so the
# +0x15B8 export and the +0x2028 IAT slot can be named without guessing.
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$r  = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p270_wr_files.txt'
$dst = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\WinRing0x64.sys'
Remove-Item -LiteralPath $r -EA 0
Remove-Item -LiteralPath $dst -EA 0
foreach ($g in 'C:\Users\Public\p37\WinRing0x64.sys', 'C:\Users\Public\p37\WinRing0x64.sys.bak', 'C:\p37vm\payload\WinRing0x64.sys', 'C:\Windows\System32\drivers\WinRing0x64.sys') {
    $out = $null
    $out = (& $VB guestcontrol $VM --username vboxuser --password password copyfrom $g $dst 2>&1) -join ' | '
    $ok = Test-Path -LiteralPath $dst
    ('{0} -> exists={1} msg={2}' -f $g, $ok, (($out -replace '\s+', ' ').Trim())) | Add-Content -LiteralPath $r
    if ($ok) {
        $f = Get-Item -LiteralPath $dst
        ('KEPT {0} size={1} mtime={2} sha256={3}' -f $g, $f.Length, $f.LastWriteTime.ToString('s'), (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash) | Add-Content -LiteralPath $r
        break
    }
}
if (Test-Path -LiteralPath $dst) {
    $b = [IO.File]::ReadAllBytes($dst)
    'MZ=' + [char]$b[0] + [char]$b[1] | Add-Content -LiteralPath $r
    $pe = [BitConverter]::ToInt32($b, 0x3C)
    'pe_off=0x{0:X}' -f $pe | Add-Content -LiteralPath $r
    ('pe_sig=' + [Text.Encoding]::ASCII.GetString($b, $pe, 4)) | Add-Content -LiteralPath $r
}
'done' | Add-Content -LiteralPath $r
