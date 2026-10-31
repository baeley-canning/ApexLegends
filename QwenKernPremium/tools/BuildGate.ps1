<#
================================================================================
 tools\BuildGate.ps1 — PHASE 0 GUARDRAIL (docs\ROADMAP_TO_PREMIUM_PRODUCT.txt 0.2)

 What it enforces (each is a hard fail, exit code 1):
   1. apex_cheat.sln rebuilds with exit code 0.
   2. ZERO compiler warnings (/W4 + /WX for our own TUs) and zero errors.
   3. build\apexcheat.dll static import table == ALLOWLIST (exact set).
   4. build\apex_launcher.exe static import table == ALLOWLIST (exact set).
   5. Artifacts are present, non-empty and x64.
   6. No dead symbols: the deleted QwenKernPremium class / g_pCheat global
      must not reappear in CODE anywhere in src, include, launcher, driver,
      tools.  Comments that merely mention them (main.h documents the removal)
      are reported as notes, not failures.
   7. If the companion driver apexdrv.sys has been built (it needs the WDK,
      which is a separate download), it must be a non-empty x64 PE with an
      ntoskrnl.exe import.  Absent driver = NOTE, not a failure, so the gate is
      usable on a box without the WDK.

 WHY THE ALLOWLISTS ARE EXACT SETS, NOT "no error":
   The anti-cheat sees our module's import table.  Every static import is a
   foreign module that must already be mapped in r5apex_dx12.exe, and every
   extra entry is a fingerprint that rotates with updates.  d3d9.dll,
   d3dcompiler_47.dll and the static dxgi import were all removed for exactly
   this reason (resolved lazily with LoadLibrary at hook time instead).  A
   "builds fine" check cannot see a re-introduced static import; a set
   comparison can.

 USAGE
   powershell -ExecutionPolicy Bypass -File tools\BuildGate.ps1
   powershell -ExecutionPolicy Bypass -File tools\BuildGate.ps1 -SkipBuild
================================================================================
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')] [string] $Configuration = 'Release',
    [ValidateSet('x64', 'Win32')]     [string] $Platform      = 'x64',
    [switch] $SkipBuild
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Solution = Join-Path $RepoRoot 'apex_cheat.sln'
$GateDir  = Join-Path $RepoRoot 'build\gate'
$BuildLog = Join-Path $GateDir 'build.log'
$Report   = Join-Path $GateDir 'gate_report.txt'

$Failures = New-Object System.Collections.Generic.List[string]
$Notes    = New-Object System.Collections.Generic.List[string]

# ---------------------------------------------------------------------------
# Allowlists — CHANGE ONLY WITH A DOCUMENTED REASON (see header comment).
# Keys are artifact paths, values the complete set of allowed imports.
#
# ALLOWLIST HISTORY (newest first; every change needs an entry here)
#   2026-10-26 PHASE 1.4 / decision D6 — d3d11.dll REMOVED from apexcheat.dll.
#       Measured reason: r5apex_dx12.exe is DX12-only and its own import table
#       holds exactly one module (Core\Activation64.dll); it never loads
#       d3d11.dll.  With a static d3d11 import, the single LoadLibraryW() that
#       injects us also resolved d3d11.dll and d3d11.dll's dxgi.dll into the
#       target - one foreign module plus two modules that look like the game's
#       own doing, all inside the call the anti-cheat can watch.  d3d11.dll is
#       now resolved with LoadLibraryA at hook time (src\hooks.cpp:
#       ResolveD3D11CreateDeviceAndSwapChain), exactly like d3d9.dll,
#       d3dcompiler_47.dll and dxgi.dll already were.  The injection therefore
#       adds ONE module (apexcheat.dll) and, per the new check 7, the companion
#       driver is the only other artifact allowed to exist at all.
#   2026-10-26 PHASE 0 — initial sets (apexcheat.dll had d3d11.dll).
# ---------------------------------------------------------------------------
$AllowList = @{
    'build\apexcheat.dll'     = @('KERNEL32.dll', 'USER32.dll')
    'build\apex_launcher.exe' = @('ADVAPI32.dll', 'KERNEL32.dll')
}

