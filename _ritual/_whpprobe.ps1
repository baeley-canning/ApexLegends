$o='C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_whpprobe.txt'
"=== run $(Get-Date -Format o) ===" | Out-File $o -Encoding ascii
"admin=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) | Out-File $o -Append -Encoding ascii
"user=" + [Security.Principal.WindowsIdentity]::GetCurrent().Name | Out-File $o -Append -Encoding ascii

$src = @'
using System;
using System.Runtime.InteropServices;
public static class Whp {
  [DllImport("WinHvPlatform.dll", ExactSpelling=true)]
  public static extern int WHvGetCapability(int code, IntPtr buf, uint bufSize, out uint written);
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
try { Add-Type -TypeDefinition $src -ErrorAction Stop; "compile=ok" | Out-File $o -Append -Encoding ascii }
catch { "compile=FAIL " + $_.Exception.Message | Out-File $o -Append -Encoding ascii; return }

function Hex($v) { $i = [int32]$v; $u = [BitConverter]::ToUInt32([BitConverter]::GetBytes($i), 0); '0x' + $u.ToString('X8') }

$buf = [Runtime.InteropServices.Marshal]::AllocHGlobal(128)
$w = [uint32]0
$hr = [Whp]::WHvGetCapability(0, $buf, 128, [ref]$w)
"cap.hvPresent hr=$(Hex $hr) present=" + [Runtime.InteropServices.Marshal]::ReadInt32($buf) | Out-File $o -Append -Encoding ascii
[Runtime.InteropServices.Marshal]::FreeHGlobal($buf)

foreach ($mode in 'bare','withCount') {
  $p = [IntPtr]::Zero
  $hr = [Whp]::WHvCreatePartition([ref]$p)
  "  $mode create hr=$(Hex $hr) handle=$p" | Out-File $o -Append -Encoding ascii
  if ($hr -lt 0) { continue }
  if ($mode -eq 'withCount') {
    $b = [Runtime.InteropServices.Marshal]::AllocHGlobal(4)
    [Runtime.InteropServices.Marshal]::WriteInt32($b, 1)
    $hr2 = [Whp]::WHvSetPartitionProperty($p, 0x00001000, $b, 4)
    "  $mode setCount hr=$(Hex $hr2)" | Out-File $o -Append -Encoding ascii
    [Runtime.InteropServices.Marshal]::FreeHGlobal($b)
  }
  $hr3 = [Whp]::WHvSetupPartition($p)
  "  $mode setup hr=$(Hex $hr3)" | Out-File $o -Append -Encoding ascii
  $null = [Whp]::WHvDeletePartition($p)
}
"=== end ===" | Out-File $o -Append -Encoding ascii

