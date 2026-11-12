# s2_hashtest.ps1 - minimal repro: do H()/H16()/line-25-style comparisons work inside an ELEVATED
# child? Step-traced, appended to _ritual\s2_hashtest.out, parent waits for CHILD-DONE.
# Re-entrant by design: the elevated relaunch reruns this same file; the child has adm=True so it
# skips the spawn branch and runs the work section.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 's2_hashtest.out'
function Trace($s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' [pid ' + $pid + '] ' + $s) }
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm) {
    Remove-Item -LiteralPath $out -EA 0
    Trace ('entry parent adm=' + $adm + ' ps=' + $PSVersionTable.PSVersion)
    Trace 'spawning elevated child via Start-Process -Verb RunAs'
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $MyInvocation.MyCommand.Path + '"')) -Verb RunAs
    for ($i = 0; $i -lt 80; $i++) { Start-Sleep -Milliseconds 500; if ((Get-Content -LiteralPath $out -Raw -EA 0) -match 'CHILD-DONE-2') { break } }
    Add-Content -LiteralPath $out -Value ('parent: poll finished saw-done=' + [bool]((Get-Content -LiteralPath $out -Raw -EA 0) -match 'CHILD-DONE'))
    Get-Content -LiteralPath $out
    exit 0
}
function H([string]$p) { if (Test-Path -LiteralPath $p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } else { return 'MISSING' } }
function H16([string]$p) { $h = H $p; if ($h.Length -ge 16) { return $h.Substring(0,16) } else { return $h } }
$V14 = '317E4A86C1817401F98210434DE9DCDEA623086A46AA1C546A97ED833E0CA83C'
$src = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\apexdrv.sys'
$dst = "$env:SystemRoot\System32\drivers\apexdrv.sys"
Trace ('CHILD adm=' + $adm + ' user=' + [Environment]::UserName + ' ps=' + $PSVersionTable.PSVersion)
try { Trace ('step1 direct hash: ' + (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.Substring(0,16)) } catch { Trace ('step1 THREW: ' + $_.Exception.Message) }
try { $a = H $src; $as = '' + $a; Trace ('step2 H(src): null=' + ($null -eq $a) + ' len=' + $as.Length + ' head=[' + $as.Substring(0, [Math]::Min(20, $as.Length)) + ']') } catch { Trace ('step2 THREW: ' + $_.Exception.Message) }
try { Trace ('step3 H16(src)=[' + (H16 $src) + ']') } catch { Trace ('step3 THREW: ' + $_.Exception.Message) }
try { Trace ('step4 eq=' + ((H $src) -eq $V14) + ' ne=' + ((H $src) -ne $V14)) } catch { Trace ('step4 THREW: ' + $_.Exception.Message) }
try { Trace ('step5 H16(dst)=[' + (H16 $dst) + ']') } catch { Trace ('step5 THREW: ' + $_.Exception.Message) }
Trace ('Error.Count=' + $Error.Count)
for ($i = 0; $i -lt [Math]::Min(4, $Error.Count); $i++) { $m = $Error[$i].ToString(); Trace ('Err[' + $i + ']: ' + $m.Substring(0, [Math]::Min(220, $m.Length))) }
Trace ('alias-h: ' + ((Get-Alias h -EA 0).Definition + ' / ' + (Get-Command H -EA 0).CommandType))
Trace '--- raw (no try) variants, exact stage line-21/25/27 patterns ---'
Add-Content -LiteralPath $out -Value ('RAW21 PRE src=[' + (H16 $src) + '] len=' + (Get-Item -LiteralPath $src -EA 0).Length)
if ((H $src) -ne $V14) { Add-Content -LiteralPath $out -Value 'RAW25: would-FAIL (H returned not-v14)' } else { Add-Content -LiteralPath $out -Value 'RAW25: eq-ok' }
foreach ($t in @($dst)) {
    $h = H $t
    Add-Content -LiteralPath $out -Value ('RAW27 h-is-null=' + ($null -eq $h))
    if ($h -eq 'MISSING') { Add-Content -LiteralPath $out -Value '  missing'; continue }
    if ($h -eq $V14) { Add-Content -LiteralPath $out -Value '  already v14'; continue }
    try { $bak = $t + '.' + $h.Substring(0,8) + '.bak'; Add-Content -LiteralPath $out -Value ('  bak would be [' + $bak + ']') } catch { Add-Content -LiteralPath $out -Value ('  bakExpr THREW: ' + $_.Exception.Message) }
}
Trace '--- renamed control: function Fh ---'
function Fh([string]$q) { if (Test-Path -LiteralPath $q) { return (Get-FileHash -LiteralPath $q -Algorithm SHA256).Hash } else { return 'MISSING' } }
Add-Content -LiteralPath $out -Value ('FH src=[' + (Fh $src).Substring(0,16) + ']')
Trace '--- fix preview: Remove-Item alias:h then H resolves to function ---'
Remove-Item Alias:h -Force -EA 0
Add-Content -LiteralPath $out -Value ('after-unalias RAW21 H16=[' + (H16 $src) + ']')
Trace 'CHILD-DONE-2'