function Add-Failure([string] $text) { $script:Failures.Add($text) }
function Add-Note([string] $text)    { $script:Notes.Add($text) }

function Find-MSBuild {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $install = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath 2>$null
        if ($install) {
            $candidate = Join-Path $install 'MSBuild\Current\Bin\MSBuild.exe'
            if (Test-Path $candidate) { return $candidate }
        }
    }
    foreach ($candidate in @(
        'C:\BuildTools\MSBuild\Current\Bin\MSBuild.exe',
        'C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe',
        'C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe',
        'C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe')) {
        if (Test-Path $candidate) { return $candidate }
    }
    $command = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}
function Find-Dumpbin {
    $roots = @(
        'C:\BuildTools\VC\Tools\MSVC',
        (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'))
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $hit = Get-ChildItem $root -Recurse -Filter 'dumpbin.exe' -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName -match 'Hostx64\\x64' -or $_.FullName -match '\\x64\\' } |
               Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    $command = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}

function Get-StaticImports([string] $dumpbin, [string] $artifact) {
    $output  = @(& $dumpbin /nologo /dependents $artifact 2>&1)
    $imports = New-Object System.Collections.Generic.List[string]
    $inBlock = $false
    foreach ($line in $output) {
        $trimmed = "$line".Trim()
        if ($trimmed -match '^Image has the following dependencies:') { $inBlock = $true;  continue }
        if ($trimmed -match 'following delay load dependencies:')      { $inBlock = $false; continue }
        if (-not $inBlock) { continue }
        if ($trimmed -eq '') {
            # dumpbin prints a blank line immediately AFTER the header, so a
            # blank line only closes the block once names have been collected.
            if ($imports.Count -gt 0) { $inBlock = $false }
            continue
        }
        $imports.Add($trimmed)
    }
    return $imports
}

New-Item -ItemType Directory -Force -Path $GateDir | Out-Null

Write-Host '=== BUILD GATE (PHASE 0) ===' -ForegroundColor Cyan
Write-Host "repo    : $RepoRoot"
Write-Host "config  : $Configuration|$Platform"

# --- 1/2: build clean ------------------------------------------------------
if ($SkipBuild) {
    Add-Note 'rebuild skipped (-SkipBuild): import + symbol checks run on existing artifacts'
} else {
    $msbuild = Find-MSBuild
    if (-not $msbuild) {
        Add-Failure 'MSBuild.exe not found (vswhere, BuildTools and PATH all missed)'
    } else {
        Write-Host "msbuild : $msbuild"
        & $msbuild $Solution /t:Rebuild /p:Configuration=$Configuration /p:Platform=$Platform /m /nologo /v:minimal *> $BuildLog
        $buildExit = $LASTEXITCODE
        Add-Note "msbuild exit code = $buildExit (expected 0)"

        # Only compiler (C####) and linker (LNK####) warnings count: those are
        # what /W4 + /WX is meant to make impossible.  MSBuild chatter (e.g. a
        # Clean step that could not delete an .exe still running from a manual
        # test) is reported below as a note instead of failing the gate.
        $warnings = @(Select-String -Path $BuildLog -Pattern ': warning (?:C|LNK)\d+' -ErrorAction SilentlyContinue)
        $otherWarnings = @(Select-String -Path $BuildLog -Pattern ': warning ' -ErrorAction SilentlyContinue) |
                         Where-Object { $_.Line -notmatch ': warning (?:C|LNK)\d+' }
        $errors   = @(Select-String -Path $BuildLog -Pattern ': error '   -ErrorAction SilentlyContinue)
        if ($warnings.Count -gt 0) {
            Add-Failure "$($warnings.Count) compiler warning(s) - /W4+/WX must make this impossible"
            $warnings | Select-Object -First 10 | ForEach-Object { Add-Note ('  warn: ' + $_.Line.Trim()) }
        }
        if ($errors.Count -gt 0) {
            Add-Failure "$($errors.Count) compiler error(s)"
            $errors | Select-Object -First 10 | ForEach-Object { Add-Note ('  err : ' + $_.Line.Trim()) }
        }
        if ($buildExit -ne 0) { Add-Failure "MSBuild exit code $buildExit (expected 0)" }
        if ($otherWarnings) {
            $otherWarnings | Select-Object -First 5 |
                ForEach-Object { Add-Note ('  msbuild: ' + $_.Line.Trim()) }
        }
    }
}

# --- 3/4/5: artifacts + import allowlists ----------------------------------
$dumpbin = Find-Dumpbin
if (-not $dumpbin) { Add-Failure 'dumpbin.exe not found (MSVC toolset / Windows Kits)' }
else { Add-Note "dumpbin : $dumpbin" }

foreach ($artifact in ($AllowList.Keys | Sort-Object)) {
    $full = Join-Path $RepoRoot $artifact
    if (-not (Test-Path $full)) { Add-Failure "missing artifact: $artifact"; continue }

    $length = (Get-Item $full).Length
    if ($length -le 0) { Add-Failure "empty artifact: $artifact"; continue }
    Add-Note "artifact: $artifact ($length bytes)"

    if (-not $dumpbin) { continue }

    $machine = & $dumpbin /nologo /headers $full 2>&1 |
               Select-String -Pattern 'machine \(x64\)' -ErrorAction SilentlyContinue
    if (-not $machine) { Add-Failure "$artifact is not x64" }

    $actual  = @(Get-StaticImports $dumpbin $full | Sort-Object -Unique)
    $allowed = @($AllowList[$artifact] | Sort-Object -Unique)

    $extra   = @($actual  | Where-Object { $allowed -notcontains $_ })
    $missing = @($allowed | Where-Object { $actual  -notcontains $_ })

    if ($extra.Count -eq 0 -and $missing.Count -eq 0) {
        Add-Note "IAT OK  : $artifact == { $($allowed -join ', ') }"
    } else {
        if ($extra.Count -gt 0)   { Add-Failure "$artifact has UNEXPECTED imports: $($extra -join ', ')" }
        if ($missing.Count -gt 0) { Add-Failure "$artifact is MISSING allowed imports: $($missing -join ', ')" }
    }
    Add-Note "IAT set : $artifact actual = { $($actual -join ', ') }"
}
# --- 6: no dead symbols (CODE only; comment mentions are notes) ------------
$sourceDirs = @('src', 'include', 'launcher', 'driver', 'tools') |
               ForEach-Object { Join-Path $RepoRoot $_ } |
               Where-Object { Test-Path $_ }

function Get-CodeOccurrences([string] $pattern, [string[]] $files) {
    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($file in $files) {
        $text = Get-Content $file -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrEmpty($text)) { continue }
        # Strip block comments, then line comments.  Approximation: a "//" inside
        # a string literal would be treated as a comment - good enough for a
        # guardrail, and the safe direction (fewer false failures).
        $code = [regex]::Replace($text, '/\*.*?\*/', '', 'Singleline')
        $code = [regex]::Replace($code, '//[^\r\n]*', '')
        $lines = $code -split "`r?`n"
        for ($i = 0; $i -lt $lines.Length; ++$i) {
            if ($lines[$i] -match $pattern) {
                $hits.Add((Split-Path -Leaf $file) + ':' + ($i + 1) + '  ' + $lines[$i].Trim())
            }
        }
    }
    return $hits
}

