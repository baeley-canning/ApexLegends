# p269bw: the triage dump header carries the crashing CONTEXT (ContextRecord @0x348, Rip @+0xF8).
# Scan the header window for qwords inside [p2base, p2base+0x20000) => code/data in the faulting image.
# Read-only.
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269bw_ctx.txt'
Set-Content -LiteralPath $out -Value ('p269bw ' + (Get-Date -f 'HH:mm:ss'))
foreach ($d in (Get-ChildItem -LiteralPath 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps' -Filter *.dmp)) {
    $b = [IO.File]::ReadAllBytes($d.FullName)
    $p2 = [BitConverter]::ToUInt64($b, 0x48); $base = $p2 - 0x5B8
    Add-Content -LiteralPath $out -Value ('== {0} base=0x{1:X}' -f $d.Name, $base)
    Add-Content -LiteralPath $out -Value ('   ctx.Rip(@0x440)=0x{0:X}  ctx.Rsp(@0x3E0)=0x{1:X}  ctx.EFlags(@0x3A8)=0x{2:X}' -f ([BitConverter]::ToUInt64($b, 0x440)), ([BitConverter]::ToUInt64($b, 0x3E0)), ([BitConverter]::ToUInt32($b, 0x3A8)))
    for ($i = 0x100; $i -lt 0x2000; $i += 8) {
        $v = [BitConverter]::ToUInt64($b, $i)
        if ($v -lt $base -or $v -ge ($base + 0x20000)) { continue }
        Add-Content -LiteralPath $out -Value ('   @0x{0:X4} 0x{1:X16} +0x{2:X}' -f $i, $v, ($v - $base))
    }
}
Add-Content -LiteralPath $out -Value 'END'
