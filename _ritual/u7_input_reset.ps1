$log = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_u7_input_reset.txt'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class U7 {
  [DllImport("user32.dll")] public static extern bool BlockInput(bool block);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
  [DllImport("user32.dll")] public static extern IntPtr GetCapture();
}
'@
$rows = [System.Collections.Generic.List[string]]::new()
$rows.Add("START $(Get-Date -Format o)")
$rows.Add("BLOCKINPUT_OFF prior=$([U7]::BlockInput($false))")
$before = [U7]::GetAsyncKeyState(0x01)
$rows.Add("LEFT_BEFORE down=$([bool]($before -band 0x8000)) pressedSinceRead=$([bool]($before -band 1)) capture=$([U7]::GetCapture())")
[U7]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
$rows.Add('LEFT_UP_SENT')
$seen = 0
$end = [DateTime]::UtcNow.AddSeconds(8)
while([DateTime]::UtcNow -lt $end) {
  $state = [U7]::GetAsyncKeyState(0x01)
  if($state -band 1) { $seen++ }
  Start-Sleep -Milliseconds 20
}
$after = [U7]::GetAsyncKeyState(0x01)
$rows.Add("LEFT_AFTER down=$([bool]($after -band 0x8000)) pressedTransitions=$seen capture=$([U7]::GetCapture())")
$rows.Add("VERDICT: Windows saw a left-click transition=$([bool]($seen -gt 0)); stuck-down=$([bool]($after -band 0x8000))")
$rows.Add("END $(Get-Date -Format o)")
$rows | Set-Content -LiteralPath $log
