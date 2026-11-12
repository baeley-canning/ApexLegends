# h313 PE - READ-ONLY diagnosis follow-up: on this boot NalDrv(prv0)/RTCore64(prv1)/ATSZIO(prv3)
# (kdu-extracted, SIGNED) fail to load with RAW NTSTATUS 0xC000009A - the exact status behind the
# SCM 1450 of zapexdrv - while Gdrv(prv2)/AsIO3(prv22)/DBUtilDrv2 load fine, seconds apart, with
# NO CodeIntegrity events. This script extracts every PE resource out of C:\Users\Public\p37\drv64.dll
# (LOAD_LIBRARY_AS_DATAFILE, no execution), identifies them against kdu_list.csv FileSHA1, parses
# the PE headers of failing-vs-loading images side by side, and adds Defender state (exclusions and
# recent detections, read-only). Writes only into temp\h313pe\ and _ritual\h313_pe.out.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h313_pe2.out'
$peDir = Join-Path (Split-Path -Parent $here) 'temp\h313pe'
function Say([string]$s) {
    $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s
    Write-Host $line
    Add-Content -LiteralPath $out -Value $line
}
if (Test-Path $out) { Remove-Item -LiteralPath $out -Force }
New-Item -ItemType Directory -Force -Path $peDir | Out-Null
Say ('===== h313 PE diff ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss') + ' =====')

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
public class KduRes {
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern IntPtr LoadLibraryExW(string f, IntPtr h, uint flags);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool EnumResourceTypesW(IntPtr h, EnumResTypeProc cb, IntPtr p);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool EnumResourceNamesW(IntPtr h, IntPtr type, EnumResNameProc cb, IntPtr p);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr FindResourceW(IntPtr h, IntPtr name, IntPtr type);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr LoadResource(IntPtr h, IntPtr r);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr LockResource(IntPtr r);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern uint SizeofResource(IntPtr h, IntPtr r);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool FreeLibrary(IntPtr h);
    public delegate bool EnumResTypeProc(IntPtr h, IntPtr type, IntPtr p);
    public delegate bool EnumResNameProc(IntPtr h, IntPtr type, IntPtr name, IntPtr p);
    public static List<string> Found = new List<string>();
    public static IntPtr HMod = IntPtr.Zero;
    public static bool OnName(IntPtr h, IntPtr type, IntPtr name, IntPtr p) {
        IntPtr r = FindResourceW(h, name, type);
        if (r != IntPtr.Zero) {
            uint sz = SizeofResource(h, r);
            IntPtr lr = LoadResource(h, r);
            if (lr != IntPtr.Zero) {
                byte[] buf = new byte[sz];
                Marshal.Copy(lr, buf, 0, (int)sz);
                if (buf.Length > 2 && buf[0] == 0x4D && buf[1] == 0x5A) {
                    string typeS = (type.ToInt64() >> 16) == 0 ? ("i" + type.ToInt64()) : Marshal.PtrToStringUni(type);
                    string nameS = (name.ToInt64() >> 16) == 0 ? ("i" + name.ToInt64()) : Marshal.PtrToStringUni(name);
                    string file = "res_" + typeS + "_" + nameS + ".sys";
                    System.IO.File.WriteAllBytes(Environment.GetEnvironmentVariable("H313PE_DIR") + "\\" + file, buf);
                    Found.Add(file + "\t" + sz);
                }
            }
        }
        return true;
    }
    public static bool OnType(IntPtr h, IntPtr type, IntPtr p) {
        EnumResourceNamesW(h, type, OnName, IntPtr.Zero);
        return true;
    }
    public static void ExtractAll(string dll, string dir) {
        Environment.SetEnvironmentVariable("H313PE_DIR", dir);
        HMod = LoadLibraryExW(dll, IntPtr.Zero, 0x2);
        if (HMod == IntPtr.Zero) throw new Exception("LoadLibraryExW failed " + Marshal.GetLastWin32Error());
        EnumResourceTypesW(HMod, OnType, IntPtr.Zero);
        FreeLibrary(HMod);
    }
}
"@
$env:H313PE_DIR = $peDir
Say ('drv64.dll sha256=' + (Get-FileHash 'C:\Users\Public\p37\drv64.dll' -Algorithm SHA256).Hash)
try {
    [KduRes]::ExtractAll('C:\Users\Public\p37\drv64.dll', $peDir)
} catch { Say ('EXTRACT FAIL: ' + $_.Exception.Message) }

