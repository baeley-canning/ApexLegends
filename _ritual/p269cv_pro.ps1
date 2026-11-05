$kd = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
$dmp = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\110526-10890-01.dmp'
$log = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269cv_pro.txt'
Remove-Item -LiteralPath $log -EA 0
& $kd -logo $log -z $dmp -c 'u WinRing0x64+0x1505 L42; .echo ===IMPORTS; dq WinRing0x64+0x2000 L10; .echo ===DONE; q' | Out-Null