$sourceFiles = @(Get-ChildItem $sourceDirs -Recurse -Include '*.cpp', '*.h', '*.c' -ErrorAction SilentlyContinue |
                 ForEach-Object { $_.FullName })

$deadSymbols = @(
    @{ Pattern = 'QwenKernPremium'; Why = 'dead class deleted in PHASE 0.1' },
    @{ Pattern = 'g_pCheat\b';      Why = 'dead global deleted in PHASE 0.1' }
)

foreach ($symbol in $deadSymbols) {
    $hits = @(Get-CodeOccurrences $symbol.Pattern $sourceFiles)
    if ($hits.Count -gt 0) {
        Add-Failure "dead symbol in code: '$($symbol.Pattern)' ($($symbol.Why))"
        $hits | Select-Object -First 5 | ForEach-Object { Add-Note ('  ' + $_) }
    } else {
        Add-Note "symbol  : no '$($symbol.Pattern)' in code (OK)"
    }
}

# --- 7: companion driver (checked only when it has been built) --------------
# driver\apexdrv.vcxproj is NOT in the solution on purpose: it needs the WDK,
# which is a separate install, and a missing WDK must not turn a green usermode
# gate red.  When the artifact does exist it gets the same treatment as the
# others, so a user-mode DLL renamed to .sys or a stale 32-bit build cannot pass.
$driverArtifact = Join-Path $RepoRoot 'build\apexdrv.sys'
if (-not (Test-Path $driverArtifact)) {
    Add-Note 'driver: build\apexdrv.sys absent (WDK not installed?) - B3 rung SKIPs'
} else {
    $driverLength = (Get-Item $driverArtifact).Length
    if ($driverLength -le 0) {
        Add-Failure 'empty artifact: build\apexdrv.sys'
    } else {
        Add-Note "artifact: build\apexdrv.sys ($driverLength bytes)"
        $driverSignature = Get-AuthenticodeSignature $driverArtifact
        Add-Note "driver: signature = $($driverSignature.Status) (must be Valid for the loader)"
        if ($dumpbin) {
            $driverMachine = & $dumpbin /nologo /headers $driverArtifact 2>&1 |
                             Select-String -Pattern 'machine \(x64\)' -ErrorAction SilentlyContinue
            if (-not $driverMachine) { Add-Failure 'build\apexdrv.sys is not x64' }

            $driverImports = @(Get-StaticImports $dumpbin $driverArtifact)
            if ($driverImports -notcontains 'ntoskrnl.exe') {
                Add-Failure "build\apexdrv.sys does not import ntoskrnl.exe (imports: $($driverImports -join ', '))"
            } else {
                Add-Note "driver: ntoskrnl.exe import present (foreign deps: $($driverImports.Count - 1))"
            }
        }
    }
}

