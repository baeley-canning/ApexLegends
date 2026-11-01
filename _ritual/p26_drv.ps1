# p26_drv.ps1 -- AGENT A. SINGLE ELEVATED STEP: load the gate-validated apexdrv.sys and prove
# that the kernel can reach the game process (IOCTL_APEXDRV_PROBE = the Q10 barrier).
# REAL ABI: service "apexdrv", device "\\.\ApexDrv", IOCTL_APEXDRV_VERSION=0x8A702004,
#          IOCTL_APEXDRV_PROBE=0x8A702008 (CTL_CODE(0x8A70,0x801/0x802,METHOD_BUFFERED,ANY)).
# run: powershell -NoProfile -ExecutionPolicy Bypass -File _ritual\p26_drv.ps1 [-TargetPid <pid>]
# writes: _ritual\p26_drv.txt   (self-elevates; leaves the service RUNNING on success - the launcher reuses it)
param([int]$TargetPid = 0, [switch]$NoSelfElevate)
$out = Join-Path $PSScriptRoot 'p26_drv.txt'
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }
function L([string]$s) { $s | Out-File -FilePath $out -Append -Encoding utf8; Write-Host $s }
$IOCTL_VERSION = [uint32]2322604036   # 0x8A702004 (decimal: PS5 [uint32]0x8A702004 throws)
$IOCTL_PROBE = [uint32]($IOCTL_VERSION + 4)   # 0x8A702008
$GENERIC_RW = [uint32]3221225472

L ("=== p26_drv  " + (Get-Date) + " ===")
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
L "elevated=$adm"
if (-not $adm -and -not $NoSelfElevate) {
    L "not elevated -> self-elevating via UAC"
    Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'), '-NoSelfElevate')
    L "elevated child launched; this copy exits"
    exit 0
}
if (-not $adm) { L "not elevated and -NoSelfElevate given"; exit 3 }

L "`n--- secure boot / bcdedit ---"
try { L ("SecureBoot=" + (Confirm-SecureBootUEFI)) } catch { L "SecureBoot=(unknown/legacy)" }
$bcd = (bcdedit /enum '{current}' 2>&1 | Out-String)
foreach ($k in 'testsigning', 'nointegritychecks', 'hypervisorlaunchtype') {
    $m = [regex]::Match($bcd, "(?im)^\s*$k\s+(\S+)")
    L ("bcd." + $k + "=" + $(if ($m.Success) { $m.Groups[1].Value } else { '(not set)' }))
}

L "`n--- QwenKern certs in machine stores ---"
foreach ($st in 'Root', 'CA', 'TrustedPublisher') {
    $c = @(Get-ChildItem ("Cert:\LocalMachine\$st") -ErrorAction SilentlyContinue | Where-Object { $_.Subject -match 'QwenKern' })
    L ("store " + $st + ": count=" + $c.Count)
    foreach ($x in $c) { L ("   " + $x.Subject + " [" + $x.Thumbprint + "] notAfter=" + $x.NotAfter) }
}

$drv = Join-Path (Split-Path $PSScriptRoot -Parent) 'QwenKernPremium\build\apexdrv.sys'
L "`n--- driver artifact (gate-validated) ---"
if (Test-Path -LiteralPath $drv) {
    $s = Get-AuthenticodeSignature -LiteralPath $drv
    L ("drv=" + $drv)
    L ("len=" + (Get-Item -LiteralPath $drv).Length + " sha1=" + (Get-FileHash -LiteralPath $drv -Algorithm SHA1).Hash)
    L ("sig=" + $s.Status + " signer=" + $(if ($s.SignerCertificate) { $s.SignerCertificate.Subject } else { '(none)' }))
} else { L "MISSING $drv"; exit 4 }
L "`n--- service apexdrv ---"
$nt = '\??\' + $drv
$qc = ((sc.exe qc apexdrv 2>&1) -join "`n")
if ($qc -match 'BINARY_PATH_NAME') {
    if ($qc -notmatch [regex]::Escape('apexdrv.sys')) {
        L "repointing service to the gate-validated build artifact"
        L ((sc.exe config apexdrv binPath= $nt 2>&1) -join "`n")
    } else { L "service already present (reusing)" }
} else {
    L ((sc.exe create apexdrv binPath= $nt type= kernel start= demand error= normal 2>&1) -join "`n")
}
L ((sc.exe start apexdrv 2>&1) -join "`n")
$startExit = $LASTEXITCODE
L ("start exit=" + $startExit)
Start-Sleep -Milliseconds 900
L ((sc.exe query apexdrv 2>&1) -join "`n")
$st = (Get-Service apexdrv -ErrorAction SilentlyContinue).Status
L "state=$st"
if ($st -ne 'Running') {
    L "`n--- START FAILED: decode + CodeIntegrity evidence ---"
    switch ($startExit) {
        577 { L "577 ERROR_INVALID_IMAGE_HASH -> DSE rejected the signature chain" }
        1275 { L "1275 ERROR_DRIVER_BLOCKED -> Code Integrity blocked it (Secure Boot + self-signed)" }
        5 { L "5 ERROR_ACCESS_DENIED" }
        2 { L "2 ERROR_FILE_NOT_FOUND" }
    }
    try {
        Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-CodeIntegrity/Operational'; StartTime = (Get-Date).AddHours(-6) } -ErrorAction Stop |
            Select-Object -First 8 | ForEach-Object { L ("[CI] id=" + $_.Id + " " + $_.TimeCreated + " :: " + (($_.Message -split "`n")[0])) }
    } catch { L "[CI] log unavailable: " + $_.Exception.Message }
    L "REMEDY:  bcdedit /set testsigning on ; shutdown /r /t 0     OR install a self-made .cat into CatRoot"
}

