# ============================================================================
# build\diag_driver_path2.ps1 — ELEVATED: is it our image or the service shape?
#   1. raw ImagePath values of working in-box drivers (the template)
#   2. an in-box, not-currently-running driver created the same way
#   3. our image from a short, non-protected path
# ============================================================================
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium'
$ev   = Join-Path $root 'build\phase1_evidence'
$log  = Join-Path $ev 'driver_path_diag2.txt'

function Dump-Key([string] $name) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
    if (-not (Test-Path $key)) { "  $name : <no key>" | Out-File -Encoding utf8 -Append $log; return }
    $props = Get-ItemProperty $key
    "  $name : Type=$($props.Type) Start=$($props.Start) ImagePath='$($props.ImagePath)'" |
        Out-File -Encoding utf8 -Append $log
}

function Try-Load([string] $svc, [string] $imagePath) {
    sc.exe delete $svc *> $null
    Start-Sleep -Milliseconds 300
    $create = (sc.exe create $svc type= kernel start= demand ('binPath= ' + $imagePath)) 2>&1
    Dump-Key $svc
    $start = (sc.exe start $svc) 2>&1
    $state = (sc.exe query $svc) 2>&1 | Select-String 'STATE' | ForEach-Object { $_.Line.Trim() }
    "  create  : $(($create -join ' ').Trim())" | Out-File -Encoding utf8 -Append $log
    "  start   : $(($start -join ' ').Trim())"   | Out-File -Encoding utf8 -Append $log
    "  state   : $state"                          | Out-File -Encoding utf8 -Append $log
    sc.exe stop $svc *> $null
    sc.exe delete $svc *> $null
    Start-Sleep -Milliseconds 300
}

"== driver path diagnostic 2 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==" | Out-File -Encoding utf8 $log
"--- existing in-box driver keys (reference) ---" | Out-File -Encoding utf8 -Append $log
'beep', 'luafv', 'null', 'msfs', 'cldflt' | ForEach-Object { Dump-Key $_ }

"--- control: in-box luafv.sys, demand start, created by us ---" | Out-File -Encoding utf8 -Append $log
Try-Load 'luatest' '\??\C:\Windows\System32\drivers\luafv.sys'

"--- ours from System32\drivers ---" | Out-File -Encoding utf8 -Append $log
Try-Load 'apexdrv' '\??\C:\Windows\System32\drivers\apexdrv.sys'

New-Item -ItemType Directory -Force -Path 'C:\apexdrv' | Out-Null
Copy-Item 'C:\Windows\System32\drivers\apexdrv.sys' 'C:\apexdrv\apexdrv.sys' -Force
"--- ours from C:\apexdrv (short path, not System32) ---" | Out-File -Encoding utf8 -Append $log
Try-Load 'apexdrv' '\??\C:\apexdrv\apexdrv.sys'

"--- registry free space / value type of a fresh key ---" | Out-File -Encoding utf8 -Append $log
(reg query 'HKLM\SYSTEM\CurrentControlSet\Services\luafv' /v ImagePath) 2>&1 |
    Out-File -Encoding utf8 -Append $log

'DONE' | Out-File -Encoding utf8 (Join-Path $ev 'pathdiag2_done.txt')
