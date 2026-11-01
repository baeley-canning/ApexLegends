# prep3.ps1 - ELEVATED, pre-reboot prep for the test-signing activation reboot.
# 1. delete the stale System32\drivers\apexdrv.sys (old ImagePath target)
# 2. park the VMs (savestate) so the hard reboot cannot dirty their disks
# 3. register a SYSTEM/at-startup task that loads apexdrv and probes on the
#    next boot, so the reboot is not wasted even if no one logs in.
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium'
$log  = 'C:\qkp\prep3.txt'
if (-not (Test-Path 'C:\qkp')) { New-Item -ItemType Directory -Force -Path 'C:\qkp' | Out-Null }
function W([string] $t) { $t | Out-File -Encoding utf8 -Append $log }

"== prep3 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==" | Out-File -Encoding utf8 $log
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
W "elevated : $isAdmin"

$bcd = (& cmd /c 'bcdedit /enum {current}' 2>&1 | Out-String)
W "bcd testsigning=Yes : $($bcd -match 'testsigning\s+Yes')   (activates at NEXT boot)"
W "lastboot           : $((Get-CimInstance Win32_OperatingSystem).LastBootUpTime)"

# --- 1: the stale System32 copy (this is the one that produced the 13:58 577) ---
$stale = 'C:\Windows\System32\drivers\apexdrv.sys'
if (Test-Path $stale) {
    try { Remove-Item $stale -Force -ErrorAction Stop; W "stale  : removed $stale" }
    catch { W "stale  : could not remove - $($_.Exception.Message)" }
} else { W 'stale  : none' }

# --- 2: park the VMs (VBoxHeadless gets hard-killed by the reboot) ---
$vb = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
if (Test-Path $vb) {
    (& $vb list runningvms 2>&1) | ForEach-Object {
        $line = "$_"
        if ($line -match '"([^"]+)"') {
            $vm = $Matches[1]
            W "vm     : savestate $vm"
            (& $vb controlvm $vm savestate 2>&1) | ForEach-Object { if ("$_".Trim()) { W "  | $_" } }
        }
    }
} else { W 'vm     : VBoxManage not found' }

# --- 3: the boot-time loader task ---
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument `
    '-NoProfile -ExecutionPolicy Bypass -File "C:\Users\New User\OneDrive\Desktop\cheating\_ritual\boot3.ps1"'
$trg = New-ScheduledTaskTrigger -AtStartup
$trg.Delay = 'PT30S'
$pr = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
Register-ScheduledTask -TaskName 'QwenKern-Boot-Load' -Action $act -Trigger $trg -Principal $pr -Settings $set -Force |
    Out-Null
W "task   : QwenKern-Boot-Load registered=$([bool](Get-ScheduledTask -TaskName 'QwenKern-Boot-Load' -ErrorAction SilentlyContinue))"
W 'RESULT: ready for the test-signing activation reboot.'
W 'END'
