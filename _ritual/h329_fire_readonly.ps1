# h329_fire_readonly.ps1 - host leg of h329: the READ-ONLY arm against the LIVE game, driver v14.
# Uses the driver that s2_load_v14.ps1 armed (svc RUNNING + DSE 0x16); if either checks fail it
# runs the h318 reload dance itself and leaves the driver RUNNING (consumer convention, like h320).
# Proves the arm with ZERO writes anywhere: BASE(pid) via driver == resolver VAD exe base (h328
# validated the resolver against Get-Process ground truth), MZ+PE chain and PEB read via driver
# ReadBuf, then read-only survival re-reads at +60 s / +300 s (game alive, same base, MZ still
# there, svc RUNNING, dse still 0x16). Elevated (SCM+kdu), so it self-elevates. ONE game launch
# assumed, 15 min fuse. Output: h329_fire_readonly.out next to the script.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h329_fire_readonly.out'
$d    = 'C:\Users\Public\p37'
$sys  = "$env:SystemRoot\System32\drivers\apexdrv.sys"
$V14  = '317E4A86C1817401F98210434DE9DCDEA623086A46AA1C546A97ED833E0CA83C'
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm) { Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $MyInvocation.MyCommand.Path + '"')) -Verb RunAs; exit 0 }
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $out -Value ($L -join "`r`n") }
function Kdu([string[]]$a, [int]$cap = 25000) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $d 'kdu.exe'; $psi.Arguments = ($a -join ' '); $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.WorkingDirectory = $d
    try { $p = [System.Diagnostics.Process]::Start($psi)
          $t1 = $p.StandardOutput.ReadToEndAsync(); $t2 = $p.StandardError.ReadToEndAsync()
          if (-not $p.WaitForExit($cap)) { try { $p.Kill() } catch { } }
          Start-Sleep -Milliseconds 150
          return (($t1.Result + $t2.Result) -replace '\s+', ' ').Trim() } catch { return ('FAIL ' + $_.Exception.Message) }
}
function SvcQ { return (((& "$env:SystemRoot\system32\sc.exe" query apexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|FAILED|does not exist' }) -join ' | ').Trim() }
function Dse { $o = Kdu @('-prv', '20', '-dse', '22'); if ($o -match 'value:\s*([0-9A-Fa-f]+)') { return $matches[1] } else { return '' } } # -dse 22 prints CURRENT then parks 0x16; bare -dse read-AND-writes 0 (h318 trap) which left dse 0 on 07/11 20:02 and Javelin refused the next launch
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
  public static string[] Census(IntPtr h) {
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
        var nb = new byte[1104]; IntPtr r2;
        if (NtQueryVirtualMemory(h, (IntPtr)b, 2, nb, (IntPtr)nb.Length, out r2) == 0) {
          int ul = BitConverter.ToUInt16(nb, 0);
          if (ul > 2 && ul <= 1040) nm = Encoding.Unicode.GetString(nb, 16, ul).TrimEnd('\0');
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
$IO_VER = [uint32](0x8A702004L); $IO_READBUF = [uint32](0x8A702014L); $IO_BASE = [uint32](0x8A70201CL)
function OpenDev { $h = [Dev]::CreateFileW('\\.\ApexDrv', [uint32](0xC0000000L), 0, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero); if ($h -eq [IntPtr](-1)) { return [IntPtr]::Zero }; return $h }
function Put32([byte[]]$b, [int]$o, [uint32]$v) { [BitConverter]::GetBytes($v).CopyTo($b, $o) }
function Put64([byte[]]$b, [int]$o, [uint64]$v) { [BitConverter]::GetBytes($v).CopyTo($b, $o) }
function Io([IntPtr]$h, [uint32]$c, [byte[]]$b) { [uint32]$r = 0; return [Dev]::DeviceIoControl($h, $c, $b, [uint32]$b.Length, $b, [uint32]$b.Length, [ref]$r, [IntPtr]::Zero) }
Lg '===== h329 fire (read-only arm, elevated, 15 min fuse) ====='
$sha = if (Test-Path $sys) { (Get-FileHash $sys -Algorithm SHA256).Hash } else { 'MISSING' }
$dse0 = Dse
Lg ('staged drv sha=' + $sha.Substring(0, [Math]::Min(16, $sha.Length)) + ' svc=[' + (SvcQ) + '] dse=' + $(if ($dse0) { '0x' + $dse0 } else { 'UNREADABLE' }) + ' game=' + @(Get-Process r5apex_dx12 -EA 0).Count)
if ($sha -ne $V14) { Lg 'RESULT: FAIL - staged image is not the v14 build (run s2_stage_v14 first)'; Emit; exit 1 }
$danced = $false
if ((SvcQ) -notmatch 'RUNNING' -or $dse0 -notmatch '^0*16$') {
    $danced = $true
    Lg 'arm gate: svc not RUNNING or dse != 0x16 -> h318 reload dance (R4: owns its restore, leaves RUNNING)'
    if ($dse0 -notmatch '^0*0$') { Lg ('dse->0 out=[' + (Kdu @('-prv', '20', '-dse', '0')) + ']'); Start-Sleep -Milliseconds 400 }
    & "$env:SystemRoot\system32\sc.exe" delete apexdrv 2>&1 | Out-Null
    & "$env:SystemRoot\system32\sc.exe" create apexdrv type= kernel start= demand binPath= $sys 2>&1 | Out-Null
    & "$env:SystemRoot\system32\sc.exe" start apexdrv 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    $q = SvcQ; Lg ('svc after start: ' + $q)
    Lg ('dse->22 out=[' + (Kdu @('-prv', '20', '-dse', '22')) + ']')
    Start-Sleep -Milliseconds 400
    $dse1 = Dse
    Lg ('dse final=' + $(if ($dse1) { '0x' + $dse1 } else { 'UNREADABLE' }))
    if ($q -notmatch 'RUNNING' -or $dse1 -notmatch '^0*16$') { Lg 'RESULT: FAIL - reload did not hold (svc/dse), not arming'; Emit; exit 1 }
}
Lg ('ARMED (' + $(if ($danced) { 'by this script, reload dance' } else { 'pre-existing s2 load' }) + ') - driver RUNNING, dse 0x16 - launch/keep the game up')
$sw = [Diagnostics.Stopwatch]::StartNew(); $tp = 0
while ($sw.Elapsed.TotalMinutes -lt 15 -and -not $tp) { Start-Sleep -Milliseconds 250; $g = @(Get-Process r5apex_dx12 -EA 0); if ($g.Count) { $tp = ($g | Sort-Object Id | Select-Object -First 1).Id } }
if (-not $tp) { Lg 'RESULT: NO-OP - no game in 15 min (driver left RUNNING, dse 0x16)'; Emit; exit 3 }
Lg ('game pid=' + $tp + ' - settle 1500 ms, then read-only arm verification')
Start-Sleep -Milliseconds 1500
$hdev = OpenDev
if ($hdev -eq [IntPtr]::Zero) { Lg 'RESULT: FAIL - \\.\ApexDrv did not open'; Emit; exit 1 }
$v = New-Object byte[] 8
if (-not (Io $hdev $IO_VER $v)) { Lg 'RESULT: FAIL - VERSION ioctl failed'; Emit; exit 1 }
$ver = [int][BitConverter]::ToUInt32($v, 0); Lg ('driver VERSION=' + $ver)
if ($ver -ne 14) { Lg 'RESULT: FAIL - driver is not v14'; Emit; exit 1 }
$gh = [Dev]::OpenProcess([uint32]0x1F0FFF, $false, $tp)
if ($gh -eq [IntPtr]::Zero) { Lg 'RESULT: FAIL - cannot OpenProcess game for the resolver'; Emit; exit 1 }
$census = [Vd]::Census($gh)
Lg ('resolver census entries=' + $census.Count)
$exeB = [uint64]0; $exeN = ''
foreach ($e in $census) { $p3 = $e.Split('|'); if ($p3.Length -ge 3 -and $p3[2] -match '(?i)\\r5apex[^\\]*\.exe$') { $b2 = [uint64]('0x' + $p3[0]); if ($exeB -eq 0 -or $b2 -lt $exeB) { $exeB = $b2; $exeN = $p3[2] } } }
if ($exeB -eq 0) { Lg 'RESULT: FAIL - resolver found no r5apex*.exe MEM_IMAGE region'; Emit; exit 1 }
Lg ('resolver exe base=0x' + $exeB.ToString('X') + ' name=' + $exeN + ' (ground truth for this leg)')
$q = New-Object byte[] 24; Put32 $q 0 ([uint32]$tp); $okBz = Io $hdev $IO_BASE $q
$stB = [int][BitConverter]::ToInt32($q, 8); $srB = [int][BitConverter]::ToInt32($q, 12); $db = [BitConverter]::ToUInt64($q, 16)
$baseEq = ($stB -eq 0 -and $db -eq $exeB)
Lg ('driver BASE status=0x' + $stB.ToString('X8') + ' source=' + $srB + ' base=0x' + $db.ToString('X') + ' ==resolver=' + $baseEq)
function DrvRead([uint64]$a, [int]$n) { $bb = New-Object byte[] (16 + $n); Put32 $bb 0 ([uint32]$tp); Put32 $bb 4 ([uint32]$n); Put64 $bb 8 $a; $ok = Io $hdev $IO_READBUF $bb; $st = [int][BitConverter]::ToInt32($bb, 16); if ($st -eq 0) { $sr = New-Object byte[] $n; [Array]::Copy($bb, 20, $sr, 0, $n); return $sr } else { return $null } }
$mz = DrvRead $exeB 64
$mzOk = ($mz -ne $null -and $mz[0] -eq 0x4D -and $mz[1] -eq 0x5A)
Lg ('driver MZ @exe base: ' + $mzOk + $(if ($mz) { ' first4=' + ('{0:X2}{1:X2}{2:X2}{3:X2}' -f $mz[0], $mz[1], $mz[2], $mz[3]) } else { ' (read failed)' }))
$elfa = 0; $peOk = $false
if ($mzOk) { $d4 = DrvRead ($exeB + 0x3C) 4; if ($d4) { $elfa = [BitConverter]::ToUInt32($d4, 0); $sig = DrvRead ($exeB + $elfa) 4; $peOk = ($sig -ne $null -and $sig[0] -eq 0x50 -and $sig[1] -eq 0x45); Lg ('PE chain: e_lfanew=0x' + $elfa.ToString('X') + ' PE-sig=' + $peOk) } }
$peb = [Vd]::PebOf($gh); $pebQ = if ($peb -ne 0) { DrvRead ([uint64]$peb) 8 } else { $null }
$pebOk = ($peb -ne 0 -and $pebQ -ne $null -and -not ($pebQ[0] -eq 0 -and $pebQ[1] -eq 0 -and $pebQ[2] -eq 0 -and $pebQ[3] -eq 0))
Lg ('PEB=0x' + $peb.ToString('X') + ' driverRead8=' + ($pebQ -ne $null) + ' nonzero=' + $pebOk + $(if ($pebQ) { ' first4=' + ('{0:X2}{1:X2}{2:X2}{3:X2}' -f $pebQ[0], $pebQ[1], $pebQ[2], $pebQ[3]) } else { '' }))
function Surv([string]$tag) {
    $alive = [bool](Get-Process -Id $tp -EA 0)
    $q = New-Object byte[] 24; Put32 $q 0 ([uint32]$tp); $okz = Io $hdev $IO_BASE $q
    $stx = [int][BitConverter]::ToInt32($q, 8); $bx = [BitConverter]::ToUInt64($q, 16)
    $mm = DrvRead $exeB 2
    $mzv = ($mm -ne $null -and $mm[0] -eq 0x4D -and $mm[1] -eq 0x5A)
    $svc = ((SvcQ) -match 'RUNNING'); $dsx = Dse
    $pass = ($alive -and $stx -eq 0 -and $bx -eq $exeB -and $mzv -and $svc -and ($dsx -match '^0*16$'))
    Lg ($tag + ': alive=' + $alive + ' baseStatus=0x' + $stx.ToString('X8') + ' baseEq=' + ($bx -eq $exeB) + ' MZ=' + $mzv + ' svcRUNNING=' + $svc + ' dse=0x' + $dsx + ' => ' + $(if ($pass) { 'PASS' } else { 'FAIL' }))
    return $pass
}
$t0 = Get-Date
while (((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Seconds 2 }
$s60 = Surv '+60s'
while (((Get-Date) - $t0).TotalSeconds -lt 300) { Start-Sleep -Seconds 5 }
$s300 = Surv '+300s'
$armOk = ($baseEq -and $mzOk -and $peOk -and $pebOk)
Lg ('RESULT: ARM base=' + $baseEq + ' MZ=' + $mzOk + ' PE=' + $peOk + ' PEB=' + $pebOk + ' | SURVIVAL +60s=' + $s60 + ' +300s=' + $s300)
$parts = @()
if (-not $armOk) { $parts += 'arm' }
if (-not $s60) { $parts += 'surv+60' }
if (-not $s300) { $parts += 'surv+300' }
$fin = if ($parts.Count -eq 0) { 'PASS' } else { 'FAIL' }
Lg ('VERDICT: h329 ' + $fin + $(if ($parts.Count) { ' failParts=' + ($parts -join ',') } else { '' }) + ' - variable = read-only arm (BASE/ReadBuf/PEB only, ZERO writes) vs live game 300 s survival; driver+svc left RUNNING, dse 0x16')
try { [void][Dev]::CloseHandle($hdev); [void][Dev]::CloseHandle($gh) } catch { }
Emit
if ($fin -eq 'PASS') { exit 0 } else { exit 1 }