Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CE3 {
    static readonly Guid DRV = new Guid("F750E6C3-38EE-11D1-85E5-00C04FC295EE");
    [DllImport("wintrust.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool CryptCATAdminAcquireContext2(out IntPtr h, IntPtr pSub, string alg, IntPtr policy, int flags);
    [DllImport("wintrust.dll", SetLastError=true)] static extern bool CryptCATAdminAcquireContext(out IntPtr h, IntPtr pSub, int flags);
    [DllImport("wintrust.dll", SetLastError=true)] static extern bool CryptCATAdminReleaseContext(IntPtr h, int flags);
    [DllImport("wintrust.dll", SetLastError=true)] static extern IntPtr CryptCATAdminEnumCatalogFromHash(IntPtr h, byte[] hash, int cb, int flags, ref IntPtr prev);
    [DllImport("wintrust.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool CryptCATCatalogInfoFromContext(IntPtr ci, ref CAT_INFO info, int flags);
    [DllImport("wintrust.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern uint WinVerifyTrust(IntPtr hwnd, ref Guid action, IntPtr data);
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct CAT_INFO { public int cbStruct; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string name; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct WTD { public int cbStruct; public IntPtr pPolicy; public IntPtr pSIP; public int uiChoice; public int rev; public int unionChoice; public IntPtr pUnion; public int stateAction; public IntPtr hState; public IntPtr urlRef; public int provFlags; public int uiContext; public IntPtr pSigSettings; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct WCI { public int cbStruct; public string catFile; public string memberTag; public string memberFile; public IntPtr hMember; public IntPtr pHash; public int cbHash; public IntPtr hCatAdmin; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct FINF { public int cbStruct; public string filePath; public IntPtr hFile; public IntPtr pKnown; }
    static IntPtr GP(Guid g) { IntPtr p = Marshal.AllocHGlobal(16); Marshal.StructureToPtr(g, p, false); return p; }
    public static string EnumVar(byte[] hash, string alg, int v) {
        IntPtr hp = IntPtr.Zero; IntPtr h = IntPtr.Zero; bool ok;
        try {
            if (v == 1) { hp = GP(DRV); ok = CryptCATAdminAcquireContext2(out h, hp, alg, IntPtr.Zero, 0); }
            else if (v == 2) { hp = GP(DRV); ok = CryptCATAdminAcquireContext2(out h, hp, null, IntPtr.Zero, 0); }
            else if (v == 3) { ok = CryptCATAdminAcquireContext2(out h, IntPtr.Zero, alg, IntPtr.Zero, 0); }
            else if (v == 4) { hp = GP(DRV); ok = CryptCATAdminAcquireContext(out h, hp, 0); }
            else { ok = CryptCATAdminAcquireContext(out h, IntPtr.Zero, 0); }
            if (!ok) return "ctx-ERR" + Marshal.GetLastWin32Error();
            try {
                IntPtr prev = IntPtr.Zero;
                IntPtr ci = CryptCATAdminEnumCatalogFromHash(h, hash, hash.Length, 0, ref prev);
                if (ci == IntPtr.Zero) return "NONE(err" + Marshal.GetLastWin32Error() + ")";
                var x = new CAT_INFO(); x.cbStruct = Marshal.SizeOf(typeof(CAT_INFO));
                string nm = "?"; if (CryptCATCatalogInfoFromContext(ci, ref x, 0)) nm = System.IO.Path.GetFileName(x.name);
                return "FOUND " + nm;
            } finally { CryptCATAdminReleaseContext(h, 0); }
        } finally { if (hp != IntPtr.Zero) Marshal.FreeHGlobal(hp); }
    }
    public static uint WvtCatalog(string catFile, string memberFile, byte[] hash, string alg) {
        IntPtr hp = GP(DRV); IntPtr h = IntPtr.Zero;
        if (!CryptCATAdminAcquireContext2(out h, hp, alg, IntPtr.Zero, 0)) { Marshal.FreeHGlobal(hp); return 0xFFFFFFFF; }
        int sc = Marshal.SizeOf(typeof(WCI)), sd = Marshal.SizeOf(typeof(WTD));
        IntPtr ciP = Marshal.AllocHGlobal(sc), dP = Marshal.AllocHGlobal(sd), hashP = Marshal.AllocHGlobal(hash.Length);
        Marshal.Copy(hash, 0, hashP, hash.Length);
        try {
            var ci = new WCI();
            ci.cbStruct = sc; ci.catFile = catFile; ci.memberTag = null; ci.memberFile = memberFile;
            ci.hMember = IntPtr.Zero; ci.pHash = hashP; ci.cbHash = hash.Length; ci.hCatAdmin = h;
            Marshal.StructureToPtr(ci, ciP, false);
            var d = new WTD();
            d.cbStruct = sd; d.uiChoice = 2; d.rev = 0; d.unionChoice = 2; d.pUnion = ciP; d.provFlags = 0x1010;
            Marshal.StructureToPtr(d, dP, false);
            Guid act = new Guid("00AAC56B-CD44-11D0-8CC2-00C04FC295EE");
            return WinVerifyTrust(IntPtr.Zero, ref act, dP);
        } finally { Marshal.FreeHGlobal(hashP); Marshal.FreeHGlobal(ciP); Marshal.FreeHGlobal(dP); Marshal.FreeHGlobal(hp); CryptCATAdminReleaseContext(h, 0); }
    }
    public static uint WvtFile(string memberFile) {
        int sf = Marshal.SizeOf(typeof(FINF)), sd = Marshal.SizeOf(typeof(WTD));
        IntPtr fiP = Marshal.AllocHGlobal(sf), dP = Marshal.AllocHGlobal(sd);
        try {
            var fi = new FINF(); fi.cbStruct = sf; fi.filePath = memberFile; fi.hFile = IntPtr.Zero; fi.pKnown = IntPtr.Zero;
            Marshal.StructureToPtr(fi, fiP, false);
            var d = new WTD();
            d.cbStruct = sd; d.uiChoice = 2; d.rev = 0; d.unionChoice = 1; d.pUnion = fiP; d.provFlags = 0x1010;
            Marshal.StructureToPtr(d, dP, false);
            Guid act = new Guid("00AAC56B-CD44-11D0-8CC2-00C04FC295EE");
            return WinVerifyTrust(IntPtr.Zero, ref act, dP);
        } finally { Marshal.FreeHGlobal(fiP); Marshal.FreeHGlobal(dP); }
    }
}
'@


$d = $PSScriptRoot
$log = Join-Path $d 'probe2.txt'
"probe2 $(Get-Date -Format s)" | Set-Content -Encoding utf8 $log
function P($s) { Add-Content -Encoding utf8 $log $s }
function Hex2Bytes($h) { $b = New-Object byte[] ($h.Length / 2); for ($i = 0; $i -lt $b.Length; $i++) { $b[$i] = [Convert]::ToByte($h.Substring($i * 2, 2), 16) }; return $b }

$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
P "identity=$env:USERDOMAIN\$env:USERNAME elevated=$adm"
P ("cryptsvc=" + (Get-Service cryptsvc -ErrorAction SilentlyContinue).Status + " trustinstaller=" + (Get-Service TrustedInstaller -ErrorAction SilentlyContinue).Status)
P ("signtool=" + ((Get-Command signtool -ErrorAction SilentlyContinue) | Select-Object -First 1 -ExpandProperty Source))

$cr2 = Join-Path $env:SystemRoot 'System32\CatRoot2'
$db = Join-Path $cr2 '{F750E6C3-38EE-11D1-85E5-00C04FC295EE}\catdb'
$dbi = Get-Item -LiteralPath $db
P ("catdb ts=" + $dbi.LastWriteTime + " size=" + $dbi.Length)
$de = Join-Path $cr2 'dberr.txt'
if (Test-Path -LiteralPath $de) {
    $ln = @(Get-Content -LiteralPath $de)
    P ("dberr lines=" + $ln.Count + " ts=" + (Get-Item -LiteralPath $de).LastWriteTime)
    foreach ($x in @($ln | Select-Object -Last 25)) { P ("  DBERR " + $x) }
}

$scan = @(Get-Content -LiteralPath (Join-Path $d 'cateng_scan.txt'))
$h1 = (($scan | Where-Object { $_ -match '^\s+sha1 engine=' } | Select-Object -Last 1) -replace '^\s+sha1 engine=', '').Trim()
$h2 = (($scan | Where-Object { $_ -match '^\s+sha256 engine=' } | Select-Object -Last 1) -replace '^\s+sha256 engine=', '').Trim()
$cat = ((($scan | Where-Object { $_ -match 'Network-Foundation.*\.cat' } | Select-Object -First 1) -replace '^.*->\s+', '') -replace '\s+@.*$', '').Trim()
P "engine sha1=$h1"
P "engine sha256=$h2"
P "cat=$cat"
$b1 = Hex2Bytes $h1
$b2 = Hex2Bytes $h2

$tcp = Join-Path $env:SystemRoot 'System32\drivers\tcpip.sys'
foreach ($v in 1..5) {
    P ("tcpip sha1  enumV$v -> " + [CE3]::EnumVar($b1, 'sha1', $v))
    P ("tcpip sha256 enumV$v -> " + [CE3]::EnumVar($b2, 'sha256', $v))
}
P ("tcpip WVT catalog(engineSha1)   -> 0x{0:X8}" -f [CE3]::WvtCatalog($cat, $tcp, $b1, 'sha1'))
P ("tcpip WVT catalog(engineSha256) -> 0x{0:X8}" -f [CE3]::WvtCatalog($cat, $tcp, $b2, 'sha256'))
P ("tcpip WVT file(embedded)        -> 0x{0:X8}" -f [CE3]::WvtFile($tcp))

foreach ($f in @((Join-Path $d '_p25h_S6lan.sys'), (Join-Path $env:SystemRoot 'System32\drivers\apexdrv.sys'))) {
    P ("--- " + $f)
    P ("  enumV1 sha1 -> " + [CE3]::EnumVar($b1, 'sha1', 1))
    P ("  WVT file(embedded) -> 0x{0:X8}" -f [CE3]::WvtFile($f))
    P ("  WVT catalog(MS cat, engineSha1) -> 0x{0:X8}" -f [CE3]::WvtCatalog($cat, $f, $b1, 'sha1'))
}
'probe2-complete' | Set-Content -Encoding utf8 (Join-Path $d 'probe2_complete.txt')
