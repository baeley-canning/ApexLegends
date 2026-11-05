$kd = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269ct_all5.txt'
foreach ($n in @('110526-8671-01', '110526-9234-01', '110526-9843-01')) {
    $dmp = "c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\$n.dmp"
    Add-Content -LiteralPath $out -Value "##### $n"
    & $kd -z $dmp -c '!analyze -v; q' 2>&1 |
        Select-String -Pattern 'MODULE_NAME|IMAGE_NAME|SYMBOL_NAME|PROCESS_NAME|FAILURE_BUCKET|BUGCHECK_CODE|WinRing0x64\+' |
        ForEach-Object { $_.Line.Trim() } | Add-Content -LiteralPath $out
}
Add-Content -LiteralPath $out -Value '###DONE'
