$kd = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
$dmp = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\110526-10890-01.dmp'
$log = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269cw_req.txt'
Remove-Item -LiteralPath $log -EA 0
& $kd -logo $log -z $dmp -c '.echo ===REQ; dq ffffa886adfad000 L8; .echo ===STK; dq ffffa381ff4bc5d0 L18; .echo ===DONE; q' | Out-Null
