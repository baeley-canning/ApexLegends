# ============================================================================
# build\elevated_nogame.ps1 — the elevated half of the Q13/Q12 evidence pass
# that 17:19 missed: fltmc with the EAC minifilter ACTUALLY loaded, plus the
# elevated probe/ladder against the live game.  Same shape as elevated_phase1.
# ============================================================================
$ErrorActionPreference = 'Continue'

$root = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium'
$ev   = Join-Path $root 'build\phase1_evidence'
Set-Location (Join-Path $root 'build')

function Write-Evidence([string] $name, [scriptblock] $body) {
    $path = Join-Path $ev $name
    "== $name  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==" | Out-File -Encoding utf8 $path
    try   { (& $body *>&1 | Out-String -Width 240) | Out-File -Encoding utf8 -Append $path }
    catch { "EXCEPTION: $_" | Out-File -Encoding utf8 -Append $path }
}

# Q13 first, and now it is the interesting case: the minifilter list WITH the
# anti-cheat stack resident (17:19 captured it with the game closed).
Write-Evidence 'elev2_fltmc_filters.txt'   { fltmc filters }
Write-Evidence 'elev2_fltmc_instances.txt' { fltmc instances }
Write-Evidence 'elev2_fltmc_volumes.txt'   { fltmc volumes }
Write-Evidence 'elev2_drivers.txt' {
    driverquery /v /fo csv | ConvertFrom-Csv |
        Where-Object { $_.'Module Name' -match 'eaanti|javelin|EasyAnti|apexdrv' } |
        Select-Object 'Module Name', State, 'Path' | Format-List
}

$apex = (Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1).Id
"APEX_PID=$apex" | Out-File -Encoding utf8 (Join-Path $ev 'elev2_apex.txt')

if ($apex) {
    .\apex_launcher.exe --forget-sticky --probe --pid=$apex *>&1 |
        Out-File -Encoding utf8 (Join-Path $ev 'elev2_probe.txt')
    "PROBE_EXIT=$LASTEXITCODE" | Out-File -Encoding utf8 -Append (Join-Path $ev 'elev2_probe.txt')

    .\apex_launcher.exe --inject --no-wait --pid=$apex *>&1 |
        Out-File -Encoding utf8 (Join-Path $ev 'elev2_ladder.txt')
    "LADDER_EXIT=$LASTEXITCODE" | Out-File -Encoding utf8 -Append (Join-Path $ev 'elev2_ladder.txt')

    Write-Evidence 'elev2_mod_check.txt' {
        $p = Get-Process -Id $apex
        "path    : $($p.Path)"
        "modules : $($p.Modules.Count)"
        $p.Modules | Where-Object { $_.ModuleName -match 'apexcheat|d3d11|d3d12|dxgi|Activation' } |
            ForEach-Object { "$($_.ModuleName) base=0x$('{0:X}' -f $_.BaseAddress.ToInt64())" }
        'sticky  : ' + ((Get-Content .\apexcheat.launcher.ini -ErrorAction SilentlyContinue) -join ' / ')
    }
} else {
    'game not running' | Out-File -Encoding utf8 (Join-Path $ev 'elev2_probe.txt')
}

'DONE' | Out-File -Encoding utf8 (Join-Path $ev 'elev2_done.txt')
