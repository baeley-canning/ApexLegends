# h2_prep - preserve prior evidence under new numbers (R5) and record pre-state (R3) before the
# H1 re-establishment on this boot. No state mutation, no elevation needed. Re-run safe.
$rit = $PSScriptRoot
$o   = Join-Path $rit 'h2_prep.txt'
function W($t){ $t | Add-Content -LiteralPath $o }
"=== h2_prep $(Get-Date -f 'dd/MM/yyyy HH:mm:ss') ===" | Set-Content -LiteralPath $o

# ---- R5: never let a rerun overwrite the only copy of a pass/failure log -------------------
function Keep([string]$src, [string]$dst){
    if(Test-Path -LiteralPath $src){
        if(-not (Test-Path -LiteralPath $dst)){ Copy-Item -LiteralPath $src -Destination $dst; W ('kept ' + (Split-Path $src -Leaf) + ' -> ' + (Split-Path $dst -Leaf)) }
        else { W ('keep skipped (exists): ' + (Split-Path $dst -Leaf)) }
    } else { W ('keep: source missing ' + (Split-Path $src -Leaf)) }
}
Keep (Join-Path $rit 'h1_host.txt')        (Join-Path $rit 'h1_host_boot2.txt')
Keep (Join-Path $rit 'h2_gate.txt')        (Join-Path $rit 'h2_gate_boot1.txt')
Keep (Join-Path $rit 'h2_gate.summary.txt')(Join-Path $rit 'h2_gate_boot1.summary.txt')

# ---- R3: pre-state ----------------------------------------------------------------
W ''
W '## pre-state'
W ('lastboot=' + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime)
W ('proc r5apex/EADesktop: ' + ((Get-Process r5apex_dx12,r5apex,EADesktop -EA SilentlyContinue | ForEach-Object { $_.Name + ':' + $_.Id }) -join ' '))
W ('apexdrv: ' + (((& sc.exe query apexdrv 2>&1) | Select-String 'STATE' | ForEach-Object { $_.ToString().Trim() }) -join ' '))
W ('blocklist=' + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config' -EA SilentlyContinue).VulnerableDriverBlocklistEnable)
$bin = "$env:WINDIR\System32\drivers\apexdrv.sys"
if(Test-Path -LiteralPath $bin){ W ('bin sha256=' + (Get-FileHash -LiteralPath $bin -Algorithm SHA256).Hash) } else { W 'bin MISSING' }
W '=== end prep ==='
