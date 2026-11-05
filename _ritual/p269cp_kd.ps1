$kd = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
$dmp = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\110526-10890-01.dmp'
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269cp_kd.txt'
& $kd -z $dmp -c 'lmv; .echo ENDLM; q' 2>&1 | Set-Content -LiteralPath $out
