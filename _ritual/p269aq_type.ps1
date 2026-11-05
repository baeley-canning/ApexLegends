# p269aq_type.ps1 - type one cmd line into the WinRE console, Enter, screenshot. p269-only helper.
# Terminal churn reaps long one-liners and mangles multi-VBoxManage chains, so the sequence lives here.
param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Shot,
    [int]$WaitMs = 2500,
    [switch]$NoEnter
)
$vb = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\' + $Shot
& $vb controlvm Win11-Test2 keyboardputstring $Text 2>&1 | Out-Null
$rc1 = $LASTEXITCODE
if (-not $NoEnter) { & $vb controlvm Win11-Test2 keyboardputscancode 1c 9c 2>&1 | Out-Null }
$rc2 = $LASTEXITCODE
Start-Sleep -Milliseconds $WaitMs
& $vb controlvm Win11-Test2 screenshotpng $out 2>&1 | Out-Null
$rc3 = $LASTEXITCODE
"type rc=$rc1 enter rc=$rc2 shot rc=$rc3 -> $Shot"
