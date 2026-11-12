# h318_allocprobe.ps1 - can anything still allocate at 0x180000000 / anywhere in the game at time T?
# Calibrates the window where the map step-5 failure (0xC000000D) comes and goes, without risking a
# payload. Two VirtualAllocEx calls (preferred base, then NULL), each freed again. Read-only.
param([Parameter(Mandatory = $true)][int]$TargetPid, [string]$Label = 'probe')
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class A {
  [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(int a, bool i, int p);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr addr, UIntPtr size, uint t, uint p);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool VirtualFreeEx(IntPtr h, IntPtr addr, UIntPtr size, uint t);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
}
'@
$h = [A]::OpenProcess(0x38, $false, $TargetPid)   # VM_OPERATION|VM_WRITE|VM_READ
if ($h -eq [IntPtr]::Zero) { "$Label open-fail err=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error(); exit 1 }
$size = [UIntPtr][uint64]0x54000
$r1 = [A]::VirtualAllocEx($h, [IntPtr]0x180000000, $size, 0x3000, 0x40)
$e1 = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
if ($r1 -ne [IntPtr]::Zero) { [void][A]::VirtualFreeEx($h, $r1, [UIntPtr]::Zero, 0x8000) }
$r2 = [A]::VirtualAllocEx($h, [IntPtr]::Zero, $size, 0x3000, 0x40)
$e2 = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
if ($r2 -ne [IntPtr]::Zero) { [void][A]::VirtualFreeEx($h, $r2, [UIntPtr]::Zero, 0x8000) }
[void][A]::CloseHandle($h)
"$Label pid=$TargetPid preferred=" + $(if ($r1 -ne [IntPtr]::Zero) { 'OK 0x' + $r1.ToString('X') } else { 'FAIL err=' + $e1 }) + ' anywhere=' + $(if ($r2 -ne [IntPtr]::Zero) { 'OK' } else { 'FAIL err=' + $e2 })


