$kd = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269cs_disasm.txt'
$buf = [IO.File]::ReadAllBytes('c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\110526-10890-01.dmp')
$trap = [BitConverter]::ToUInt64($buf, 0x50)
$dmp = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\110526-10890-01.dmp'
Add-Content -LiteralPath $out -Value ("##### trap=0x{0:X}" -f $trap)
$cmds = '.cxr {0:x}; r; .echo ===U; u WinRing0x64+0x1560 L50; .echo ===END; q' -f $trap
& $kd -z $dmp -c $cmds 2>&1 | Add-Content -LiteralPath $out
Add-Content -LiteralPath $out -Value '###DONE'
