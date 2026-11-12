# s2_stage_v14.ps1 -- session 2: stage the freshly built v14 ApexDrv (19:07 build, 20480 B) into
# System32\drivers\apexdrv.sys (the apexdrv service binPath) and into C:\Users\Public\p37\zapexdrv.sys
# (the copy the h329 VM bench pushes into the guest). FILE COPY ONLY - no service, no DSE, no kdu.
# Old images are kept as hash-named .bak files (R4); the verdict is the post-copy hash read-back (R3).
# Self-elevating (writes under System32).
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 's2_stage_v14.out'
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm) { Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $MyInvocation.MyCommand.Path + '"')) -Verb RunAs; exit 0 }
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $out -Value ($L -join "`r`n") }
# Fh/Fh16, not H/H16: builtin alias 'h' -> Get-History shadows a function named H (alias beats function).
function Fh([string]$p) { if (Test-Path -LiteralPath $p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } else { return 'MISSING' } }
function Fh16([string]$p) { $h = Fh $p; if ($h.Length -ge 16) { return $h.Substring(0,16) } else { return $h } }
$V14 = '317E4A86C1817401F98210434DE9DCDEA623086A46AA1C546A97ED833E0CA83C'
$src = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\apexdrv.sys'
$dst = "$env:SystemRoot\System32\drivers\apexdrv.sys"
$p37 = 'C:\Users\Public\p37\zapexdrv.sys'
Lg '===== s2_stage_v14 (file copy only, svc untouched) ====='
Lg ('PRE src='  + (Fh16 $src) + ' len=' + (Get-Item -LiteralPath $src -EA 0).Length)
Lg ('PRE dst='  + (Fh16 $dst) + ' len=' + (Get-Item -LiteralPath $dst -EA 0).Length)
Lg ('PRE p37z=' + (Fh16 $p37) + ' len=' + (Get-Item -LiteralPath $p37 -EA 0).Length)
Lg ('svc pre: ' + (((& "$env:SystemRoot\system32\sc.exe" query apexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|FAILED|does not exist' }) -join ' | ').Trim())
if ((Fh $src) -ne $V14) { Lg 'RESULT: FAIL - build\apexdrv.sys is not the 19:07 v14 build (run BuildDriver.ps1 first)'; Emit; exit 1 }
foreach ($t in @($dst, $p37)) {
    $h = Fh $t
    if ($h -eq 'MISSING') { Lg ('  ' + $t + ' missing - nothing to back up') ; continue }
    if ($h -eq $V14) { Lg ('  ' + $t + ' already v14 - no bak'); continue }
    $bak = $t + '.' + $h.Substring(0,8) + '.bak'
    if (Test-Path -LiteralPath $bak) { Lg ('  bak exists: ' + (Split-Path -Leaf $bak)) }
    else { Copy-Item -LiteralPath $t -Destination $bak -Force; Lg ('  bak made: ' + (Split-Path -Leaf $bak) + ' sha=' + (Fh16 $bak)) }
}
Copy-Item -LiteralPath $src -Destination $dst -Force
Copy-Item -LiteralPath $src -Destination $p37 -Force
$hd = Fh $dst; $hp = Fh $p37
Lg ('POST dst='  + (Fh16 $dst) + ' len=' + (Get-Item -LiteralPath $dst).Length)
Lg ('POST p37z=' + (Fh16 $p37) + ' len=' + (Get-Item -LiteralPath $p37).Length)
Lg ('svc post: ' + (((& "$env:SystemRoot\system32\sc.exe" query apexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|FAILED|does not exist' }) -join ' | ').Trim())
if ($hd -eq $V14 -and $hp -eq $V14) { Lg 'RESULT: PASS - v14 staged to System32 + p37 (hashes == 317E4A86..); svc untouched'; Emit; exit 0 }
Lg 'RESULT: FAIL - post-copy hash mismatch'; Emit; exit 1
