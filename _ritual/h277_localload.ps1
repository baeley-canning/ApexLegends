# h277 side-check: baseline the payload in the guest itself. If LoadLibraryW on this DLL fails
# here too (same build, same file), the 87 is the payload's doing and not the APC plumbing.
# Loads the DLL and, when it loads, resolves the local-load error separately from DllMain.
$p = 'C:\Users\Public\apexcheat.dll'
if (-not (Test-Path $p)) { 'missing payload'; exit 1 }
'payload bytes = ' + (Get-Item $p).Length
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class L {
    [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr LoadLibraryW(string p);
    [DllImport("kernel32", SetLastError=true)]
    public static extern bool FreeLibrary(IntPtr h);
}
'@
[Runtime.InteropServices.Marshal]::GetLastWin32Error() | Out-Null
$h = [L]::LoadLibraryW($p)
$e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
'handle = 0x' + $h.ToInt64().ToString('X') + ' err = ' + $e
if ($h -ne [IntPtr]::Zero) { 'LOAD OK'; [void][L]::FreeLibrary($h) } else { 'LOAD FAILED' }
# and the same call by bare relative name, to reproduce the launcher's path handling
Set-Location 'C:\Users\Public'
$h2 = [L]::LoadLibraryW('apexcheat.dll')
$e2 = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
'relative handle = 0x' + $h2.ToInt64().ToString('X') + ' err = ' + $e2
'unloaded before relative? no - second load returns the existing base'
