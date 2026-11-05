# h276 side-check: what does GetProcAddress actually return for kernelbase!LoadLibraryW?
# The driver's export walk answered rva 0xFC5B0 and the file's own export table agrees, but
# the call still fails with 87. If the runtime answer differs, the walk is misreading the
# mapped image and the delta is the bug. Pure read, no driver, no writes.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class P {
    [DllImport("kernel32", CharSet=CharSet.Ansi, SetLastError=true)]
    public static extern IntPtr GetProcAddress(IntPtr h, string n);
    [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr GetModuleHandle(string n);
}
'@
function Hex([IntPtr]$p) { '0x' + $p.ToInt64().ToString('X') }
$kb  = [P]::GetModuleHandle('kernelbase.dll')
$k32 = [P]::GetModuleHandle('kernel32.dll')
if ($kb -eq [IntPtr]::Zero) { 'kernelbase not in this process'; exit 1 }
$ga  = [P]::GetProcAddress($kb, 'LoadLibraryW')
$k32a = [P]::GetProcAddress($k32, 'LoadLibraryW')
'kernelbase base = ' + (Hex $kb)
'GetProcAddress(kernelbase!LoadLibraryW) = ' + (Hex $ga)
'  -> rva vs kernelbase = 0x' + ($ga.ToInt64() - $kb.ToInt64()).ToString('X')
'kernel32!LoadLibraryW (what the launcher prints as "ours") = ' + (Hex $k32a)
'  -> rva vs kernel32 = 0x' + ($k32a.ToInt64() - $k32.ToInt64()).ToString('X')
'walk answer for comparison = 0xFC5B0'

