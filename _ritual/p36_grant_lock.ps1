# p36_grant_lock.ps1 - grant SeLockMemoryPrivilege (policy "Lock pages in memory")
# to SYSTEM + Administrators, then force a fresh p36 run.
#
# Why: build 26200 no longer puts SeLockMemoryPrivilege in default tokens - not even
# a genuine SYSTEM one (12:20 run: identity=SYSTEM isSystem=True, privilege
# NOT_ASSIGNED, NtOpenSection 0xC0000022).  Every task start creates a NEW SYSTEM
# token, so an LSA grant needs no re-logon - it applies to the very next run.
$log = Join-Path $PSScriptRoot '_p36_grant.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"') -Verb RunAs -Wait
    exit 0
}
Set-Content -LiteralPath $log -Value ('grant run ' + (Get-Date -f 'HH:mm:ss')) -Encoding UTF8

$cs = @'
using System;
using System.Runtime.InteropServices;
public static class LsaPriv {
    [StructLayout(LayoutKind.Sequential)] public struct LSA_UNICODE_STRING { public ushort Length, MaxLength; public IntPtr Buffer; }
    [StructLayout(LayoutKind.Sequential)] public struct LSA_OBJECT_ATTRIBUTES { public int Length; public IntPtr RootDirectory, ObjectName; public uint Attributes; public IntPtr SecurityDescriptor, SecurityQualityOfService; }
    [DllImport("advapi32.dll", SetLastError = true)] static extern int LsaOpenPolicy(IntPtr sys, ref LSA_OBJECT_ATTRIBUTES oa, uint access, out IntPtr pol);
    [DllImport("advapi32.dll", SetLastError = true)] static extern int LsaAddAccountRights(IntPtr pol, IntPtr sid, LSA_UNICODE_STRING[] rights, uint count);
    [DllImport("advapi32.dll")] static extern int LsaClose(IntPtr pol);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool ConvertStringSidToSidW(string s, out IntPtr sid);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr h);

    public static string Grant(string sidStr, string priv) {
        IntPtr sid;
        if (!ConvertStringSidToSidW(sidStr, out sid)) return "ConvertSid err=" + Marshal.GetLastWin32Error();
        IntPtr nameBuf = Marshal.StringToHGlobalUni(priv);
        LSA_OBJECT_ATTRIBUTES oa = new LSA_OBJECT_ATTRIBUTES();
        oa.Length = Marshal.SizeOf(typeof(LSA_OBJECT_ATTRIBUTES));
        IntPtr pol;
        int st = LsaOpenPolicy(IntPtr.Zero, ref oa, 0x00F0FFF, out pol);
        if (st != 0) { LocalFree(nameBuf); LocalFree(sid); return "OpenPolicy nt=0x" + st.ToString("x"); }
        LSA_UNICODE_STRING u; u.Length = (ushort)(priv.Length * 2); u.MaxLength = (ushort)(priv.Length * 2 + 2); u.Buffer = nameBuf;
        LSA_UNICODE_STRING[] arr = new LSA_UNICODE_STRING[] { u };
        st = LsaAddAccountRights(pol, sid, arr, 1);
        LsaClose(pol); LocalFree(nameBuf); LocalFree(sid);
        return st == 0 ? "OK" : "AddRights nt=0x" + st.ToString("x");
    }
}
'@
try { Add-Type -TypeDefinition $cs -ErrorAction Stop } catch { Add-Content -LiteralPath $log -Value ('compile FAIL: ' + $_.Exception.Message) ; exit 1 }

foreach ($sid in 'S-1-5-18', 'S-1-5-32-544') {
    try { Add-Content -LiteralPath $log -Value ($sid + ' -> ' + [LsaPriv]::Grant($sid, 'SeLockMemoryPrivilege')) }
    catch { Add-Content -LiteralPath $log -Value ($sid + ' EXC: ' + $_.Exception.Message) }
}

# verify from the (now-elevated) token, then force a fresh task run
$pv = (whoami /priv | Select-String 'SeLockMemory')
Add-Content -LiteralPath $log -Value ('self priv line: ' + ($pv -join ' '))
# wait out any in-flight run (MultipleInstances=IgnoreNew would swallow the start)
for ($i = 0; $i -lt 24; $i++) {
    if ((Get-ScheduledTask -TaskName 'QwenKern_p36').State -ne 'Running') { break }
    Start-Sleep -Milliseconds 500
}
Remove-Item -LiteralPath (Join-Path $PSScriptRoot 'p36_write.txt') -EA 0
Remove-Item -LiteralPath (Join-Path $PSScriptRoot '_p36_stderr.txt') -EA 0
Start-ScheduledTask -TaskName 'QwenKern_p36'
Add-Content -LiteralPath $log -Value ('task started, state=' + (Get-ScheduledTask -TaskName 'QwenKern_p36').State)