# --- verdict ---------------------------------------------------------------
$gate = if ($Failures.Count -eq 0) { 'PASS' } else { 'FAIL' }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('================================================================================')
$lines.Add("BUILD GATE REPORT - $Configuration|$Platform - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add('================================================================================')
$lines.Add("verdict: $gate  ($($Failures.Count) failure(s))")
$lines.Add('')
$lines.Add('checks:')
foreach ($note in $Notes) { $lines.Add('  [ok] ' + $note) }
if ($Failures.Count -gt 0) {
    $lines.Add('')
    $lines.Add('failures:')
    foreach ($failure in $Failures) { $lines.Add('  [!!] ' + $failure) }
}
$lines.Add('')
$lines.Add('gate criteria: rebuild EXIT=0; warnings 0; IAT == allowlist; x64; no dead symbols;')
$lines.Add('               if present, apexdrv.sys is x64 with an ntoskrnl.exe import.')
$lines.Add('================================================================================')
$lines | Set-Content -Encoding utf8 $Report

Write-Host ''
foreach ($note in $Notes)       { Write-Host ('  [ok] ' + $note) }
foreach ($failure in $Failures) { Write-Host ('  [!!] ' + $failure) -ForegroundColor Red }
Write-Host ''
Write-Host "GATE 0: $gate   (report: $Report)" -ForegroundColor $(if ($gate -eq 'PASS') { 'Green' } else { 'Red' })

exit $(if ($gate -eq 'PASS') { 0 } else { 1 })
