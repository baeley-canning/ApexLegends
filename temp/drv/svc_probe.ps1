# svc_probe.ps1 -- which kernel drivers related to this project (and which
# vulnerable signed drivers we could borrow) are installed and running?
$out = Join-Path $PSScriptRoot 'svc_probe.txt'
$lines = New-Object System.Collections.Generic.List[string]
function L($s) { $lines.Add([string]$s) }

L '=== Win32_SystemDriver (filtered)'
Get-CimInstance Win32_SystemDriver -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'apex|gdrv|msio|asio|winio|ene|rtcore|cpuz' } |
    Sort-Object Name |
    ForEach-Object { L ("  {0,-16} {1,-10} {2,-8} {3}" -f $_.Name, $_.State, $_.StartMode, $_.PathName) }

L ''
L '=== files in System32\drivers matching apex/asio/gdrv/msio'
Get-ChildItem "$env:SystemRoot\System32\drivers" -Filter '*.sys' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^(apex|gdrv|msio|asio|winio|ene)' } |
    ForEach-Object {
        $sig = '?'
        try {
            $s = Get-AuthenticodeSignature $_.FullName
            $sig = "$($s.Status)/$($s.SignerCertificate.Subject -replace ',.*','')"
        } catch { }
        L ("  {0,-14} {1,6}  {2:yyyy-MM-dd}  {3}" -f $_.Name, $_.Length, $_.LastWriteTime, $sig)
    }

L ''
L '=== loaded kernel modules (top of \Driver object dir via NtQuerySystemInformation)'
if (-not ('ModList' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class ModList {
  [DllImport("ntdll.dll")] public static extern int NtQuerySystemInformation(int cls, IntPtr buf, int len, out int ret);
  public static string[] Get() {
    int len = 1 << 20; IntPtr p = Marshal.AllocHGlobal(len); int ret;
    int st = NtQuerySystemInformation(11, p, len, out ret);
    if (st < 0) { Marshal.FreeHGlobal(p); return new string[] { "err=" + st }; }
    int n = Marshal.ReadInt32(p);
    var res = new string[n];
    long basep = p.ToInt64() + 8;
    for (int i = 0; i < n; i++) {
      IntPtr e = new IntPtr(basep + i * 296);
      IntPtr namePtr = Marshal.ReadIntPtr(e, 0x58);  // ImageName UNICODE_STRING.Buffer (x64)
      ushort l = (ushort)Marshal.ReadInt16(e, 0x50);
      res[i] = Marshal.PtrToStringUni(namePtr, l / 2) + "  base=0x" + Marshal.ReadInt64(e, 0x30).ToString("x");
    }
    Marshal.FreeHGlobal(p); return res;
  }
}
'@
}
$mods = [ModList]::Get()
L ("  total modules = " + $mods.Count)
$mods | Where-Object { $_ -match 'apex|gdrv|msio|asio|winio|ene|iqvw' } | ForEach-Object { L ("  " + $_) }

L ''
L '=== device namespaces we can open (no admin needed for some)'
foreach ($d in '\\.\apexr', '\\.\apexdrv', '\\.\gdrv', '\\.\gdrv3', '\\.\MsIo64', '\\.\MsIo', '\\.\AsIO3', '\\.\AsUpIO') {
    $ok = $false
    try {
        $h = [System.IO.File]::Open($d, 'Open', 'ReadWrite', 'None'); $h.Close(); $ok = $true
    } catch { }
    L ("  {0,-14} openable={1}" -f $d, $ok)
}

Set-Content -LiteralPath $out -Value ($lines -join "`r`n") -Encoding UTF8
Write-Host ("wrote " + $out)
