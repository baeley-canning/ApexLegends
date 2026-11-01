# p29 - GATE DISCRIMINATOR: is the 20:36 Javelin popup caused by the BOOT FLAG (testsigning)
# or by our self-signed apexdrv being LOADED?  Only one of the two is removable without a reboot.
# Method: stop apexdrv (leave it stopped), then launch the game exactly like p27 does.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File _ritual\p29_gate2.ps1 [-WaitSec 150]
# Writes: _ritual\p29_gate2.txt  (and archives the previous p27 evidence)
param([int]$WaitSec = 150)
$ErrorActionPreference = 'Continue'
$o = Join-Path $PSScriptRoot 'p29_gate2.txt'
function W($t){ $t | Add-Content -LiteralPath $o }
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if(-not $adm){
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-WaitSec',"$WaitSec")
  exit
}
"=== p29 GATE DISCRIMINATOR $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') admin=True host=$env:COMPUTERNAME ===" | Set-Content -LiteralPath $o
W 'QUESTION: with TESTSIGNING still in the boot config, does the game start once the self-signed'
W '          driver is NOT loaded?  yes -> our loaded driver is the trigger (no reboot needed)'
W '                                   no  -> the boot flag alone is the trigger (reboot required)'

W ''
W '########## A: stop our driver (leave it stopped) ##########'
$p27 = Join-Path $PSScriptRoot 'p27_gate.txt'
if(Test-Path -LiteralPath $p27){ Copy-Item -LiteralPath $p27 -Destination (Join-Path $PSScriptRoot 'p27_gate_run1.txt') -Force; W '  archived p27_gate.txt -> p27_gate_run1.txt' }
W ("  before: {0}" -f (((& sc.exe query apexdrv 2>&1) -join ' ~ ') -replace '\s+',' '))
$rc = 0
& sc.exe stop apexdrv *> $null; $rc = $LASTEXITCODE
Start-Sleep -Seconds 3
W ("  sc stop apexdrv rc={0}" -f $rc)
W ("  after : {0}" -f (((& sc.exe query apexdrv 2>&1) -join ' ~ ') -replace '\s+',' '))
W ("  other lab services: {0}" -f ((('apexdrv_cat','kernprobe') | ForEach-Object { $_ + '=' + (((& sc.exe query $_ 2>&1) | Select-String 'STATE' | ForEach-Object { $_.ToString().Trim() })) }) -join ' ; '))

# best effort: dismiss the leftover modal "Security Violation" message box (owned by csrss)
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class PW29 {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowW(string cls, string name);
  [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
}
'@ -ErrorAction SilentlyContinue
$titles = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match 'Security Violation' } | ForEach-Object { $_.ProcessName + ':' + $_.MainWindowTitle })
W ("  popup windows before dismiss: [{0}]" -f ($titles -join ' | '))
$h = [PW29]::FindWindowW($null, 'Security Violation')
if($h -ne [IntPtr]::Zero){ [void][PW29]::PostMessageW($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero); W '  posted WM_CLOSE to the Security Violation box' } else { W '  (no exact-titled window found - the operator may need to click OK)' }

W ''
W '########## B: launch the game with the driver stopped ##########'
W '  (p27 is invoked with -Launch; its popup watcher is the detector)'
$t0 = Get-Date
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'p27_gate.ps1') -Launch -WaitSec $WaitSec *> (Join-Path $PSScriptRoot 'p29_p27_out.txt')
W ("  p27 exit={0} elapsed={1:N0}s" -f $LASTEXITCODE,((New-TimeSpan -Start $t0).TotalSeconds))

W ''
W '########## C: result (from the p27 evidence file) ##########'
$lines = @(Get-Content -LiteralPath $p27 -ErrorAction SilentlyContinue)
$idx = [array]::IndexOf($lines, ($lines | Where-Object { $_ -match '========== VERDICT' } | Select-Object -First 1))
if($idx -ge 0){ $lines[$idx..([Math]::Min($idx+18,$lines.Count-1))] | ForEach-Object { W ('  ' + $_) } } else { W '  (no verdict block in p27_gate.txt)' }
$popupRows = @($lines | Where-Object { $_ -match '\*\*\* POPUP \*\*\*' -or $_ -match 't\+\s*\d+s.*POPUP' -or ($_ -match 'Security Violation' -and $_ -match '20:') })
W ''
W ("  new popup rows in this run: {0}" -f $popupRows.Count)
$popupRows | ForEach-Object { W ('   ' + $_) }

W ''
W '########## VERDICT ##########'
$hasPopup = ($popupRows.Count -gt 0)
if($hasPopup){
  W '  STILL BLOCKED with the driver stopped => the BOOT FLAG (testsigning) alone is enough.'
  W '  NEXT: run21.cmd (bcdedit testsigning off, self-elevating) then REBOOT; after the reboot'
  W '        run27.cmd to confirm the gate is closed, then run28.cmd to inject the ESP.'
  W '        apexdrv stays stopped by design (it 577s under testsigning-off until the cat DB is fixed).'
} else {
  W '  GAME STARTED with the driver stopped => our loaded self-signed apexdrv is what Javelin flagged.'
  W '  => the ESP can be tested RIGHT NOW, no reboot: run28.cmd (usermode rung) and press INSERT.'
  W '  => and it tells us the driver track needs a properly trusted signer (stage 4), not just a cat.'
}
W ("  state now: apexdrv={0}" -f ((& sc.exe query apexdrv 2>&1) | Select-String 'STATE').ToString().Trim())
W ''
W "-- p29 END $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') --"
