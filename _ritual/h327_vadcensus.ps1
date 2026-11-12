# h327 - address-space census of the live game, by VirtualQueryEx only (read-only).
# Variable: "what the address space looks like to a handle we provably own" - i.e. is the
#   space we are querying the one the game is running in (7.7 GB resident), or a small
#   shadow space presented to us (Javelin CR3 abuse, KB [B4])?
# Control: the same census on THIS process, before the target, so a broken instrument
#   shows up as a broken control instead of a verdict about the game.
# Mutates nothing: OpenProcess + VirtualQueryEx + NtQueryInformationProcess + one RPM.
param([int] $GamePid = 0, [switch] $Elevate)
$outF = 'C:\h320x\h327.out'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and $Elevate) {
    $extra = ' -Elevate'
    if ($GamePid -gt 0) { $extra += " -GamePid $GamePid" }
    Start-Process powershell -Verb RunAs -Wait -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"{1}' -f $PSCommandPath, $extra)
    if (Test-Path -LiteralPath $outF) { Get-Content -LiteralPath $outF }
    exit 0
}
Remove-Item -LiteralPath $outF -Force -ErrorAction SilentlyContinue
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class A27 {
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr OpenProcess(uint a, bool i, int pid);
    [DllImport("kernel32", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32", SetLastError=true)] public static extern bool ReadProcessMemory(IntPtr hp, IntPtr addr, byte[] b, IntPtr n, out IntPtr done);
    [StructLayout(LayoutKind.Sequential)] public struct MBI {
        public IntPtr BaseAddress, AllocationBase; public uint AllocationProtect, a1;
        public IntPtr RegionSize; public uint State, Protect, Type, a2;
    }
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr VirtualQueryEx(IntPtr hp, IntPtr addr, out MBI m, IntPtr len);
    [StructLayout(LayoutKind.Sequential)] public struct PBI {
        public IntPtr ExitStatus, PebBaseAddress, AffinityMask, BasePriority, UniqueProcessId, InheritedFromUniqueProcessId;
    }
    [DllImport("ntdll")] public static extern int NtQueryInformationProcess(IntPtr h, int cls, out PBI pbi, int len, out int ret);

    const uint MEM_COMMIT = 0x1000, MEM_RESERVE = 0x2000;
    const uint MEM_IMAGE = 0x1000000, MEM_MAPPED = 0x40000;

    // One region, or 0 when the query refused.
    public static long Region(IntPtr h, long addr, out MBI m) {
        IntPtr r = VirtualQueryEx(h, (IntPtr)addr, out m, (IntPtr)48);
        if (r == IntPtr.Zero) return 0;
        return m.RegionSize.ToInt64();
    }

    // Walk the whole user range. Returns the report as lines so PowerShell only prints.
    public static string[] Census(IntPtr h, long wsBytes, string tag, int maxRegions, int maxMs) {
        var L = new List<string>();
        long addr = 0; int regions = 0, images = 0, shown = 0;
        long commit = 0, imageB = 0, privB = 0, mapB = 0, reserveB = 0, freeB = 0, firstImage = 0;
        uint firstImageProt = 0;
        var topBase = new long[5]; var topSize = new long[5];
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (addr < 0x7FFFFFFF0000L && regions < maxRegions && sw.ElapsedMilliseconds < maxMs) {
            MBI m; long size;
            try { size = Region(h, addr, out m); } catch { break; }
            if (size <= 0) break;
            regions++;
            if (m.State == MEM_COMMIT) {
                commit += size;
                if (m.Type == MEM_IMAGE) {
                    images++; imageB += size;
                    if (images == 1) { firstImage = addr; firstImageProt = m.Protect; }
                    if (shown < 6) {
                        L.Add(String.Format("    image  0x{0:X}-0x{1:X}  size=0x{2:X}  prot=0x{3:X}", addr, addr + size, size, m.Protect));
                        shown++;
                    }
                } else if (m.Type == MEM_MAPPED) mapB += size;
                else privB += size;
            } else if (m.State == MEM_RESERVE) reserveB += size;
            else freeB += size;
            for (int i = 0; i < 5; i++) {
                if (size > topSize[i]) {
                    for (int j = 4; j > i; j--) { topSize[j] = topSize[j-1]; topBase[j] = topBase[j-1]; }
                    topSize[i] = size; topBase[i] = addr; break;
                }
            }
            long next = addr + size;
            if (next <= addr) break;
            addr = next;
        }
        sw.Stop();
        double ratio = wsBytes > 0 ? (double)commit / (double)wsBytes : 0.0;
        L.Add(String.Format("  {0}: regions={1} commit={2}MB image={3}MB({4} img) private={5}MB mapped={6}MB reserve={7}MB free={8}MB",
            tag, regions, commit >> 20, imageB >> 20, images, privB >> 20, mapB >> 20, reserveB >> 20, freeB >> 20));
        L.Add(String.Format("  {0}: ws={1}MB commit/ws={2:F2} firstImage=0x{3:X} prot=0x{4:X} walk={5}ms stoppedAt=0x{6:X}",
            tag, wsBytes >> 20, ratio, firstImage, firstImageProt, sw.ElapsedMilliseconds, addr));
        for (int i = 0; i < 5; i++) {
            if (topSize[i] >= (1L << 20)) L.Add(String.Format("    big    0x{0:X}  size=0x{1:X} ({2}MB)", topBase[i], topSize[i], topSize[i] >> 20));
        }
        return L.ToArray();
    }
}
'@
function W([string] $s) { Add-Content -LiteralPath $outF -Value $s -Encoding utf8 }
W ('h327 - address-space census via VirtualQueryEx - ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
W ('elevated: ' + $isAdmin)

# ---- control: this process, same code path, same binary -----------------------
$me = Get-Process -Id $PID
$hSelf = [A27]::OpenProcess(0x1F0FFF, $false, $PID)
if ($hSelf -eq [IntPtr]::Zero) {
    W ('self     : OpenProcess err=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
} else {
    [A27]::Census($hSelf, $me.WorkingSet64, 'self', 400000, 20000) | ForEach-Object { W $_ }
    [void][A27]::CloseHandle($hSelf)
}

# ---- target ------------------------------------------------------------------
$pid0 = $GamePid
if ($pid0 -le 0) {
    $g = Get-Process -Name 'r5apex_dx12','baeleys*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($g) { $pid0 = $g.Id }
}
if ($pid0 -le 0) { W 'game     : no game process - nothing to measure'; W 'RESULT: FAIL no-game'; W 'h327 DONE'; Get-Content -LiteralPath $outF; return }
$gp = Get-Process -Id $pid0 -ErrorAction SilentlyContinue
if (-not $gp) { W ('game     : pid=' + $pid0 + ' not found'); W 'RESULT: FAIL no-game'; W 'h327 DONE'; Get-Content -LiteralPath $outF; return }
W ('game     : pid=' + $pid0 + ' ws=' + [int]($gp.WorkingSet64/1MB) + 'MB threads=' + $gp.Threads.Count)
$h = [A27]::OpenProcess(0x1F0FFF, $false, $pid0)
if ($h -eq [IntPtr]::Zero) {
    W ('game     : OpenProcess(ALL) err=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
    W 'RESULT: FAIL open'; W 'h327 DONE'; Get-Content -LiteralPath $outF; return
}
W ('handle   : 0x{0:X}' -f $h.ToInt64())
[A27]::Census($h, $gp.WorkingSet64, 'game', 400000, 25000) | ForEach-Object { W $_ }

# ---- named addresses: the recorded "PEB", h326's page, the image base ---------
$pbi = New-Object A27+PBI
$ret = 0
$st = [A27]::NtQueryInformationProcess($h, 0, [ref] $pbi, 48, [ref] $ret)
$peb = $pbi.PebBaseAddress.ToInt64()
W ('peb      : status=0x{0:X8} peb=0x{1:X}' -f $st, $peb)
foreach ($a in @($peb, 0x223000, 0x10100, 0x140000000)) {
    $m = New-Object A27+MBI
    $sz = [A27]::Region($h, [int64] $a, [ref] $m)
    if ($sz -gt 0) {
        W ('  at 0x{0:X}: vqe=ok base=0x{1:X} size=0x{2:X} state=0x{3:X} prot=0x{4:X} type=0x{5:X}' -f $a, $m.BaseAddress.ToInt64(), $sz, $m.State, $m.Protect, $m.Type)
    } else {
        W ('  at 0x{0:X}: vqe=FAIL err={1}' -f $a, [Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
}
$buf = New-Object byte[] 8
$got = [IntPtr]::Zero
$okRead = [A27]::ReadProcessMemory($h, [IntPtr] $peb, $buf, [IntPtr] 8, [ref] $got)
W ('  rpm at peb: ok={0} err={1} bytes={2}' -f $okRead, [Runtime.InteropServices.Marshal]::GetLastWin32Error(), $got)
[void][A27]::CloseHandle($h)

$alive = [bool](Get-Process -Id $pid0 -ErrorAction SilentlyContinue)
W ('after    : alive=' + $alive)
if ($alive) { W 'RESULT: census complete, game untouched' } else { W 'RESULT: game DIED during the census' }
W 'h327 DONE'
Get-Content -LiteralPath $outF
