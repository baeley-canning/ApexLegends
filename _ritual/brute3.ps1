# brute3.ps1 - find what CryptCATAdminCalcHashFromFileHandle2 actually hashes.
# Decisive experiments on a tiny self-signed file (_p25h_S6lan.sys) plus structural
# hypotheses (section-order / gap / tail / compact). Read-only; temp copies in $env:TEMP.
$dir = $PSScriptRoot
$f   = Join-Path $dir '_p25h_S6lan.sys'
$out = Join-Path $dir 'brute3.txt'
$tgt = '37647B4654AE7F7608D8012A4BAA5AA8FB843552F6F053C2549ECE167D4C6EE8'  # api sha256 of $f
"brute3 $(Get-Date -Format s)  target(api sha256 of S6lan)=$tgt" | Set-Content -Encoding utf8 $out

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
public static class B3 {
    [DllImport("wintrust.dll", SetLastError=true)] static extern bool CryptCATAdminAcquireContext2(out IntPtr h, ref Guid g, string alg, IntPtr pol, int f);
    [DllImport("wintrust.dll", SetLastError=true)] static extern bool CryptCATAdminCalcHashFromFileHandle2(IntPtr h, IntPtr hf, ref int pcb, byte[] pb, int f);
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr CreateFileW(string p, uint acc, uint sh, IntPtr sa, uint cd, uint fl, IntPtr t);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
    static Guid G = new Guid("F750E6C3-38EE-11D1-85E5-00C04FC295EE");
    public static string Hx(byte[] d, bool sha1) {
        byte[] h = sha1 ? SHA1.Create().ComputeHash(d) : SHA256.Create().ComputeHash(d);
        return BitConverter.ToString(h).Replace("-","");
    }
    public static string Api(string path) {
        IntPtr h; if (!CryptCATAdminAcquireContext2(out h, ref G, "SHA256", IntPtr.Zero, 0))
            return "CTXFAIL" + Marshal.GetLastWin32Error();
        var sb = new StringBuilder();
        using (var fs = File.OpenRead(path)) {
            byte[] buf = new byte[64]; int need = 0;
            if (!CryptCATAdminCalcHashFromFileHandle2(h, fs.SafeFileHandle.DangerousGetHandle(), ref need, buf, 0))
                return "ERR" + Marshal.GetLastWin32Error();
            sb.Append(BitConverter.ToString(buf, 0, need).Replace("-",""));
        }
        return sb.ToString();
    }
    public static byte[] Slice(byte[] r, int off, int n) {
        if (off < 0) off = 0; if (n > r.Length - off) n = r.Length - off;
        byte[] b = new byte[n]; Array.Copy(r, off, b, 0, n); return b;
    }
    // sections: returns lines + fills list of (name, prd, srsd, vsize, va) in table order
    public static string Sections(byte[] raw, List<string> table) {
        int lf = BitConverter.ToInt32(raw, 0x3C);
        int nsec = BitConverter.ToUInt16(raw, lf + 6);
        int soh  = BitConverter.ToUInt16(raw, lf + 20);
        int opt  = lf + 24;
        int st   = opt + soh;
        var sb = new StringBuilder();
        sb.AppendLine("  lf=" + lf + " nsec=" + nsec + " sizeOfOptionalHeader=" + soh + " sizeOfHeaders=" + BitConverter.ToUInt32(raw, opt + 0x3C));
        for (int i = 0; i < nsec; i++) {
            int o = st + i * 40;
            string nm = Encoding.ASCII.GetString(raw, o, 8).TrimEnd('\0');
            uint vsize = BitConverter.ToUInt32(raw, o + 8);
            uint va    = BitConverter.ToUInt32(raw, o + 12);
            uint srsd  = BitConverter.ToUInt32(raw, o + 16);
            uint prd   = BitConverter.ToUInt32(raw, o + 20);
            table.Add(nm + "|" + prd + "|" + srsd);
            sb.AppendLine("  sec[" + i + "] " + nm.PadRight(9) + " vsize=0x" + vsize.ToString("X") + " va=0x" + va.ToString("X") + " srsd=0x" + srsd.ToString("X") + " prd=0x" + prd.ToString("X"));
        }
        return sb.ToString();
    }
}
'@

$raw = [IO.File]::ReadAllBytes($f)
$sec = New-Object 'System.Collections.Generic.List[string]'
$struct = [B3]::Sections($raw, $sec)
Add-Content -Encoding utf8 $out '=== structure of S6lan'; Add-Content -Encoding utf8 $out $struct
Add-Content -Encoding utf8 $out ("  certSecEntry bytes = " + (($raw[384..391] | ForEach-Object { $_.ToString('X2') }) -join ' '))

# --- trusted cross-checks ---
Add-Content -Encoding utf8 $out '=== trusted plain-hash cross-checks'
Add-Content -Encoding utf8 $out ("  plain sha256(full)   = " + [B3]::Hx($raw, $false))
Add-Content -Encoding utf8 $out ("  plain sha1(full)     = " + [B3]::Hx($raw, $true))
Add-Content -Encoding utf8 $out ("  api  sha256(full)    = " + [B3]::Api($f))

$tmp = Join-Path $env:TEMP ('b3_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$cp = 8704; $cl = 1680
[IO.File]::WriteAllBytes("$tmp\prefix.bin", [B3]::Slice($raw, 0, $cp))
[IO.File]::WriteAllBytes("$tmp\suffix.bin", [B3]::Slice($raw, $cp, $cl))
$cm = [byte[]]$raw.Clone(); for ($i = 9000; $i -lt 9016; $i++) { $cm[$i] = 0 }
[IO.File]::WriteAllBytes("$tmp\certmod.bin", $cm)
$hm = [byte[]]$raw.Clone(); for ($i = 400; $i -lt 500; $i++) { $hm[$i] = 0xAA }
[IO.File]::WriteAllBytes("$tmp\headmod.bin", $hm)
Add-Content -Encoding utf8 $out '=== experiment: api vs plain on derived files'
foreach ($n in 'prefix.bin', 'suffix.bin', 'certmod.bin', 'headmod.bin') {
    Add-Content -Encoding utf8 $out ("  {0,-13} api={1} plain={2}" -f $n, [B3]::Api("$tmp\$n"), [B3]::Hx([IO.File]::ReadAllBytes("$tmp\$n"), $false))
}
Add-Content -Encoding utf8 $out 'DONE-part1'
'part1 done'
