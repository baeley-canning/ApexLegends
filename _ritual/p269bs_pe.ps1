# p269bs: is RVA 0x5B8 inside zapexdrv.sys's .text? Print PE header facts + section map
# for the images that appear in the crash dump's module list. Read-only (uses file bytes).
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269bs_pe.txt'
Set-Content -LiteralPath $out -Value ('p269bs ' + (Get-Date -f 'HH:mm:ss') + '  target RVA=0x5B8')
$files = @(
    'C:\p37vm\payload\zapexdrv.sys',
    'C:\p37vm\payload\gdrv3.sys',
    'C:\p37vm\payload\DBUtilDrv2.sys'
)
foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath $f)) { Add-Content -LiteralPath $out -Value ($f + ' MISSING'); continue }
    $b = [IO.File]::ReadAllBytes($f)
    Add-Content -LiteralPath $out -Value ('== ' + (Split-Path $f -Leaf) + ' size=' + $b.Length)
    $eLfanew = [BitConverter]::ToInt32($b, 0x3C)
    Add-Content -LiteralPath $out -Value ('  e_lfanew=0x' + $eLfanew.ToString('X') + ' magic=0x' + [BitConverter]::ToUInt16($b, $eLfanew + 24).ToString('X'))
    if ([BitConverter]::ToUInt32($b, $eLfanew) -ne 0x4550) { Add-Content -LiteralPath $out -Value '  not a PE'; continue }
    $nSec = [BitConverter]::ToUInt16($b, $eLfanew + 6)
    $szImg = [BitConverter]::ToUInt32($b, $eLfanew + 24 + 56)
    $entry = [BitConverter]::ToUInt32($b, $eLfanew + 24 + 16)
    $base = [BitConverter]::ToUInt64($b, $eLfanew + 24 + 24)
    Add-Content -LiteralPath $out -Value ('  sections=' + $nSec + ' SizeOfImage=0x' + $szImg.ToString('X') + ' EntryPoint=0x' + $entry.ToString('X') + ' ImageBase=0x' + $base.ToString('X'))
    $secBase = $eLfanew + 24 + [BitConverter]::ToUInt16($b, $eLfanew + 20)
    for ($i = 0; $i -lt $nSec; $i++) {
        $o = $secBase + ($i * 40)
        $nm = [Text.Encoding]::ASCII.GetString($b, $o, 8).Trim([char]0)
        $vsz = [BitConverter]::ToUInt32($b, $o + 8); $vad = [BitConverter]::ToUInt32($b, $o + 12)
        $rsz = [BitConverter]::ToUInt32($b, $o + 16); $rad = [BitConverter]::ToUInt32($b, $o + 20)
        $flag = ''
        if (0x5B8 -ge $vad -and 0x5B8 -lt ($vad + $vsz)) { $flag = '   <== 0x5B8 LANDS HERE' }
        Add-Content -LiteralPath $out -Value ('    ' + $nm.PadRight(8) + ' va=0x' + $vad.ToString('X') + ' vsz=0x' + $vsz.ToString('X') + ' raw=0x' + $rad.ToString('X') + ' rsz=0x' + $rsz.ToString('X') + $flag)
        if ($flag -and $rsz -gt 0 -and (0x5B8 - $vad) -lt $rsz) {
            $off = $rad + (0x5B8 - $vad)
            Add-Content -LiteralPath $out -Value ('    FILE OFFSET 0x' + $off.ToString('X') + ' bytes=' + (($b[$off..($off + 15)] | ForEach-Object { $_.ToString('X2') }) -join ' '))
        }
    }
}
Add-Content -LiteralPath $out -Value 'END'
