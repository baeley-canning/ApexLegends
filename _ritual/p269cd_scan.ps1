# p269cd: stop using any assumed stride. For each interesting base value, find every qword-aligned
# occurrence in the header area and print the record's inline UNICODE name at +0x5C. Read-only.
param([string]$Dump = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269_dumps\110526-10890-01.dmp',
      [string]$Targets = 'p2minus15B8,ripminus1660,ripminus660,nt')
$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269cd_scan.txt'
Set-Content -LiteralPath $out -Value ('p269cd ' + (Get-Date -f 'HH:mm:ss') + ' ' + (Split-Path -Leaf $Dump))
$b = [IO.File]::ReadAllBytes($Dump)
Add-Content -LiteralPath $out -Value ('len=0x{0:X}' -f $b.Length)
if ($b.Length -le 0x200) { Add-Content -LiteralPath $out -Value 'END'; return }
$p2 = [BitConverter]::ToUInt64($b, 0x348 + 0xF8)
$rip = [BitConverter]::ToUInt64($b, 0x348 + 0xF8)
