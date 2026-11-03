# ea_show - force the EA app window visible and foregrounded, then dump what is actually on screen.
# PrintWindow returns the wrong pixels for EA's Electron surface, so this uses a real desktop grab.
$rit = $PSScriptRoot
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public class S {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
'@
$ea = @(Get-Process EADesktop -EA SilentlyContinue)
if(-not $ea.Count){ 'EA not running'; exit 1 }
$pids = @($ea | ForEach-Object { $_.Id })
$hits = @()
$cb = [S+EP]{ param($h,$l)
  $pp = 0; [void][S]::GetWindowThreadProcessId($h, [ref]$pp)
  if($pids -contains [int]$pp){
    $sb = New-Object System.Text.StringBuilder 300; [void][S]::GetWindowText($h, $sb, 300)
    $script:hits += [pscustomobject]@{ H = $h; T = $sb.ToString() }
  }
  $true
}
[void][S]::EnumWindows($cb, [IntPtr]::Zero)
"windows found: $($hits.Count)"
foreach($w in $hits){ "  [$($w.T)] h=$($w.H)" }
$target = $hits | Where-Object { $_.T -match 'EA' } | Select-Object -First 1
if($target){
  [void][S]::ShowWindow($target.H, 9)   # SW_RESTORE
  [void][S]::ShowWindow($target.H, 5)   # SW_SHOW
  [void][S]::SetForegroundWindow($target.H)
  "shown h=$($target.H) fg now=$([S]::GetForegroundWindow())"
} else { 'no EA-titled window to show' }
& (Join-Path $rit 'small_shot.ps1') -Scale 0.5