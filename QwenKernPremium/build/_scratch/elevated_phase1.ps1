# ============================================================================
# build\elevated_phase1.ps1 — ELEVATED evidence pass (2026-10-26, PHASE 1.4)
#
# Why elevated: Q13 (fltmc needs admin), Q9 (does the launcher's integrity level
# change the denial?), Q12 (is the target blackout state-dependent?).  The
# non-elevated pass of the same day is in e1_probe.txt / e2_ladder.txt; this
# script writes the elevated counterparts next to it so the two can be compared
# line by line.  It NEVER installs anything and never reboots.
#
# Run:  Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile',
#         '-ExecutionPolicy','Bypass','-File','...\build\elevated_phase1.ps1'
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

Write-Evidence 'elev_identity.txt' {
    $principal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent())
    "elevated  : $($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
    "integrity : $([Security.Principal.WindowsIdentity]::GetCurrent().Groups | Where-Object { $_.Value -like 'S-1-16-*' })"
    "session   : $((Get-Process -Id $PID).SessionId)  user: $env:USERNAME"
    whoami /groups
}

# Q13 — the file-I/O minifilter altitude table was readable only as admin.
Write-Evidence 'elev_fltmc_filters.txt'   { fltmc filters }
Write-Evidence 'elev_fltmc_instances.txt' { fltmc instances -v }
Write-Evidence 'elev_fltmc_volumes.txt'   { fltmc volumes }

# Which anti-cheat kernel components exist, per SCM (not per driverquery).
Write-Evidence 'elev_services.txt' {
    sc.exe query state= all | Select-String -Pattern 'eaanti|javelin|EasyAnti|BEDaisy|service_name' -Context 0,3
}

# Q9/Q12 — the elevated launcher against the live game, and the same again with
# the driver staged.  --forget-sticky so the ladder really starts at the top.
$apex = (Get-Process r5apex_dx12 -ErrorAction SilentlyContinue |
         Select-Object -First 1).Id
"APEX_PID=$apex" | Out-File -Encoding utf8 (Join-Path $ev 'elev_apex.txt')

if ($apex) {
    "exit=$LASTEXITCODE" | Out-Null
    .\apex_launcher.exe --forget-sticky --probe --pid=$apex *>&1 |
        Out-File -Encoding utf8 (Join-Path $ev 'elev_probe.txt')
    "PROBE_EXIT=$LASTEXITCODE" | Out-File -Encoding utf8 -Append (Join-Path $ev 'elev_probe.txt')

    .\apex_launcher.exe --inject --no-wait --pid=$apex *>&1 |
        Out-File -Encoding utf8 (Join-Path $ev 'elev_ladder.txt')
    "LADDER_EXIT=$LASTEXITCODE" | Out-File -Encoding utf8 -Append (Join-Path $ev 'elev_ladder.txt')

    # Independently of our own reader: can PowerShell see the module list, and
    # does the payload show up as a module of the game afterwards?
    Write-Evidence 'elev_mod_check.txt' {
        $p = Get-Process -Id $apex
        "path      : $($p.Path)"
        "modules   : $($p.Modules.Count)"
        $p.Modules | Where-Object { $_.ModuleName -match 'apexcheat|d3d11|d3d12|dxgi' } |
            ForEach-Object { "$($_.ModuleName) base=0x$('{0:X}' -f $_.BaseAddress.ToInt64()) size=$($_.ModuleMemorySize)" }
        "psapi_via_ps : $((Get-Process -Id $apex).Modules.Count) entries"
        "sticky    : " + ((Get-Content .\apexcheat.launcher.ini -ErrorAction SilentlyContinue) -join ' / ')
    }
} else {
    'game not running' | Out-File -Encoding utf8 -Append (Join-Path $ev 'elev_probe.txt')
}

'DONE' | Out-File -Encoding utf8 (Join-Path $ev 'elev_done.txt')
