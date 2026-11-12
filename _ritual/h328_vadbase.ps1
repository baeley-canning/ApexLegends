# h328_vadbase.ps1 -- VAD module-base resolver (image sections + MEMORY_SECTION_NAME) + driver ABI
# self-validation against ground truth, read-only against the game. Runs host or guest, NON-elevated,
# with or without the driver loaded. Output: h328_vadbase.out next to the script. One variable:
# the resolver path itself. Modeled on h327_vadcensus.ps1 (same census mechanism, proven on the game).
#
# P1 - resolver: walk own VAD via NtQueryVirtualMemory(MemoryBasicInformation), take committed
#      MEM_IMAGE regions, resolve each with MemoryMappedFilenameInformation, match ntdll.dll /
#      kernel32.dll / the host .exe against [Diagnostics.Process] ground truth (the module list is
#      only readable in our own process - that is why the probe validates itself first). MZ check
#      every resolved base. This is the thing, not the driver, that supplies "where is the exe".
# P2 - driver vs ground truth, on our own pid: VERSION==14, BASE(pid)==ground-truth main base,
#      Read8/ReadBuf byte-for-byte against a user-mode read of the same addresses, 1-byte Write
#      round-trip on a private heap buffer (restored). No self-referential claims anywhere.
# P3 - game (read-only, no write): resolver exe base vs driver BASE cross-check, MZ + PE chain at
#      the base via the driver, one driver read of the game PEB. This is "line A" from user mode.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h328_vadbase.out'
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $out -Value ($L -join "`r`n") }
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text; using System.Collections.Generic;
public static class Dev {
  [DllImport("kernel32", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr CreateFileW(string p, uint a, uint s, IntPtr sa, uint d, uint fl, IntPtr t);
  [DllImport("kernel32", SetLastError=true)]
  public static extern bool DeviceIoControl(IntPtr h, uint c, byte[] i, uint il, byte[] o, uint ol, out uint r, IntPtr ov);
  [DllImport("kernel32")] public static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32", SetLastError=true)] public static extern IntPtr OpenProcess(uint a, bool inh, int pid);
}
public static class Vd {
  [DllImport("ntdll")] static extern int NtQueryVirtualMemory(IntPtr h, IntPtr b, int cls, byte[] buf, IntPtr len, out IntPtr ret);
  [DllImport("ntdll")] static extern int NtQueryInformationProcess(IntPtr h, int cls, byte[] buf, int len, out int ret);
  public static string[] Census(IntPtr h, bool named) {
    var res = new List<string>();
    long a = 0x10000, max = 0x7FFFFFFF0000L; int guard = 0; int fails = 0;
    var mbi = new byte[48]; IntPtr ret;
    while (a < max && guard++ < 4000000) {
      if (NtQueryVirtualMemory(h, (IntPtr)a, 0, mbi, (IntPtr)48, out ret) != 0) { if (++fails > 64) break; a += 0x1000; continue; }
      fails = 0;
      long b = BitConverter.ToInt64(mbi, 0); long sz = BitConverter.ToInt64(mbi, 24);
      uint state = BitConverter.ToUInt32(mbi, 32); uint type = BitConverter.ToUInt32(mbi, 40);
      if (sz <= 0) break;
      if (state == 0x1000 && type == 0x1000000) {
        string nm = "";
        if (named) {
          var nb = new byte[1104]; IntPtr r2;
          if (NtQueryVirtualMemory(h, (IntPtr)b, 2, nb, (IntPtr)nb.Length, out r2) == 0) {
            int ul = BitConverter.ToUInt16(nb, 0);
            if (ul > 2 && ul <= 1040) nm = Encoding.Unicode.GetString(nb, 16, ul).TrimEnd('\0');
          }
        }
        res.Add(b.ToString("X") + "|" + sz.ToString("X") + "|" + nm);
        a = b + sz;
      } else { a = b + sz; }
    }
    return res.ToArray();
  }
  public static long PebOf(IntPtr h) {
    var pbi = new byte[48]; int rr;
    if (NtQueryInformationProcess(h, 0, pbi, 48, out rr) != 0) return 0;
    return BitConverter.ToInt64(pbi, 8);
  }
}
'@
$IO_VER    = [uint32](0x8A702004L)
$IO_READ8  = [uint32](0x8A702010L)
$IO_READBUF= [uint32](0x8A702014L)
$IO_WRITE  = [uint32](0x8A702018L)
$IO_BASE   = [uint32](0x8A70201CL)
function OpenDev {
    $h = [Dev]::CreateFileW('\\.\ApexDrv', [uint32](0xC0000000L), 0, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if ($h -eq [IntPtr](-1)) { return [IntPtr]::Zero }
    return $h
}
function Put32([byte[]]$b, [int]$o, [uint32]$v) { [BitConverter]::GetBytes($v).CopyTo($b, $o) }
function Put64([byte[]]$b, [int]$o, [uint64]$v) { [BitConverter]::GetBytes($v).CopyTo($b, $o) }
function Io([IntPtr]$h, [uint32]$c, [byte[]]$b) {
    [uint32]$r = 0
    return [Dev]::DeviceIoControl($h, $c, $b, [uint32]$b.Length, $b, [uint32]$b.Length, [ref]$r, [IntPtr]::Zero)
}
function BytesOf([long]$a, [int]$n) { $bb = New-Object byte[] $n; [Runtime.InteropServices.Marshal]::Copy([IntPtr]$a, $bb, 0, $n); return $bb }
function Same([byte[]]$a, [byte[]]$b, [int]$n) { for ($i = 0; $i -lt $n; $i++) { if ($a[$i] -ne $b[$i]) { return $false } }; return $true }
Lg '===== h328 vadbase (resolver + driver self/game crosscheck, read-only) ====='
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Lg ('host=' + $env:COMPUTERNAME + ' ps=' + $PSVersionTable.PSVersion.ToString() + ' elevated=' + $adm + ' pid=' + $PID)
$me = [System.Diagnostics.Process]::GetCurrentProcess()
$truth = @{}
$truth['main'] = $me.MainModule.BaseAddress.ToInt64()
$truth['mainName'] = $me.MainModule.ModuleName
foreach ($m in $me.Modules) { if ($m.ModuleName -ieq 'ntdll.dll' -or $m.ModuleName -ieq 'kernel32.dll') { $truth[$m.ModuleName.ToLower()] = $m.BaseAddress.ToInt64() } }
$targets = @(
    @{ n = $truth['mainName'].ToLower(); a = $truth['main'] },
    @{ n = 'ntdll.dll';    a = $truth['ntdll.dll'] },
    @{ n = 'kernel32.dll'; a = $truth['kernel32.dll'] }
)
Lg ('ground truth (own modules): ' + (($targets | ForEach-Object { $_.n + '=0x' + $_.a.ToString('X') }) -join ' '))

# ---- P1: resolver on own process vs ground truth (the probe's own gate) ---------------------
$lines = [Vd]::Census([IntPtr](-1), $true)
$found = @{}
$imgCount = 0
foreach ($ln in $lines) {
    $p = $ln -split '\|'
    if ($p.Count -lt 3) { continue }
    $imgCount++
    $leaf = [System.IO.Path]::GetFileName($p[2])
    if ($leaf -and -not $found.ContainsKey($leaf.ToLower())) { $found[$leaf.ToLower()] = [Convert]::ToInt64($p[0], 16) }
}
Lg ('P1 census: ' + $imgCount + ' image regions walked, ' + $found.Count + ' distinct names resolved')
$p1ok = $true; $mzok = $true
foreach ($t in $targets) {
    $f = if ($found.ContainsKey($t.n)) { $found[$t.n] } else { -1 }
    $hit = ($f -eq $t.a)
    if (-not $hit) { $p1ok = $false }
    $mz = $false
    if ($f -gt 0) { try { $b2 = BytesOf $f 2; $mz = ($b2[0] -eq 0x4D -and $b2[1] -eq 0x5A) } catch { $mz = $false }; if (-not $mz) { $mzok = $false } }
    Lg ('P1 ' + $t.n + ': resolver=' + $(if ($f -gt 0) { '0x' + $f.ToString('X') } else { 'NOT-FOUND' }) + ' truth=0x' + $t.a.ToString('X') + ' match=' + $hit + ' MZ=' + $mz)
}
Lg ('RESULT: P1 resolver-vs-groundtruth ' + $(if ($p1ok -and $mzok) { 'PASS' } else { 'FAIL' }) + ' (' + $imgCount + ' image regions, ' + $found.Count + ' names)')
$ex = 0
if (-not ($p1ok -and $mzok)) { $ex++ }

# ---- P2: driver vs ground truth on our own pid ----------------------------------------------
$ver = -1
$hdev = OpenDev
$p2 = 'SKIPPED (no driver handle - service not started)'
if ($hdev -ne [IntPtr]::Zero) {
    try {
        $v = New-Object byte[] 8
        if (-not (Io $hdev $IO_VER $v)) { $p2 = 'SKIPPED (VERSION ioctl err=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error() + ')' }
        else {
            $ver = [int][BitConverter]::ToUInt32($v, 0)
            Lg ('P2 driver version=' + $ver)
            if ($ver -ne 14) { $p2 = 'FAIL (ABI ' + $ver + ', expected 14)'; $ex++ }
            else {
                $q = New-Object byte[] 24; Put32 $q 0 ([uint32]$me.Id)
                $okB = Io $hdev $IO_BASE $q
                $stB = [int][BitConverter]::ToInt32($q, 8); $src = [int][BitConverter]::ToInt32($q, 12); $base = [BitConverter]::ToUInt64($q, 16)
                Lg ('P2 BASE rc=' + $okB + ' status=0x' + $stB.ToString('X8') + ' source=' + $src + ' base=0x' + $base.ToString('X'))
                $okBase = ($stB -eq 0 -and $base -eq [uint64]$truth['main'] -and ($src -eq 1 -or $src -eq 2))
                $addrs = @([uint64]$truth['main'], [uint64]($truth['main'] + 0x3C), [uint64]$truth['ntdll.dll'])
                $r8 = New-Object byte[] 1288; Put32 $r8 0 ([uint32]$me.Id); Put32 $r8 4 3
                for ($i = 0; $i -lt 3; $i++) { Put64 $r8 (8 + $i * 8) $addrs[$i] }
                $ok8 = Io $hdev $IO_READ8 $r8
                $ok8v = $true
                for ($i = 0; $i -lt 3; $i++) {
                    $st = [int][BitConverter]::ToInt32($r8, 520 + $i * 4)
                    $gv = [BitConverter]::ToUInt64((BytesOf $addrs[$i] 8), 0)
                    $val = if ($st -eq 0) { [BitConverter]::ToUInt64($r8, 776 + $i * 8) } else { 0 }
                    $hit = ($st -eq 0 -and $val -eq $gv)
                    if (-not $hit) { $ok8v = $false }
                    Lg ('P2 READ8[' + $i + '] addr=0x' + $addrs[$i].ToString('X') + ' status=0x' + $st.ToString('X8') + ' val=0x' + $val.ToString('X16') + ' truth=0x' + $gv.ToString('X16') + ' match=' + $hit)
                }
                $rb = New-Object byte[] 4116; Put32 $rb 0 ([uint32]$me.Id); Put32 $rb 4 64; Put64 $rb 8 ([uint64]$truth['main'])
                $okR = Io $hdev $IO_READBUF $rb
                $stR = [int][BitConverter]::ToInt32($rb, 16)
                $drvBytes = New-Object byte[] 64; [Array]::Copy($rb, 20, $drvBytes, 0, 64)
                $own = BytesOf $truth['main'] 64
                $sameR = ($stR -eq 0 -and (Same $drvBytes $own 64))
                Lg ('P2 READBUF[64@main] rc=' + $okR + ' status=0x' + $stR.ToString('X8') + ' bytesEqual=' + (Same $drvBytes $own 64) + ' first4=' + ('{0:X2}{1:X2}{2:X2}{3:X2}' -f $drvBytes[0], $drvBytes[1], $drvBytes[2], $drvBytes[3]))
                $hb = [Runtime.InteropServices.Marshal]::AllocHGlobal(64)
                try {
                    for ($i = 0; $i -lt 64; $i++) { [Runtime.InteropServices.Marshal]::WriteByte($hb, $i, [byte]0x41) }
                    $orig = [Runtime.InteropServices.Marshal]::ReadByte($hb, 8)
                    $wr = New-Object byte[] 4116; Put32 $wr 0 ([uint32]$me.Id); Put32 $wr 4 1; Put64 $wr 8 ([uint64]($hb.ToInt64() + 8)); $wr[20] = [byte]($orig -bxor 0x5C)
                    $okW = Io $hdev $IO_WRITE $wr
                    $stW = [int][BitConverter]::ToInt32($wr, 16)
                    $after = [Runtime.InteropServices.Marshal]::ReadByte($hb, 8)
                    $wHit = ($stW -eq 0 -and $after -eq ($orig -bxor 0x5C))
                    $wr[20] = [byte]$orig
                    $okW2 = Io $hdev $IO_WRITE $wr
                    $stW2 = [int][BitConverter]::ToInt32($wr, 16)
                    $wHit2 = ($stW2 -eq 0 -and [Runtime.InteropServices.Marshal]::ReadByte($hb, 8) -eq $orig)
                    Lg ('P2 WRITE heap rc=' + $okW + '/' + $okW2 + ' status=0x' + $stW.ToString('X8') + '/0x' + $stW2.ToString('X8') + ' xorRoundtrip=' + $wHit + ' restored=' + $wHit2 + ' at=0x' + $hb.ToInt64().ToString('X'))
                    if ($okBase -and $ok8v -and $sameR -and $wHit -and $wHit2) { $p2 = 'PASS (BASE/Read8/ReadBuf/Write all == ground truth on own pid)' }
                    else { $p2 = 'FAIL (base=' + $okBase + ' read8=' + $ok8v + ' readbuf=' + $sameR + ' write=' + ($wHit -and $wHit2) + ')'; $ex++ }
                } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($hb) }
            }
        }
    } catch { $p2 = 'FAIL (exception: ' + $_.Exception.Message + ')'; $ex++ }
}
Lg ('RESULT: P2 driver-self ' + $p2)

# ---- P3: game crosscheck, read-only ----------------------------------------------------------
$p3 = 'SKIPPED (game not running)'
$g = @(Get-Process r5apex_dx12 -EA 0)
if ($g.Count -gt 0 -and $hdev -ne [IntPtr]::Zero -and $ver -eq 14) {
    $gp = $g[0].Id
    $gh = [Dev]::OpenProcess([uint32]0x1F0FFF, $false, $gp)
    if ($gh -eq [IntPtr]::Zero) { $p3 = 'FAIL (OpenProcess err=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error() + ')'; $ex++ }
    else {
        try {
            $gl = [Vd]::Census($gh, $true)
            $gbase = 0L; $gsrc = 'section-name'; $minb = [long]0x7FFFFFFFFFFFFFFF
            foreach ($ln in $gl) { $p = $ln -split '\|'; $leaf = [System.IO.Path]::GetFileName($p[2]); if ($leaf -match '^r5apex') { $b = [Convert]::ToInt64($p[0], 16); if ($b -lt $minb) { $minb = $b; $gbase = $b } } }
            if ($gbase -eq 0) { $gsrc = 'heuristic-lowest-image'; foreach ($ln in $gl) { $b = [Convert]::ToInt64(($ln -split '\|')[0], 16); if ($b -lt $minb) { $minb = $b; $gbase = $b } } }
            Lg ('P3 game pid=' + $gp + ' imageRegions=' + $gl.Count + ' exeBase=0x' + $gbase.ToString('X') + ' via=' + $gsrc)
            $q = New-Object byte[] 24; Put32 $q 0 ([uint32]$gp)
            $okB = Io $hdev $IO_BASE $q
            $stB = [int][BitConverter]::ToInt32($q, 8); $sr = [int][BitConverter]::ToInt32($q, 12); $bb = [BitConverter]::ToUInt64($q, 16)
            $cross = ($stB -eq 0 -and $bb -eq [uint64]$gbase)
            Lg ('P3 driver BASE rc=' + $okB + ' status=0x' + $stB.ToString('X8') + ' source=' + $sr + ' base=0x' + $bb.ToString('X') + ' crossAgreesWithResolver=' + $cross)
            $r8 = New-Object byte[] 1288; Put32 $r8 0 ([uint32]$gp); Put32 $r8 4 2
            Put64 $r8 8 ([uint64]$gbase); Put64 $r8 16 ([uint64]($gbase + 0x3C))
            $ok8 = Io $hdev $IO_READ8 $r8
            $st0 = [int][BitConverter]::ToInt32($r8, 520); $st1 = [int][BitConverter]::ToInt32($r8, 524)
            $mz = if ($st0 -eq 0) { [BitConverter]::ToUInt64($r8, 776) } else { 0 }
            $elf = if ($st1 -eq 0) { [BitConverter]::ToUInt64($r8, 784) } else { 0 }
            $mzok2 = ($st0 -eq 0 -and ($mz -band 0xFFFF) -eq 0x5A4D)
            $peb = [Vd]::PebOf($gh)
            $pb = New-Object byte[] 4116; Put32 $pb 0 ([uint32]$gp); Put32 $pb 4 16
            if ($peb -gt 0) { Put64 $pb 8 ([uint64]$peb) }
            $okP = Io $hdev $IO_READBUF $pb; $stP = [int][BitConverter]::ToInt32($pb, 16)
            $pe = New-Object byte[] 4116; Put32 $pe 0 ([uint32]$gp); Put32 $pe 4 4; Put64 $pe 8 ([uint64]([long]$gbase + [long]$elf))
            $okPe = Io $hdev $IO_READBUF $pe; $stPe = [int][BitConverter]::ToInt32($pe, 16)
            $pesig = ($stPe -eq 0 -and $pe[20] -eq 0x50 -and $pe[21] -eq 0x45)
            Lg ('P3 READ8 MZstatus=0x' + $st0.ToString('X8') + ' e_lfanew=0x' + $elf.ToString('X') + ' PEstatus=0x' + $stPe.ToString('X8') + ' PEsig=' + $pesig + ' PEB=0x' + $peb.ToString('X') + ' PEBread=0x' + $stP.ToString('X8'))
            $p3ok = $cross -and $mzok2 -and $pesig -and ($stP -eq 0) -and $peb -gt 0
            $p3 = $(if ($p3ok) { 'PASS' } else { 'FAIL' }) + ' (pid=' + $gp + ' resolverBase=0x' + $gbase.ToString('X') + ' cross=' + $cross + ' mz=' + $mzok2 + ' pe=' + $pesig + ' pebRead=' + ($stP -eq 0) + ')'
            if (-not $p3ok) { $ex++ }
            if (-not (Get-Process -Id $gp -EA 0)) { Lg 'P3 note: game died mid-probe' }
        } finally { [void][Dev]::CloseHandle($gh) }
    }
}
Lg ('RESULT: P3 driver-game ' + $p3)
if ($hdev -ne [IntPtr]::Zero) { [void][Dev]::CloseHandle($hdev) }
$final = 'PASS'
if (-not ($p1ok -and $mzok)) { $final = 'FAIL' }
if ($p2 -like 'FAIL*' -or $p3 -like 'FAIL*') { $final = 'FAIL' }
$notes = @()
if ($p2 -like 'SKIPPED*') { $notes += 'P2=' + $p2 }
if ($p3 -like 'SKIPPED*') { $notes += 'P3=' + $p3 }
Lg ('VERDICT: h328 ' + $final + ' failChecks=' + $ex + ' - variable = VAD section-name resolver vs [Diagnostics.Process] ground truth (own proc) + driver BASE/Read8/ReadBuf/Write ground-truthed + read-only game crosscheck' + $(if ($notes.Count) { ' | ' + ($notes -join ' | ') } else { '' }))
Emit
if ($final -eq 'PASS') { exit 0 } else { exit 1 }