<#
  tools\pe_tls.ps1 - READ-ONLY PE inspection for the manual-map gates.

  Prints only facts the mapper must care about:
    - DllCharacteristics (GUARD_CF / CET change what the driver must support)
    - TLS directory: raw data range, AddressOfIndex, callback array, ZeroFill
    - load config: GuardFlags + SecurityCookie, so "no CFG" is recorded, not guessed

  Usage: powershell -ExecutionPolicy Bypass -File tools\pe_tls.ps1 -Path build\apexcheat.dll
  Exit codes: 0 = parsed, 1 = not a PE64 DLL.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Path
)

$ErrorActionPreference = 'Stop'

function Fail([string] $message) {
    Write-Output "PE_TLS_VERDICT: PARSE_FAIL $message"
    exit 1
}

$full = (Resolve-Path -LiteralPath $Path).Path
$bytes = [System.IO.File]::ReadAllBytes($full)
$len = $bytes.Length

if ($len -lt 0x100 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { Fail 'no MZ' }
$lfanew = [BitConverter]::ToUInt32($bytes, 0x3C)
if ($lfanew + 0x60 -gt $len -or
    [BitConverter]::ToUInt32($bytes, $lfanew) -ne 0x00004550) { Fail 'no PE' }

$nt = $lfanew + 4
$machine = [BitConverter]::ToUInt16($bytes, $nt)
$numSect = [BitConverter]::ToUInt16($bytes, $nt + 2)
$optSize = [BitConverter]::ToUInt16($bytes, $nt + 16)
$chars   = [BitConverter]::ToUInt16($bytes, $nt + 18)
$opt     = $nt + 20

if ($machine -ne 0x8664) { Fail ('machine 0x{0:X4} not x64' -f $machine) }
if (-not ($chars -band 0x2000)) { Fail 'not a DLL (IMAGE_FILE_DLL clear)' }
if ($optSize -lt 0x70) { Fail 'optional header too small' }

$magic = [BitConverter]::ToUInt16($bytes, $opt)
if ($magic -ne 0x20B) { Fail ('magic 0x{0:X3X} not PE32+' -f $magic) }

$imageBase = [BitConverter]::ToUInt64($bytes, $opt + 0x18)
$imageSize = [BitConverter]::ToUInt32($bytes, $opt + 0x38)
$dllChars  = [BitConverter]::ToUInt16($bytes, $opt + 0x46)
$numDirs   = [BitConverter]::ToUInt32($bytes, $opt + 0x6C)
$dirBase   = $opt + 0x70

# --- section table: RVA -> raw offset ---
$sectOff = $opt + $optSize
$sections = @()
for ($i = 0; $i -lt $numSect; ++$i) {
    $s = $sectOff + $i * 40
    if ($s + 40 -gt $len) { Fail 'section table past EOF' }
    $sections += [pscustomobject]@{
        Name = [Text.Encoding]::ASCII.GetString($bytes, $s, 8).Trim([char]0)
        VSize = [BitConverter]::ToUInt32($bytes, $s + 8)
        VAddr = [BitConverter]::ToUInt32($bytes, $s + 12)
        RSize = [BitConverter]::ToUInt32($bytes, $s + 16)
        RPtr  = [BitConverter]::ToUInt32($bytes, $s + 20)
    }
}

function Convert-RvaToOffset([UInt32] $rva) {
    foreach ($s in $sections) {
        if ($rva -ge $s.VAddr -and $rva -lt ($s.VAddr + [Math]::Max($s.VSize, $s.RSize))) {
            $delta = $rva - $s.VAddr
            if ($delta -ge $s.RSize) { return $null }   # virtual-only tail
            return [int64]($s.RPtr + $delta)
        }
    }
    return $null
}

function Read-RvaU64([UInt32] $rva) {
    $off = Convert-RvaToOffset $rva
    if ($null -eq $off -or $off + 8 -gt $len) { return $null }
    return [BitConverter]::ToUInt64($bytes, [int]$off)
}

"file            : $full"
"size            : $len"
"image base      : 0x{0:X}" -f $imageBase
"image size      : 0x{0:X}" -f $imageSize
"DllCharacteristics: 0x{0:X4}" -f $dllChars
foreach ($bit in @(
        @(0x0020, 'HIGH_ENTROPY_VA'), @(0x0040, 'DYNAMIC_BASE'),
        @(0x0100, 'NX_COMPAT'), @(0x0200, 'NO_SEH'),
        @(0x0400, 'NO_BIND'), @(0x0800, 'APPCONTAINER'),
        @(0x1000, 'WDM_DRIVER'), @(0x2000, 'GUARD_CF'),
        @(0x4000, 'TERMINAL_SERVER_AWARE'))) {
    if ($dllChars -band $bit[0]) { "  set: $($bit[1])" }
}

# --- TLS directory (data directory 9) ---
$tlsRva = 0; $tlsSize = 0
if ($numDirs -gt 9) {
    $tlsRva  = [BitConverter]::ToUInt32($bytes, $dirBase + 9 * 8)
    $tlsSize = [BitConverter]::ToUInt32($bytes, $dirBase + 9 * 8 + 4)
}
"tls directory : rva=0x{0:X} size=0x{1:X}" -f $tlsRva, $tlsSize

$callbacks = @()
$rawSize = 0
$zero = 0
if ($tlsRva -ne 0 -and $tlsSize -ge 0x28) {
    $tlsOff = Convert-RvaToOffset $tlsRva
    $start  = Read-RvaU64 $tlsRva
    $end    = Read-RvaU64 ($tlsRva + 8)
    $index  = Read-RvaU64 ($tlsRva + 0x10)
    $cbs    = Read-RvaU64 ($tlsRva + 0x18)
    if ($null -ne $tlsOff) {
        $zero   = [BitConverter]::ToUInt32($bytes, [int]($tlsOff + 0x20))
        $tlsChr = [BitConverter]::ToUInt32($bytes, [int]($tlsOff + 0x24))
        "  tls flags   : 0x{0:X}" -f $tlsChr
    }
    if ($null -ne $start -and $null -ne $end -and $end -gt $start) {
        $rawSize = [UInt64]($end - $start)
    }
    "  raw data    : 0x{0:X} .. 0x{1:X} (0x{2:X} bytes)" -f $start, $end, $rawSize
    "  index ptr   : 0x{0:X}" -f $index
    "  callbacks   : 0x{0:X}" -f $cbs
    "  zero fill   : 0x{0:X}" -f $zero

    if ($cbs -ne 0) {
        $arrRva = [UInt32]($cbs - $imageBase)
        for ($k = 0; $k -lt 16; ++$k) {
            $entry = Read-RvaU64 ([UInt32]($arrRva + $k * 8))
            if ($null -eq $entry -or $entry -eq 0) { break }
            $callbacks += [UInt64]$entry
        }
        if ($callbacks.Count -eq 0) {
            '  callback[0] : null (array present, empty)'
        } else {
            for ($k = 0; $k -lt $callbacks.Count; ++$k) {
                '  callback[{0}] : 0x{1:X} (rva 0x{2:X})' -f $k, $callbacks[$k],
                    ([UInt64]($callbacks[$k] - $imageBase))
            }
        }
    }
} else {
    '  (no TLS directory)'
}

# --- load config (data directory 10): GuardFlags + cookie ---
$lcRva = 0; $lcSize = 0
if ($numDirs -gt 10) {
    $lcRva  = [BitConverter]::ToUInt32($bytes, $dirBase + 10 * 8)
    $lcSize = [BitConverter]::ToUInt32($bytes, $dirBase + 10 * 8 + 4)
}
"load config   : rva=0x{0:X} size=0x{1:X}" -f $lcRva, $lcSize
$guardFlags = 0
if ($lcRva -ne 0 -and $lcSize -ge 0xA0) {
    $lcOff = Convert-RvaToOffset $lcRva
    if ($null -ne $lcOff) {
        # IMAGE_LOAD_CONFIG_DIRECTORY64: SecurityCookie 0x58, GuardFlags 0x90.
        $cookie = [BitConverter]::ToUInt64($bytes, [int]($lcOff + 0x58))
        $guardFlags = [BitConverter]::ToUInt32($bytes, [int]($lcOff + 0x90))
        '  security cookie : 0x{0:X}' -f $cookie
        '  guard flags     : 0x{0:X}' -f $guardFlags
        foreach ($bit in @(
                @(0x0100, 'CF_INSTRUMENTED'), @(0x0200, 'CFW_INSTRUMENTED'),
                @(0x0400, 'CF_FUNCTION_TABLE_PRESENT'), @(0x0800, 'SECURITY_COOKIE_UNUSED'),
                @(0x1000, 'PROTECT_DELAYLOAD_IAT'), @(0x2000, 'DELAYLOAD_IAT_IN_ITS_OWN_SECTION'),
                @(0x4000, 'CF_EXPORT_SUPPRESSION_INFO_PRESENT'), @(0x10000, 'CF_LONGJUMP_TABLE_PRESENT'))) {
            if ($guardFlags -band $bit[0]) { "    set: $($bit[1])" }
        }
    }
}

$bits = @()
if ($callbacks.Count -gt 0) { $bits += "tls_callbacks=$($callbacks.Count)" }
if ($rawSize -gt 0 -or $zero -gt 0) { $bits += 'tls_data' }
if ($guardFlags -band 0x0400) { $bits += 'guard_table' }
if ($guardFlags -band 0x0100) { $bits += 'guard_instrumented' }
if ($bits.Count -eq 0) { $bits += 'none' }
'PE_TLS_VERDICT: parsed ' + ($bits -join ' ')
exit 0
