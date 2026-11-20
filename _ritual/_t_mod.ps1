# _t_mod - isolate whether module enumeration fails systemically or only on Apex
$o = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_t_mod.txt'
$src = @'
using System;
using System.Runtime.InteropServices;

public static class T
{
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint a, bool inh, int pid);
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags, int pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("psapi.dll", SetLastError=true)] static extern bool EnumProcessModulesEx(IntPtr h, IntPtr[] mods, int cb, out int need, uint filter);
    [DllImport("psapi.dll", SetLastError=true)] static extern bool EnumProcessModules(IntPtr h, IntPtr[] mods, int cb, out int need);

    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct MODENT
    {
        public uint dwSize; public uint th32ModuleID; public uint th32ProcessID;
        public uint GlblcntUsage; public uint ProccntUsage;
        public IntPtr modBaseAddr; public uint modBaseSize; public IntPtr hModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string szModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string szExePath;
    }

    public static string Probe(string label, int pid)
    {
        string r = label + ": ";
        IntPtr snap = CreateToolhelp32Snapshot(0x08 | 0x10, pid);
        if (snap == new IntPtr(-1)) r += "snap(08|10) err=" + Marshal.GetLastWin32Error();
        else
        {
            MODENT me = new MODENT(); me.dwSize = (uint)Marshal.SizeOf(typeof(MODENT));
            bool ok = false;
            if (ModuleFirst(snap, ref me)) { ok = true; r += "snap ok first=\"" + me.szModule + "\" base=0x" + me.modBaseAddr.ToInt64().ToString("x"); }
            else r += "snap ok but First err=" + Marshal.GetLastWin32Error();
            CloseHandle(snap);
            if (ok) r += "; ";
        }
        IntPtr snap32 = CreateToolhelp32Snapshot(0x08, pid);
        if (snap32 == new IntPtr(-1)) r += "snap(08) err=" + Marshal.GetLastWin32Error() + "; ";
        else { r += "snap(08) ok; "; CloseHandle(snap32); }

        IntPtr h = OpenProcess(0x0410, false, pid);
        if (h == IntPtr.Zero) { r += "open err=" + Marshal.GetLastWin32Error(); return r; }
        IntPtr[] mods = new IntPtr[512]; int need;
        if (EnumProcessModulesEx(h, mods, mods.Length * IntPtr.Size, out need, 3)) r += "enumEx(3) ok n=" + need / IntPtr.Size;
        else r += "enumEx(3) err=" + Marshal.GetLastWin32Error();
        int need2;
        if (EnumProcessModules(h, mods, mods.Length * IntPtr.Size, out need2)) r += "; enumplain ok n=" + need2 / IntPtr.Size;
        else r += "; enumplain err=" + Marshal.GetLastWin32Error();
        CloseHandle(h);
        return r;
    }

    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool Module32FirstW(IntPtr s, ref MODENT m);
    static bool ModuleFirst(IntPtr s, ref MODENT m) { return Module32FirstW(s, ref m); }
}
'@

Add-Type -TypeDefinition $src
$lines = @()
$lines += "is64=" + [Environment]::Is64BitProcess + " os64=" + [Environment]::Is64BitOperatingSystem
foreach ($n in 'explorer', 'r5apex_dx12') {
    $p = Get-Process -Name $n -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p) { $lines += [T]::Probe($n + '(' + $p.Id + ')', $p.Id) } else { $lines += "$n : not running" }
}
$lines -join "`r`n" | Out-File -LiteralPath $o -Encoding ascii
