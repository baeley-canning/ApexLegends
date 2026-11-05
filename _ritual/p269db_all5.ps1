$kd = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
$dir = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps'
$res = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269db_all.txt'
Get-ChildItem -LiteralPath $dir -Filter '*.dmp' | Sort-Object Name | ForEach-Object {
    $n = $_.Name
    if ($n -eq '110526-10890-01.dmp') { return }
    $log = "$env:TEMP\p269db_$($_.BaseName).txt"
    & $kd -logo $log -z $_.FullName -c '!analyze -v; q' | Out-Null
    Add-Content -LiteralPath $res -Value "=== $n"
    Get-Content -LiteralPath $log | Where-Object { $_ -match '^(BUGCHECK_CODE|BUGCHECK_P\d|MODULE_NAME|IMAGE_NAME|SYMBOL_NAME|PROCESS_NAME|FAILURE_BUCKET_ID|WinRing0x64\+|AV_)' } |
        ForEach-Object { $_.Trim() } | Add-Content -LiteralPath $res
}