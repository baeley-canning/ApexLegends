# p269cf: resolve a base to its module name without assuming strides or record starts.
# Crib established from the ntoskrnl record: inline name starts at baseOffset+0x5A (DWORD len at +0x56).
# Control target = nt base (must resolve to ntoskrnl). Then the real targets. Read-only.
# NB: PowerShell desugars UInt64-Int32 to signed, so all arithmetic goes through Int64 reinterprets.
$dir = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps'
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269cf_resolve.txt'
Set-Content -LiteralPath $out -Value ('p269cf ' + (Get-Date -f 'HH:mm:ss'))
function ToU([uint64]$v) { return $v }
function Sub([uint64]$v, [int]$d) {
    $i = [BitConverter]::ToInt64([BitConverter]::GetBytes($v), 0) - $d
    return [BitConverter]::ToUInt64([BitConverter]::GetBytes($i), 0)
}
function Get-NameAt([byte[]]$b, [int64]$o) {
    $len = [BitConverter]::ToUInt32($b, [int]$o + 0x56)
    $sb = New-Object Text.StringBuilder
    $t = [int]$o + 0x5A
    while ($t -lt $b.Length - 1 -and [BitConverter]::ToUInt16($b, $t) -ne 0 -and $sb.Length -lt 260) {
        [void]$sb.Append([char][BitConverter]::ToUInt16($b, $t)); $t += 2
    }
    return ('lenField={0} name="{1}"' -f $len, $sb.ToString())
}
foreach ($d in (Get-ChildItem -LiteralPath $dir -Filter *.dmp | Sort-Object Name)) {
    $b = [IO.File]::ReadAllBytes($d.FullName)
    $p2 = [BitConverter]::ToUInt64($b, 0x48)
    $rip = [BitConverter]::ToUInt64($b, 0x440)
    $rsp = [BitConverter]::ToUInt64($b, 0x3E0)
    Add-Content -LiteralPath $out -Value ('== {0} p2=0x{1:X} rip=0x{2:X} rsp=0x{3:X}' -f $d.Name, $p2, $rip, $rsp)
    $targets = [ordered]@{}
    $targets['ctrl.nt']   = [Convert]::ToUInt64('FFFFF804C5600000', 16)
    $targets['p2-0x15B8'] = Sub $p2 0x15B8
    $targets['p2-0x5B8']  = Sub $p2 0x5B8
    $targets['rip-0x660'] = Sub $rip 0x660
    $targets['rip-0x1660']= Sub $rip 0x1660
    $targets['rip']       = $rip
    $targets['p2']        = $p2
    foreach ($k in $targets.Keys) {
        $v = $targets[$k]
        if ((($v -shr 32) -band 0xFFFF) -ne 0xFFFFF804 -and (($v -shr 32) -band 0xFFFFFF) -ne 0xFFFFF8 ) { }
        $bytes = [BitConverter]::GetBytes([uint64]$v)
        $hits = New-Object System.Collections.ArrayList
        for ($i = 0x10000; $i -lt 0x40000; $i += 8) {
            if ($b[$i] -ne $bytes[0] -or $b[$i+7] -ne 0xFF -or $b[$i+6] -ne 0xFF) { continue }
            if ([BitConverter]::ToUInt64($b, $i) -eq [uint64]$v) { [void]$hits.Add($i) }
        }
        if ($hits.Count -eq 0) { Add-Content -LiteralPath $out -Value ('  {0} 0x{1:X}  -> no hit' -f $k, $v); continue }
        foreach ($h in $hits) { Add-Content -LiteralPath $out -Value ('  {0} 0x{1:X}  @0x{2:X5} {3}' -f $k, $v, $h, (Get-NameAt $b $h)) }
    }
}
Add-Content -LiteralPath $out -Value 'END'
