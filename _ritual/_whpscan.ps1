$o='C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_whpscan.txt'
"=== scan $(Get-Date -Format o) ===" | Out-File $o -Encoding ascii
$src = @'
using System;
using System.Runtime.InteropServices;
public static class Whp2 {
  [DllImport("WinHvPlatform.dll", ExactSpelling=true)]
  public static extern int WHvCreatePartition(out IntPtr part);
  [DllImport("WinHvPlatform.dll", ExactSpelling=true)]
  public static extern int WHvSetPartitionProperty(IntPtr part, int code, IntPtr buf, uint size);
  [DllImport("WinHvPlatform.dll", ExactSpelling=true)]
  public static extern int WHvSetupPartition(IntPtr part);
  [DllImport("WinHvPlatform.dll", ExactSpelling=true)]
  public static extern int WHvDeletePartition(IntPtr part);
}
'@
Add-Type -TypeDefinition $src
function Hex($v) { $i = [int32]$v; $u = [BitConverter]::ToUInt32([BitConverter]::GetBytes($i), 0); '0x' + $u.ToString('X8') }

$b8 = [Runtime.InteropServices.Marshal]::AllocHGlobal(8)
[Runtime.InteropServices.Marshal]::WriteInt64($b8, 1)

foreach ($code in 0x1000..0x1006) {
  $p = [IntPtr]::Zero
  $hr = [Whp2]::WHvCreatePartition([ref]$p)
  if ($hr -lt 0) { "code=0x$('{0:X4}' -f $code) create=$(Hex $hr)" | Out-File $o -Append -Encoding ascii; continue }
  $s4 = [Whp2]::WHvSetPartitionProperty($p, $code, $b8, 4)
  $s8 = [Whp2]::WHvSetPartitionProperty($p, $code, $b8, 8)
  $st = [Whp2]::WHvSetupPartition($p)
  "code=0x$('{0:X4}' -f $code) set4=$(Hex $s4) set8=$(Hex $s8) setup=$(Hex $st)" | Out-File $o -Append -Encoding ascii
  $null = [Whp2]::WHvDeletePartition($p)
}
[Runtime.InteropServices.Marshal]::FreeHGlobal($b8)
"=== end ===" | Out-File $o -Append -Encoding ascii
