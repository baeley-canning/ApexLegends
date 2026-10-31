# ============================================================================
# build\diag_driver_path.ps1  — ELEVATED: which ImagePath form can the SCM load?
#
# Differential test: an in-box demand-start driver (beep) proves whether the
# loader works at all on this machine; then the same signed image is offered
# with every ImagePath syntax Windows documents.
# ============================================================================
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium'
$ev   = Join-Path $root 'build\phase1_evidence'
$log  = Join-Path $ev 'driver_path_diag.txt'
$canon = 'C:\Windows\System32\drivers\apexdrv.sys'

function Try-Driver([string] $label, [string] $imagePath) {
    sc.exe delete apexdrv *> $null
    Start-Sleep -Milliseconds 300
    $create = (sc.exe create apexdrv type= kernel start= demand ('binPath= ' + $imagePath)) 2>&1
    $start  = (sc.exe start apexdrv) 2>&1
    $state  = (sc.exe query apexdrv) 2>&1 | Select-String -Pattern 'STATE' | ForEach-Object { $_.Line.Trim() }
    "--- $label" | Out-File -Encoding utf8 -Append $log
    "    binPath : $imagePath" | Out-File -Encoding utf8 -Append $log
    "    create  : $(($create -join ' ').Trim())" | Out-File -Encoding utf8 -Append $log
    "    start   : $(($start -join ' ').Trim())" | Out-File -Encoding utf8 -Append $log
    "    state   : $state" | Out-File -Encoding utf8 -Append $log
    sc.exe stop apexdrv *> $null
    sc.exe delete apexdrv *> $null
    Start-Sleep -Milliseconds 300
}

"== driver path diagnostic $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==" | Out-File -Encoding utf8 $log
"image : $canon ($((Get-Item $canon -ErrorAction SilentlyContinue).Length) bytes) sig=$( (Get-AuthenticodeSignature $canon).Status )" |
    Out-File -Encoding utf8 -Append $log

# 1: control - does ANY kernel driver start on this machine right now?
"--- control: in-box 'beep' service" | Out-File -Encoding utf8 -Append $log
"    qc      : $((sc.exe qc beep) 2>&1 | Select-String 'BINARY_PATH_NAME' | ForEach-Object { $_.Line.Trim() })" |
    Out-File -Encoding utf8 -Append $log
"    start   : $(((sc.exe start beep) 2>&1) -join ' ')" | Out-File -Encoding utf8 -Append $log
"    state   : $((sc.exe query beep) 2>&1 | Select-String 'STATE' | ForEach-Object { $_.Line.Trim() })" |
    Out-File -Encoding utf8 -Append $log
sc.exe stop beep *> $null

Try-Driver 'A: \??\C:\...'      ('\??\' + $canon)
Try-Driver 'B: System32\drivers' 'System32\drivers\apexdrv.sys'
Try-Driver 'C: \SystemRoot\...'  '\SystemRoot\System32\drivers\apexdrv.sys'
Try-Driver 'D: C:\Windows\...'   $canon

(Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber | Format-List | Out-String) |
    Out-File -Encoding utf8 -Append $log
'DONE' | Out-File -Encoding utf8 (Join-Path $ev 'pathdiag_done.txt')
