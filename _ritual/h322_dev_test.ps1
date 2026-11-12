# h322_dev_test.ps1 - can the driver device be opened WITHOUT elevation?  The SCM call needs
# admin, a plain CreateFileW on \\.\ApexDrv does not unless the DACL forbids it.  If this opens,
# the whole probe can be driven non-elevated (no UAC, no schtasks, no DSE round-trip).
$ErrorActionPreference = 'Stop'
$f = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'h322_dev_test.out'
$src = @'
using System; using System.Runtime.InteropServices;
public static class Dev {
  [DllImport("kernel32", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr CreateFileW(string p, uint acc, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);
  [DllImport("kernel32", SetLastError=true)]
  public static extern bool DeviceIoControl(IntPtr h, uint code, byte[] inb, uint inl, byte[] outb, uint outl, out uint ret, IntPtr ov);
  [DllImport("kernel32", SetLastError=true)]
  public static extern bool CloseHandle(IntPtr h);
}
'@
$l = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $l.Add((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) }
Lg ('admin=' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
Add-Type -TypeDefinition $src
$h = [Dev]::CreateFileW('\\.\ApexDrv', [uint32]0xC0000000, 0, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
Lg ('handle=' + $h + ' err=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
if ($h -eq [IntPtr](-1)) { Lg 'RESULT: DENIED - device needs elevation'; Set-Content -LiteralPath $f -Value $l; exit 1 }
$inb = New-Object byte[] 8; $outb = New-Object byte[] 8; [uint32]$ret = 0
$ok = [Dev]::DeviceIoControl($h, 0x8A702004, $inb, 8, $outb, 8, [ref]$ret, [IntPtr]::Zero)
Lg ('version ioctl=' + $ok + ' err=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error() + ' version=' + [BitConverter]::ToUInt32($outb, 0))
[void][Dev]::CloseHandle($h)
Lg 'RESULT: device reachable non-elevated - an unprivileged probe fuse is possible'
Set-Content -LiteralPath $f -Value $l
