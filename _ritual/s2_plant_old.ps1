# s2_plant_old.ps1 -- one-shot helper: overwrite the two v14 stage destinations with KNOWN old images so
# the fixed s2_stage_v14.ps1 exercises its bak-branch (the first, bugged stage run swapped with NO bak).
# Plant sources: drivers\apexdrv.sys.off -> System32 dst ; drivers\apexdrv.sys.bak_p25h.off -> p37\zapexdrv.sys.
# Self-elevating (writes under System32). File copies only: svc + DSE untouched. Output: s2_plant.out
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 's2_plant.out'
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm) { Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $MyInvocation.MyCommand.Path + '"')) -Verb RunAs; exit 0 }
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $out -Value ($L -join "`r`n") }
$drv = "$env:SystemRoot\System32\drivers"
$dst = Join-Path $drv 'apexdrv.sys'
$p37 = 'C:\Users\Public\p37\zapexdrv.sys'
$srcDst = Join-Path $drv 'apexdrv.sys.off'
$srcP37 = Join-Path $drv 'apexdrv.sys.bak_p25h.off'
Lg '===== s2_plant_old (plant known old images at dst + p37; svc + DSE untouched) ====='
Lg ('svc pre: ' + ((& "$env:SystemRoot\system32\sc.exe" query apexdrv 2>&1 | Select-String 'STATE') -join ' ').Trim())
foreach ($f in @($dst, $p37, $srcDst, $srcP37)) { if (-not (Test-Path -LiteralPath $f)) { Lg ('MISSING: ' + $f); Lg 'RESULT: FAIL'; Emit; exit 1 } }
Lg ('PRE  dst=['  + (Get-FileHash -LiteralPath $dst  -Algorithm SHA256).Hash.Substring(0,16) + '] p37=[' + (Get-FileHash -LiteralPath $p37  -Algorithm SHA256).Hash.Substring(0,16) + ']')
Lg ('plant old dst=[' + (Get-FileHash -LiteralPath $srcDst -Algorithm SHA256).Hash.Substring(0,16) + '] p37=[' + (Get-FileHash -LiteralPath $srcP37 -Algorithm SHA256).Hash.Substring(0,16) + ']')
Copy-Item -LiteralPath $srcDst -Destination $dst  -Force
Copy-Item -LiteralPath $srcP37 -Destination $p37 -Force
$hd = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
$hp = (Get-FileHash -LiteralPath $p37 -Algorithm SHA256).Hash
$ok = ($hd -eq (Get-FileHash -LiteralPath $srcDst -Algorithm SHA256).Hash) -and ($hp -eq (Get-FileHash -LiteralPath $srcP37 -Algorithm SHA256).Hash)
Lg ('POST dst=[' + $hd.Substring(0,16) + '] p37=[' + $hp.Substring(0,16) + ']')
if ($ok) { Lg 'RESULT: PASS - both destinations now hold planted old images; next: re-run s2_stage_v14.ps1 (expect bak made x2 + restage v14)'; Emit; exit 0 }
Lg 'RESULT: FAIL - post-plant hash mismatch'; Emit; exit 1
