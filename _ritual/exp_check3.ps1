# Which indexing bug produces exactly 0xFC5B0?
# A: funcs + ordinal*4  -> 0xFC6D0 (correct)
# B: funcs + ordinal    (missing *4)      -> ?
# C: ordinals read as BYTE array          -> ?
$ErrorActionPreference = 'Stop'
$o = Join-Path $PSScriptRoot '_exp_check3.txt'
$b = [IO.File]::ReadAllBytes((Join-Path $env:SystemRoot 'System32\kernelbase.dll'))
function U32([int]$off) { [BitConverter]::ToUInt32($b, $off) }
function U16([int]$off) { [BitConverter]::ToUInt16($b, $off) }
$nt = U32 0x3C
$dirRva = U32 ($nt + 0x18 + 0x70)
$funcs = U32 ($dirRva + 0x1C)
$ords = U32 ($dirRva + 0x24)
$names = U32 ($dirRva + 0x20)
# locate LoadLibraryW name index again
$hit = -1
for ($i = 0; $i -lt (U32 ($dirRva + 0x18)); $i++) {
    $nr = U32 ($names + $i * 4); $e = $nr
    while ($b[$e] -ne 0) { $e++ }
    if ([Text.Encoding]::ASCII.GetString($b, $nr, $e - $nr) -eq 'LoadLibraryW') { $hit = $i; break }
}
$ordw = U16 ($ords + $hit * 2)
$ordlo = [int]$b[$ords + $hit * 2]
$ordhi = [int]$b[$ords + $hit * 2 + 1]
"hit=$hit ordinalWord=0x{0:X4} lowByte={1} highByte={2}" -f $ordw, $ordlo, $ordhi | Out-File $o -Encoding utf8
"A correct  = 0x{0:X}" -f (U32 ($funcs + $ordw * 4)) | Out-File $o -Append -Encoding utf8
"B no*4     = 0x{0:X}" -f (U32 ($funcs + $ordw))    | Out-File $o -Append -Encoding utf8
"C ord-bytes= 0x{0:X}" -f (U32 ($funcs + $ordlo * 4)) | Out-File $o -Append -Encoding utf8
"D funcs[loByte]=0x{0:X}" -f (U32 ($funcs + $ordlo * 4)) | Out-File $o -Append -Encoding utf8
'driver said 0xFC5B0' | Out-File $o -Append -Encoding utf8
Get-Content $o
