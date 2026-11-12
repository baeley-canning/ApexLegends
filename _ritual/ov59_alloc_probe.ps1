# ov59_alloc_probe.ps1 - can an ELEVATED process still allocate in r5apex_dx12?
#
# The ladder fails every usermode rung with `VirtualAllocEx ... 5`.  Before
# choosing a workaround, this probe isolates the one call: OpenProcess with the
# exact rights the loaders need, then VirtualAllocEx RW and RWX, then free.
# Read-only apart from one transient allocation, no driver, no DSE change.
param([int] $Pid_ = 0, [string] $Out = 'C:\h320x\t287_alloc.txt')

Add-Type @'
using System; using System.Runtime.InteropServices;
public class AP {
  [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(int a, bool h, int pid);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr VirtualAllocEx(IntPtr p, IntPtr a, UIntPtr s, uint t, uint pr);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool VirtualFreeEx(IntPtr p, IntPtr a, UIntPtr s, uint t);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool ReadProcessMemory(IntPtr p, IntPtr a, byte[] b, UIntPtr s, out UIntPtr r);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
}
'@
$utf8 = [Text.UTF8Encoding]::new($false)
$lines = @("alloc probe - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') pid=$Pid_",
           'elevated : ' + (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)))

# 0x1FFFFF = PROCESS_ALL_ACCESS-ish set the launcher asks for
foreach ($access in @(0x1FFFFF, 0x0438, 0x0008)) {
    $h = [AP]::OpenProcess($access, $false, $Pid_)
    $lines += ('OpenProcess(0x{0:X}) -> {1} err={2}' -f $access, $h, [Runtime.InteropServices.Marshal]::GetLastWin32Error())
    if ($h -ne [IntPtr]::Zero) {
        foreach ($prot in @(0x04, 0x40)) {          # RW, RWX
            $a = [AP]::VirtualAllocEx($h, [IntPtr]::Zero, [UIntPtr]::new(0x1000), 0x3000, $prot)
            $lines += ('  VirtualAllocEx(prot=0x{0:X}) -> {1} err={2}' -f $prot, $a, [Runtime.InteropServices.Marshal]::GetLastWin32Error())
            if ($a -ne [IntPtr]::Zero) { [void][AP]::VirtualFreeEx($h, $a, [UIntPtr]::Zero, 0x8000) }
        }
        $sg = [IntPtr]::Zero
        $buf = New-Object byte[] 2
        $got = [UIntPtr]::Zero
        $ok = [AP]::ReadProcessMemory($h, [IntPtr]::new(0x10000), $buf, [UIntPtr]::new(2), [ref]$got)
        $lines += ('  ReadProcessMemory(0x10000) -> {0} err={1}' -f $ok, [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        [void][AP]::CloseHandle($h)
    }
}
[IO.File]::WriteAllText($Out, ($lines -join "`r`n") + "`r`n", $utf8)
