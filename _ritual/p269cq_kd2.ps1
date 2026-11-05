$kd = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269cq_kd2.txt'
foreach ($n in @('110526-10890-01', '110526-13843-01')) {
    $dmp = "c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\$n.dmp"
    $buf = [IO.File]::ReadAllBytes($dmp)
    $p2 = [BitConverter]::ToUInt64($buf, 0x48)
    $rip = [BitConverter]::ToUInt64($buf, 0x440)
    $cmds = 'ln {0:x}; ln {1:x}; .echo ===KV; kv; .echo ===AN; !analyze -v; q' -f $p2, $rip
    Add-Content -LiteralPath $out -Value ("##### $n p2=0x{0:X} rip=0x{1:X}" -f $p2, $rip)
    & $kd -z $dmp -c $cmds 2>&1 | Add-Content -LiteralPath $out
}
Add-Content -LiteralPath $out -Value '###DONE'
