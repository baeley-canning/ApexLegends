$kd = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269cu_exports.txt'
$dmp = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\110526-10890-01.dmp'
& $kd -z $dmp -c 'x WinRing0x64!*; .echo ===UPRE; u WinRing0x64+0x14c0 L48; .echo ===IMP; dq WinRing0x64+0x2000 L6; u /c 1 WinRing0x64+0x2020 L1; .echo ===END; q' 2>&1 | Add-Content -LiteralPath $out
Add-Content -LiteralPath $out -Value '###DONE'