L "`n--- device open + IOCTL ---"
try { Add-Type @'
using System; using System.Runtime.InteropServices;
public static class D26 {
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr CreateFileW(string n, uint acc, uint sh, IntPtr sa, uint disp, uint fl, IntPtr t);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool DeviceIoControl(IntPtr h, uint code, byte[] inBuf, uint inLen, byte[] outBuf, uint outLen, out uint ret, IntPtr ov);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
}
'@ -ErrorAction Stop } catch { L ("Add-Type FAILED: " + $_.Exception.Message) }
if ('D26' -as [type]) { $h = [D26]::CreateFileW('\\.\ApexDrv', $GENERIC_RW, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero) } else { L "type D26 missing, using raw CreateFile via kernel32"; $h = [IntPtr](-1) }
L ("CreateFile(\\\\.\\ApexDrv) handle=" + $h + " lastErr=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
if ($h -eq [IntPtr](-1)) { L "=> device not opened (driver not loaded or symlink missing)"; exit 5 }

$got = 0
$vo = New-Object byte[] 8
$ok = [D26]::DeviceIoControl($h, $IOCTL_VERSION, (New-Object byte[] 8), 8, $vo, 8, [ref]$got, [IntPtr]::Zero)
L ("IOCTL_VERSION ok=" + $ok + " err=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error() + " driverVersion=" + $(if ($ok) { [BitConverter]::ToUInt32($vo, 0) } else { '-' }))

if ($TargetPid -eq 0) {
    $pr = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(r5apex|baeleys)' } | Select-Object -First 1
    if ($pr) { $TargetPid = $pr.Id; L ("target pid (game) = " + $TargetPid + " " + $pr.ProcessName) }
    else { $TargetPid = (Get-Process -Name explorer | Select-Object -First 1).Id; L ("target pid (explorer fallback) = " + $TargetPid) }
} else { L ("target pid (arg) = " + $TargetPid) }

$in = New-Object byte[] 88
[BitConverter]::GetBytes([uint32]$TargetPid).CopyTo($in, 0)
$po = New-Object byte[] 88
$ok = [D26]::DeviceIoControl($h, $IOCTL_PROBE, $in, 88, $po, 88, [ref]$got, [IntPtr]::Zero)
L ("IOCTL_PROBE ok=" + $ok + " err=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error() + " bytes=" + $got)
if ($ok) {
    $names = @('PsLookupProcessByProcessId', 'ObOpenObjectByPointer', 'ZwAllocateVirtualMemory', 'WriteProcessMemory', 'ZwFreeVirtualMemory', 'MmCopyVirtualMemory')
    for ($i = 0; $i -lt 6; $i++) {
        $v = [BitConverter]::ToInt32($po, 8 + 4 * $i)
        $lbl = switch ([uint32]$v) { 0 { 'SUCCESS' } 0xC0000005 { 'ACCESS_VIOLATION' } 0xC0000022 { 'ACCESS_DENIED' } 0xC00000BB { 'NOT_SUPPORTED' } 0xC0000008 { 'INVALID_HANDLE' } 0xC000009A { 'INSUFFICIENT_RESOURCES' } 0xC000010A { 'PROCESS_IS_TERMINATING' } default { '-' } }
        L ("  " + $names[$i] + " = 0x" + ([uint32]$v).ToString('X8') + " " + $lbl)
    }
    L ("  BytesCopied = " + [BitConverter]::ToUInt32($po, 32))
    $peb = [BitConverter]::ToUInt64($po, 36)   # /Zp1-packed driver: 36, not 40 (vs launcher sizeof 88)
    L ("  PebAddress  = 0x" + $peb.ToString('X'))
    $bytes = $po[52..83]                        # Bytes starts at 52 in the packed layout, not 56
    L ("  PebBytes[0..31] = " + (($bytes | ForEach-Object { $_.ToString('X2') }) -join ' '))
    $img = [BitConverter]::ToUInt64($bytes, 0x10)
    L ("  -> PEB.ImageBaseAddress = 0x" + $img.ToString('X'))
    if ($img -gt 0x10000) { L "*** KERNEL -> TARGET REACH: PROVEN (live PEB copied out from kernel context) ***" }
    else { L "PEB bytes are zero - see per-step statuses above" }
}
[void][D26]::CloseHandle($h)
L "`n=== DONE -> _ritual\p26_drv.txt (service left " + (Get-Service apexdrv -ErrorAction SilentlyContinue).Status + ") ==="

