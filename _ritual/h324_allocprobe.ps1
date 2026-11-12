# h324 - is VirtualAllocEx err=87 our call signature, or the protected target?
# Same elevated process allocates the same buffer in (a) a fresh notepad and
# (b) the live EA-launched game (29184 or first live).  One variable: target.
param([int] $GamePid = 0, [switch] $Elevate)
$outF = 'C:\h320x\h324.out'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and $Elevate) {
    $extra = ' -Elevate'
    if ($GamePid -gt 0) { $extra += " -GamePid $GamePid" }
    Start-Process powershell -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"{1}' -f $PSCommandPath, $extra)
    exit 0
}
Remove-Item $outF -Force -ErrorAction SilentlyContinue
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class A24 {
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr OpenProcess(uint a, bool i, int pid);
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr VirtualAllocEx(IntPtr hp, IntPtr addr, IntPtr size, uint type, uint prot);
    [DllImport("kernel32", SetLastError=true)] public static extern bool VirtualFreeEx(IntPtr hp, IntPtr addr, IntPtr size, uint type);
    [DllImport("kernel32", SetLastError=true)] public static extern bool WriteProcessMemory(IntPtr hp, IntPtr addr, byte[] b, IntPtr n, out IntPtr done);
    [DllImport("kernel32", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
    public static string Try(int pid, string label) {
        IntPtr h = OpenProcess(0x1F0FFF, false, pid);
        if (h == IntPtr.Zero) return label + " pid=" + pid + " OpenProcess err=" + Marshal.GetLastWin32Error();
        IntPtr m = VirtualAllocEx(h, IntPtr.Zero, (IntPtr)120, 0x3000, 0x40);
        int e = Marshal.GetLastWin32Error();
        string r;
        if (m == IntPtr.Zero) { r = label + " pid=" + pid + " alloc FAILED err=" + e; }
        else {
            byte[] b = new byte[120];
            IntPtr w;
            bool ok = WriteProcessMemory(h, m, b, (IntPtr)120, out w);
            r = label + " pid=" + pid + " alloc OK at 0x" + m.ToString("X") + " write=" + ok + " werr=" + Marshal.GetLastWin32Error();
            VirtualFreeEx(h, m, IntPtr.Zero, 0x8000);
        }
        CloseHandle(h);
        return r;
    }
}
'@
function W($m) { $m | Out-File -FilePath $outF -Append -Encoding utf8 }
W ("h324 - alloc/write control, elevated=$isAdmin - " + (Get-Date -Format 'HH:mm:ss'))
$np = Start-Process notepad -PassThru
Start-Sleep -Milliseconds 800
W ('(a) ' + [A24]::Try($np.Id, 'notepad'))
W ('(b) ' + [A24]::Try([int](Get-Process -Id $PID).Id, 'self   '))
$g = if ($GamePid -gt 0) { Get-Process -Id $GamePid -ErrorAction SilentlyContinue } else { @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue) | Select-Object -First 1 }
if ($g) { W ('(c) ' + [A24]::Try($g.Id, 'game   ')) } else { W '(c) no live game' }
Stop-Process -Id $np.Id -Force -ErrorAction SilentlyContinue
W 'RESULT: (a) failing = our call; only (c) failing = target protection'
W 'h324 DONE'
Get-Content $outF
