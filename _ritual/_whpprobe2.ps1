$o='C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_whpprobe2.txt'
"=== run $(Get-Date -Format o) ===" | Out-File $o -Encoding ascii
"admin=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) | Out-File $o -Append -Encoding ascii
"user=" + [Security.Principal.WindowsIdentity]::GetCurrent().Name | Out-File $o -Append -Encoding ascii
"session=" + (Get-Process -Id $PID).SessionId | Out-File $o -Append -Encoding ascii

$src = @'
using System;
using System.Runtime.InteropServices;
public static class Whp3 {
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
function Name($v) {
  switch (Hex $v) {
    '0x00000000' { 'S_OK'; break }
    '0xC0000022' { 'E_ACCESSDENIED'; break }
    '0x80370300' { 'WHV_E_UNKNOWN_CAPABILITY'; break }
    '0x80370301' { 'WHV_E_INSUFFICIENT_BUFFER'; break }
    '0x80370302' { 'WHV_E_UNKNOWN_PROPERTY'; break }
    '0x80370303' { 'WHV_E_UNKNOWN_REGISTER'; break }
    '0x80370304' { 'WHV_E_INVALID_PARTITION_STATE'; break }
    '0x80370305' { 'WHV_E_INVALID_PARTITION_PROPERTY'; break }
    '0x80370306' { 'WHV_E_INVALID_PROCESSOR_INDEX'; break }
    default { '' }
  }
}
function Log($s) { ($s + '   [' + (Name $script:last) + ']') | Out-File $o -Append -Encoding ascii }

$buf = [Runtime.InteropServices.Marshal]::AllocHGlobal(16)
$w = [uint32]0
$cap = [Whp3]::WHvGetCapability(0, $buf, 16, [ref]$w)
$hv = [Runtime.InteropServices.Marshal]::ReadInt32($buf)
"cap.hypervisorPresent=$hv hr=$(Hex $cap)" | Out-File $o -Append -Encoding ascii
[Runtime.InteropServices.Marshal]::FreeHGlobal($buf)

foreach ($mode in 'bare','count') {
  $p = [IntPtr]::Zero
  $c = [Whp3]::WHvCreatePartition([ref]$p)
  $script:last = $c
  "  $mode create=$(Hex $c) handle=$p" | Out-File $o -Append -Encoding ascii
  if ($c -lt 0) { continue }
  if ($mode -eq 'count') {
    $b = [Runtime.InteropServices.Marshal]::AllocHGlobal(4)
    [Runtime.InteropServices.Marshal]::WriteInt32($b, 1)
    $s = [Whp3]::WHvSetPartitionProperty($p, 0x00001FFF, $b, 4)
    "  $mode setProcessorCount=$(Hex $s)" | Out-File $o -Append -Encoding ascii
    [Runtime.InteropServices.Marshal]::FreeHGlobal($b)
  }
  $st = [Whp3]::WHvSetupPartition($p)
  $script:last = $st
  "  $mode setup=$(Hex $st)" | Out-File $o -Append -Encoding ascii
  $st2 = [Whp3]::WHvSetupPartition($p)
  "  $mode setupAgain=$(Hex $st2)" | Out-File $o -Append -Encoding ascii
  $d = [Whp3]::WHvDeletePartition($p)
  "  $mode delete=$(Hex $d)" | Out-File $o -Append -Encoding ascii
}
"=== end ===" | Out-File $o -Append -Encoding ascii
