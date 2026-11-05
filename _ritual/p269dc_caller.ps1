$kd = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
$dmp = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\110526-10890-01.dmp'
$log = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269dc_caller.txt'
Remove-Item -LiteralPath $log -EA 0
& $kd -logo $log -z $dmp -c '.cxr ffffa381ff4bbbb0; .echo ===CR2; r cr2; .echo ===CALLER; u WinRing0x64+0x1390 L80; .echo ===DONE; q' | Out-Null
