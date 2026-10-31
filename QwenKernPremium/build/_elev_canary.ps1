# build\_elev_canary.ps1
#
# Finds an elevation route that works from this medium-IL session, so the LIVE
# probe/ladder can be driven without the operator typing anything.
#
# Route A: Start-Process -Verb RunAs (auto-consent: ConsentPromptBehaviorAdmin=0)
# Route B: one-shot scheduled task with /RL HIGHEST (service launches full token)
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File build\_elev_canary.ps1

$root = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium'
$log  = Join-Path $root 'build\_elev_canary.txt'
$payload = Join-Path $root 'build\_elev_test.ps1'

'== canary ' + (Get-Date -Format 'HH:mm:ss') + ' ==' | Out-File -FilePath $log -Encoding utf8

function Add([string] $text) {
    $text | Out-File -FilePath $log -Encoding utf8 -Append
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
Add ("whoami=" + $id.Name)
Add ("medium_il_elevated=" + (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator))

# ---- Route A ---------------------------------------------------------------
Remove-Item (Join-Path $root 'build\_elev_test.txt') -ErrorAction SilentlyContinue
try {
    $a = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $payload `
        -ErrorAction Stop
    Add ("A: started pid=" + $a.Id)
} catch {
    Add ("A: EXCEPTION " + $_.Exception.Message)
}
Start-Sleep -Seconds 10
Add ("A: output-file=" + (Test-Path (Join-Path $root 'build\_elev_test.txt')))

# ---- Route B ---------------------------------------------------------------
$task = 'QwenKernElevCanary'
$cmd  = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $payload
$out  = & schtasks.exe /create /tn $task /tr $cmd /sc once /st 23:59 /rl HIGHEST /f 2>&1
Add ("B: create -> " + ($out -join ' '))
$out  = & schtasks.exe /run /tn $task 2>&1
Add ("B: run    -> " + ($out -join ' '))
Start-Sleep -Seconds 12
Add ("B: output-file=" + (Test-Path (Join-Path $root 'build\_elev_test.txt')))
if (Test-Path (Join-Path $root 'build\_elev_test.txt')) {
    Add ('B: content -> ' + ((Get-Content (Join-Path $root 'build\_elev_test.txt')) -join ' | '))
}
Add 'canary done'