function ParsePe([string]$path) {
    $b = [IO.File]::ReadAllBytes($path)
    $name = Split-Path $path -Leaf
    if ($b.Length -lt 0x40 -or $b[0] -ne 0x4D) { return @{ file = $name; err = 'no MZ' } }
    $pe = [BitConverter]::ToInt32($b, 0x3C)
    if ($pe -le 0 -or $pe + 200 -gt $b.Length) { return @{ file = $name; err = 'bad lfanew' } }
    $opt = $pe + 24
    $sizeOpt = [BitConverter]::ToUInt16($b, $pe + 20)
    $nsec = [BitConverter]::ToUInt16($b, $pe + 6)
    $r = [ordered]@{
        file = $name; size = $b.Length; machine = ('0x{0:X4}' -f [BitConverter]::ToUInt16($b, $pe + 4))
        nsec = $nsec; sizeOpt = $sizeOpt
        subsystem = [BitConverter]::ToUInt16($b, $opt + 68)
        dllchar = ('0x{0:X4}' -f [BitConverter]::ToUInt16($b, $opt + 70))
        checksum = ('0x{0:X8}' -f [BitConverter]::ToUInt32($b, $opt + 64))
        secalign = ('0x{0:X}' -f [BitConverter]::ToUInt32($b, $opt + 32))
        filealign = ('0x{0:X}' -f [BitConverter]::ToUInt32($b, $opt + 36))
        imgsize = ('0x{0:X}' -f [BitConverter]::ToUInt32($b, $opt + 56))
        imgbase = ('0x{0:X}' -f [BitConverter]::ToUInt64($b, $opt + 24))
        ep = ('0x{0:X}' -f [BitConverter]::ToUInt32($b, $opt + 16))
        nrva = [BitConverter]::ToUInt32($b, $opt + 108)
        sections = @(); dirs = @()
    }
    $secTab = $pe + 24 + $sizeOpt
    for ($i = 0; $i -lt $nsec; ++$i) {
        $s = $secTab + 40 * $i
        if ($s + 40 -gt $b.Length) { break }
        $r.sections += ('{0}[v{1:X} a{2:X} r{3:X} f{4:X4}]' -f `
            ([Text.Encoding]::ASCII.GetString($b, $s, 8).Trim([char]0)), `
            [BitConverter]::ToUInt32($b, $s + 8), [BitConverter]::ToUInt32($b, $s + 12), `
            [BitConverter]::ToUInt32($b, $s + 16), [BitConverter]::ToUInt32($b, $s + 36))
    }
    $dirNames = 'exp','imp','rsrc','exc','SEC','rel','dbg','arch','gp','tls','lc','bound','iat','dly'
    for ($i = 0; $i -lt 14; ++$i) {
        $d = $opt + 112 + 8 * $i
        $rva = [BitConverter]::ToUInt32($b, $d); $sz = [BitConverter]::ToUInt32($b, $d + 4)
        if ($rva -ne 0 -or $sz -ne 0) { $r.dirs += ($dirNames[$i] + '=0x' + $rva.ToString('X') + '/0x' + $sz.ToString('X')) }
    }
    return $r
}
# name the extracted resources against kdu_list.csv (FileSHA1 column 13)
$shaMap = @{}
foreach ($row in (Get-Content 'C:\Users\Public\p37\kdu_list.csv' -EA 0 | Select-Object -Skip 1)) {
    $c = $row -split '","'
    if ($c.Count -ge 13) {
        $nm = ($c[2] -replace '"', ''); $sha = ($c[12] -replace '"', '')
        $shaMap[$sha] = $nm + '(prv' + ($c[0] -replace '"', '') + ')'
    }
}
$targets = @(Get-ChildItem $peDir -Filter '*.sys' | ForEach-Object { $_.FullName })
$targets += 'C:\Users\Public\p37\zapexdrv.sys'
$targets += 'C:\p37vm\payload\DBUtilDrv2.sys'
Say '--- PE facts (failing: NalDrv/RTCore64/ATSZIO/zapexdrv vs loading: Gdrv/AsIO3/DBUtilDrv2) ---'
foreach ($t in $targets) {
    $p = ParsePe $t
    $sha1 = [BitConverter]::ToString([Security.Cryptography.SHA1]::Create().ComputeHash([IO.File]::ReadAllBytes($t))).Replace('-', '')
    $id = if ($shaMap.ContainsKey($sha1)) { $shaMap[$sha1] } else { 'NOT-IN-CSV' }
    Say ('  ' + $p.file + ' <- ' + $id + ' sha1=' + $sha1.Substring(0, 12))
    if ($p.err) { Say ('    err=' + $p.err); continue }
    Say ('    machine=' + $p.machine + ' nsec=' + $p.nsec + ' subsys=' + $p.subsystem + ' dllchar=' + $p.dllchar + ' cksum=' + $p.checksum + ' ep=' + $p.ep + ' base=' + $p.imgbase)
    Say ('    secalign=' + $p.secalign + ' filealign=' + $p.filealign + ' imgsize=' + $p.imgsize + ' nrva=' + $p.nrva + ' sizeOpt=' + $p.sizeOpt)
    Say ('    sections: ' + ($p.sections -join ' '))
    Say ('    dirs: ' + ($p.dirs -join ' '))
}
Say '--- Defender state (read-only) ---'
try { $mp = Get-MpPreference -EA Stop; Say ('  ExclusionPath: ' + (@($mp.ExclusionPath) -join ' | ')) } catch { Say ('  Get-MpPreference failed: ' + $_.Exception.Message) }
try { $st = Get-MpComputerStatus -EA Stop; Say ('  RealTime=' + $st.RealTimeProtectionEnabled + ' Amsvc=' + $st.AMServiceEnabled + ' Behavior=' + $st.BehaviorMonitorEnabled) } catch { Say ('  Get-MpComputerStatus failed: ' + $_.Exception.Message) }
try { $det = @(Get-MpThreatDetection -EA Stop | Sort-Object InitialDetectionTime -Descending | Select-Object -First 5) ; if ($det.Count) { foreach ($d in $det) { Say ('  detect ' + $d.InitialDetectionTime.ToString('dd/MM HH:mm') + ' ' + $d.ProcessName + ' ' + $d.Resources) } } else { Say '  no MpThreatDetection rows' } } catch { Say ('  Get-MpThreatDetection failed: ' + $_.Exception.Message) }
Say 'RESULT: PE diff written - compare dllchar/checksum/sections/dirs rows of FAIL vs LOAD sets above'
Say 'VERDICT: PE-DIFF - whatever column splits {NalDrv,RTCore64,ATSZIO,zapexdrv} from {Gdrv,AsIO3,DBUtilDrv2} is the 0xC000009A discriminator; report to lead, no fix attempted'
