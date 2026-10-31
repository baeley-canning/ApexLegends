<#
pe_imports.ps1 - INDEPENDENT PE reader for static IAT / delay-import / dynamic-load
strings.  Written straight from the PE spec so it is a SECOND OPINION on the
import table: BuildGate.ps1 parses the same information with its own code, and
Phase 1.3 reference-integrity claims must not rest on a single implementation.

Usage:
  powershell -ExecutionPolicy Bypass -File tools\pe_imports.ps1 -Path a.exe,b.dll
  powershell -ExecutionPolicy Bypass -File tools\pe_imports.ps1 -Path x.dll -Strings
#>
param(
    [Parameter(Mandatory = $true)][string[]]$Path,
    [switch]$Strings
)

function Convert-RvaToOffset {
    param([byte[]]$Bytes, [int]$NumSections, [int]$SectionTableStart, [uint32]$Rva)
    for ($i = 0; $i -lt $NumSections; $i++) {
        $s    = $SectionTableStart + ($i * 40)
        $va   = [BitConverter]::ToUInt32($Bytes, $s + 12)
        $rsz  = [BitConverter]::ToUInt32($Bytes, $s + 16)
        $praw = [BitConverter]::ToUInt32($Bytes, $s + 20)
        if ($rsz -eq 0) { continue }
        if ($Rva -ge $va -and $Rva -lt ($va + $rsz)) { return [int]($praw + ($Rva - $va)) }
    }
    return -1
}

function Read-CString {
    param([byte[]]$Bytes, [int]$Offset)
    if ($Offset -lt 0 -or $Offset -ge $Bytes.Length) { return '' }
    $sb = New-Object System.Text.StringBuilder
    while ($Offset -lt $Bytes.Length -and $Bytes[$Offset] -ne 0 -and $sb.Length -lt 260) {
        [void]$sb.Append([char]$Bytes[$Offset]); $Offset++
    }
    return $sb.ToString()
}

function Invoke-PeImportScan {
    param([string]$File)

    Write-Output "---------------- $File ----------------"
    $b = [IO.File]::ReadAllBytes($File)
    if ($b.Length -lt 0x40) { Write-Output '  too small'; return }

    $pe = [BitConverter]::ToInt32($b, 0x3C)
    if ($b[$pe] -ne 0x50 -or $b[$pe + 1] -ne 0x45) { Write-Output '  no PE signature'; return }

    $machine    = [BitConverter]::ToUInt16($b, $pe + 4)
    $numSect    = [BitConverter]::ToUInt16($b, $pe + 6)
    $optSize    = [BitConverter]::ToUInt16($b, $pe + 20)
    $optStart   = $pe + 24
    $magic      = [BitConverter]::ToUInt16($b, $optStart)
    $ptrSize    = if ($magic -eq 0x20B) { 8 } else { 4 }
    $ddStart    = if ($magic -eq 0x20B) { $optStart + 112 } else { $optStart + 96 }
    $secTable   = $optStart + $optSize

    Write-Output ("  machine=0x{0:X4}  magic=0x{1:X4}  sections={2}  ptr={3}" -f $machine, $magic, $numSect, $ptrSize)

    # [1] import directory, [13] delay import directory
    foreach ($idx in 1, 13) {
        $rva  = [BitConverter]::ToUInt32($b, $ddStart + ($idx * 8))
        $size = [BitConverter]::ToUInt32($b, $ddStart + ($idx * 8) + 4)
        $kind = if ($idx -eq 1) { 'import' } else { 'delay-import' }
        Write-Output ("  [{0}] rva=0x{1:X8} size={2}" -f $kind, $rva, $size)
        if ($rva -eq 0) { continue }

        $off = Convert-RvaToOffset -Bytes $b -NumSections $numSect -SectionTableStart $secTable -Rva $rva
        if ($off -lt 0) { Write-Output '    (unmapped rva)'; continue }

        $step = if ($idx -eq 1) { 20 } else { 32 }
        $nameField = if ($idx -eq 1) { 12 } else { 4 }
        $thunkField = if ($idx -eq 1) { 16 } else { 16 }

        $count = 0
        for ($d = $off; ; $d += $step) {
            if ($d + $step -gt $b.Length) { break }
            $nameRva = [BitConverter]::ToUInt32($b, $d + $nameField)
            if ($nameRva -eq 0) { break }

            $nOff = Convert-RvaToOffset -Bytes $b -NumSections $numSect -SectionTableStart $secTable -Rva $nameRva
            $dll  = Read-CString -Bytes $b -Offset $nOff

            # count imported symbols via the thunk array (0-terminated)
            $thunkRva = [BitConverter]::ToUInt32($b, $d + $thunkField)
            $syms = 0
            if ($thunkRva -ne 0) {
                $tOff = Convert-RvaToOffset -Bytes $b -NumSections $numSect -SectionTableStart $secTable -Rva $thunkRva
                for ($t = $tOff; $t + $ptrSize -le $b.Length; $t += $ptrSize) {
                    $val = if ($ptrSize -eq 8) { [BitConverter]::ToUInt64($b, $t) } else { [BitConverter]::ToUInt32($b, $t) }
                    if ($val -eq 0) { break }
                    $syms++
                    if ($syms -gt 5000) { break }
                }
            }

            Write-Output ("    {0,-34} imports={1}" -f $dll, $syms)
            $count++
            if ($count -gt 200) { break }
        }
        Write-Output ("    => {0} module(s)" -f $count)
    }

    if ($Strings) {
        $text = [Text.Encoding]::ASCII.GetString($b)
        $pat = 'd3d11|d3d12|d3d9|dxgi|d3dcompiler|javelin|EAAntiCheat|EasyAntiCheat|start_protected_game'
        $hits = [regex]::Matches($text, "(?i)[A-Za-z0-9_\.\-]{0,40}($pat)[A-Za-z0-9_\.\-]{0,40}") |
                ForEach-Object { $_.Value } | Sort-Object -Unique
        Write-Output '  [load-string hits]'
        $hits | ForEach-Object { Write-Output "    $_" }
    }
}

# `powershell -File script.ps1 -Path a,b` hands "a,b" over as ONE string, so the
# list has to be re-split here.  (-Command would bind it correctly; -File does not.)
$targets = @()
foreach ($p in $Path) {
    foreach ($part in ($p -split ',')) {
        if ($part.Trim() -ne '') { $targets += $part.Trim() }
    }
}

foreach ($f in $targets) {
    if (Test-Path -LiteralPath $f) {
        Invoke-PeImportScan -File (Resolve-Path -LiteralPath $f).Path
    } else {
        Write-Output "---------------- $f ----------------"
        Write-Output '  MISSING'
    }
}
