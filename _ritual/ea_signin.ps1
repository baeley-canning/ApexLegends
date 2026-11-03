# ea_signin - drive the EA app sign-in form by coordinates relative to its live window rect.
# Account: originId kern30120 / kern30120@fldubai.com (created 03/11 ~07:06, see _ritual\js\create.js).
# SendKeys treats ! + ^ % ~ ( ) { } [ ] as modifiers -> escape to literals before sending.
param([int]$Stage = 1)
$rit = $PSScriptRoot
$o   = Join-Path $rit 'ea_signin.txt'
function W($t){ $t | Add-Content -LiteralPath $o }
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System; using System.Runtime.InteropServices;
public class C {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public struct R { public int L, T, Rr, B; }
  public static void Click(int x, int y){
    SetCursorPos(x, y); System.Threading.Thread.Sleep(120);
    mouse_event(0x0002, 0, 0, 0, IntPtr.Zero); System.Threading.Thread.Sleep(60);
    mouse_event(0x0004, 0, 0, 0, IntPtr.Zero); System.Threading.Thread.Sleep(200);
  }
}
'@
function Esc([string]$s){
  $sb = New-Object System.Text.StringBuilder
  foreach($ch in $s.ToCharArray()){
    if('!+^%~(){}[]'.Contains($ch)){ [void]$sb.Append('{').Append($ch).Append('}') } else { [void]$sb.Append($ch) }
  }
  $sb.ToString()
}
$ea = @(Get-Process EADesktop -EA SilentlyContinue)
if(-not $ea.Count){ 'EA not running'; exit 1 }
$pids = @($ea | ForEach-Object { $_.Id })
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public class W2 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
}
'@
$h = [IntPtr]::Zero
$cb = [W2+EP]{ param($w,$l)
  $pp = 0; [void][W2]::GetWindowThreadProcessId($w, [ref]$pp)
  if($pids -contains [int]$pp){ $sb = New-Object System.Text.StringBuilder 300; [void][W2]::GetWindowText($w, $sb, 300); if($sb.ToString() -eq 'EA'){ $script:h = $w } }
  $true
}
[void][W2]::EnumWindows($cb, [IntPtr]::Zero)
if($h -eq [IntPtr]::Zero){ 'EA window not found'; exit 1 }
[void][C]::ShowWindow($h, 9); [void][C]::SetForegroundWindow($h); Start-Sleep -Milliseconds 700
$r = New-Object C+R; [void][C]::GetWindowRect($h, [ref]$r)
"window rect=$($r.L),$($r.T),$($r.Rr),$($r.B) fg=$([C]::GetForegroundWindow()) h=$h" | Tee-Object -Append -FilePath $o

# form geometry is proportional to the window; measured on a 520x867 render
$cx = $r.L + 258
$fieldY = $r.T + 453
$nextY  = $r.T + 631

if($Stage -eq 1){
  'stage1: click email, type, click NEXT' | Add-Content -LiteralPath $o
  [C]::Click($cx, $fieldY)
  Start-Sleep -Milliseconds 300
  [System.Windows.Forms.SendKeys]::SendWait((Esc 'kern30120@fldubai.com'))
  Start-Sleep -Milliseconds 400
  [C]::Click($cx, $nextY)
  Start-Sleep -Milliseconds 2500
}
if($Stage -eq 2){
  'stage2: click password, type, submit' | Add-Content -LiteralPath $o
  [C]::Click($cx, ($r.T + 300))
  Start-Sleep -Milliseconds 300
  [System.Windows.Forms.SendKeys]::SendWait((Esc '7sp0OTh5RBydZQ64j1vX!Q7z'))
  Start-Sleep -Milliseconds 400
  [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
  Start-Sleep -Milliseconds 3000
}
& (Join-Path $rit 'small_shot.ps1') -Scale 0.5