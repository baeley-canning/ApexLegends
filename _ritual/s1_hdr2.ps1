# ============================================================================
# _ritual\s1_hdr2.ps1 — Stage-1 support probe (read-only, no state changes).
# Question: does the INSTALLED WDK 10.0.26100.0 km/shared/um header set expose
# ANY VAD/EPROCESS surface, and which Stage-1 candidate APIs actually exist in
# ntoskrnl.lib (the build links /NODEFAULTLIB + ntoskrnl.lib only, so a symbol
# must either be declared in a header AND in the lib, or be hand-declared and
# resolved at runtime via MmGetSystemRoutineAddress).
# Writes _ritual\s1_hdr2.out (fresh file each run; stamps LASTWRITE).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File _ritual\s1_hdr2.ps1
# ============================================================================
$ErrorActionPreference = 'Continue'
$rt  = $PSScriptRoot
$out = Join-Path $rt 's1_hdr2.out'
$inc = 'C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0'
$lib = 'C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\km\x64\ntoskrnl.lib'
$L = New-Object System.Collections.Generic.List[string]
function S([string]$t) { $L.Add($t) }

S ("S1 HDR2  " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
S ("inc: " + $inc + "   (exists=" + (Test-Path $inc) + ")")
S ("lib: " + $lib + "   (exists=" + (Test-Path $lib) + ")")

$dirs = 'km','km\crt','shared','um'
$patterns = @(
  'VadRoot','RTL_AVL_TREE','_MMVAD','MmGetNextVadNode',
  'PsGetProcessSectionBaseAddress','PsGetProcessImageFileName',
  'ZwQueryVirtualMemory','NtQueryVirtualMemory','RtlGetVersion','RtlAvl',
  'MmCopyMemory','typedef struct _EPROCESS','struct _EPROCESS','KPROCESS','PsGetProcessPeb')

$files = @()
foreach ($d in $dirs) {
    $p = Join-Path $inc $d
    if (Test-Path $p) {
        $files += @(Get-ChildItem -LiteralPath $p -Filter *.h -File -Recurse -ErrorAction SilentlyContinue)
    }
}
S ("header files scanned: " + $files.Count)

# one pass, all patterns, then group by matched pattern
$all = @($files | Select-String -SimpleMatch -Pattern $patterns -ErrorAction SilentlyContinue)
S ("total match rows: " + $all.Count)
foreach ($pat in $patterns) {
    S ''
    S ("=== PAT[s] " + $pat + " ===")
    $hits = @($all | Where-Object { $_.Pattern -eq $pat })
    S ("hits: " + $hits.Count)
    $hits | Select-Object -First 25 | ForEach-Object {
        S ("  " + (Split-Path -Leaf $_.Path) + ":" + $_.LineNumber + "  " + $_.Line.Trim())
    }
    if ($hits.Count -gt 25) { S ("  ... +" + ($hits.Count - 25) + " more") }
}

S ''
S '=== ntddk.h L5540..5650 — the UniqueProcessId anchor: which struct is this? ==='
$f = Join-Path $inc 'km\ntddk.h'
if (Test-Path $f) {
    $ls = @(Get-Content -LiteralPath $f)
    for ($i = 5539; $i -lt [Math]::Min(5650, $ls.Count); $i++) { S ("L" + ($i + 1) + ": " + $ls[$i]) }
    S ''
    S '=== every "struct _EPROCESS" site in ntddk.h (line numbers only) ==='
    foreach ($m in (Select-String -LiteralPath $f -Pattern 'struct _EPROCESS' -SimpleMatch)) {
        S ("@" + $m.LineNumber + ": " + $m.Line.Trim())
    }
    $m = Select-String -LiteralPath $f -Pattern 'typedef struct _EPROCESS {' -SimpleMatch | Select-Object -First 1
    if ($m) {
        S '=== first typedef site + 24 lines of context ==='
        for ($i = $m.LineNumber - 1; $i -lt [Math]::Min($m.LineNumber + 24, $ls.Count); $i++) { S ("   " + $ls[$i]) }
    }
} else {
    S 'ntddk.h missing'
}

S ''
S '=== ntoskrnl.lib: which candidate symbols exist? (dumpbin /linkermember:1) ==='
$db = Get-ChildItem 'C:\BuildTools\VC\Tools\MSVC','C:\Program Files\Microsoft Visual Studio','C:\Program Files (x86)\Microsoft Visual Studio' -Recurse -Filter dumpbin.exe -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match 'Hostx64\\x64' } | Select-Object -Last 1
if ($db -and (Test-Path $lib)) {
    S ("dumpbin: " + $db.FullName)
    $dump = @(& $db.FullName /linkermember:1 $lib 2>$null)
    S ("linkermember lines: " + $dump.Count)
    foreach ($pat in 'Vad','QueryVirtualMemory','PsGetProcessSectionBaseAddress','PsGetProcessImageFileName','RtlGetVersion','MmCopyMemory','PsGetProcessPeb') {
        $h = @($dump | Select-String -Pattern $pat -SimpleMatch)
        S ("  " + $pat + " -> " + $h.Count + " hit(s)")
        $h | Select-Object -First 8 | ForEach-Object { S ("    " + $_.Line.Trim()) }
    }
} else {
    S ("  dumpbin missing=" + (-not $db) + "  lib missing=" + (-not (Test-Path $lib)))
}

S ''
S ("LASTWRITE " + (Get-Date -Format 'HH:mm:ss'))
S 'DONE'
$L | Set-Content -Encoding utf8 $out
Write-Host ("WROTE " + $out + " (" + $L.Count + " lines)")
