# ============================================================================
# _ritual\h282_expect.ps1 - host-only byte parser. Precomputes the numbers a
# later probe (h283) will compare against, straight out of the PE headers.
# Nothing is loaded, nothing is executed, the input file is only READ.
#
# This is the oracle half of the map rung: h281 proved a mapped image can be
# handed a DllMain call, so the next question is whether a map of the REAL
# payload comes out with the same import/reloc/TLS shape the linker recorded.
# That comparison is worthless without an independent count taken on the host,
# which is what this script produces. Same reason the guest side gets an
# oracle file: a number produced by the same code under test proves nothing.
#
# Hard facts that make the parse unambiguous:
#   - PE32+ (magic 0x20B) and machine 0x8664 only; anything else aborts, because
#     a 32-bit image has 4-byte thunks and different optional-header offsets.
#   - Data directories live in the optional header; index i is at +0x70+8*i.
#     So reloc (index 5) is +0x98/+0x9C, TLS (9) is +0xB8/+0xBC, LoadConfig
#     (10) is +0xC0/+0xC4 - and the IMPORT dir (index 1) is +0x78/+0x7C.
#     NOTE: +0x80/+0x84 is index 2 (RESOURCES), not the import directory. The
#     resource pair sits right next to the import pair and reads as plausible
#     RVAs, so it is the easy off-by-one to make here.
#   - Ordinals are the high bit of the thunk plus the low 16 bits; everything
#     else is an RVA to IMAGE_IMPORT_BY_NAME (Hint WORD at +0, name at +2).
#
# Usage:  powershell -ExecutionPolicy Bypass -File _ritual\h282_expect.ps1 -Path <pe>
# Output: _ritual\h282_expected.txt (override with -Out) AND stdout.
#         First line = input path + SHA-256.
# ============================================================================
[CmdletBinding()]
param(
    [string] $Path = 'QwenKernPremium\build\apexcheat.dll',
    [string] $Out
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not [IO.Path]::IsPathRooted($Path)) { $Path = Join-Path $RepoRoot $Path }
if (-not $Out) { $Out = Join-Path $RepoRoot '_ritual\h282_expected.txt' }
$Out = [IO.Path]::GetFullPath($Out)

$L = New-Object System.Collections.ArrayList
function W([string]$s) { [void]$L.Add($s) }

function Emit {
    $text = $L -join "`r`n"
    Set-Content -LiteralPath $Out -Value $text -Encoding ascii
    Write-Host $text
}
function Abort([string]$msg) {
    W ('ABORT ' + $msg)
    Emit
    exit 1
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Abort ('input missing: ' + $Path) }
$full = (Resolve-Path -LiteralPath $Path).Path
$sha  = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
$B    = [IO.File]::ReadAllBytes($full)
W ($full + ' sha256=' + $sha + ' bytes=' + $B.Length)

# --- raw readers, all bounds-checked (PS array indexes go $null, not throw) ---
# BitConverter is used for the multi-byte reads: in PS 5.1 [uint64]<negative int64>
# THROWS, so the usual byte-shift accumulator blows up on any value with bit 63 set
# (i.e. an ordinal thunk, or e_lfanew-sized nonsense).
function U16([int64]$o) {
    if ($o -lt 0 -or ($o + 2) -gt $B.Length) { return -1 }
    return [int][BitConverter]::ToUInt16($B, [int]$o)
}
function U32([int64]$o) {
    if ($o -lt 0 -or ($o + 4) -gt $B.Length) { return [int64]-1 }
    return [int64][BitConverter]::ToUInt32($B, [int]$o)
}
function U64([int64]$o) {
    if ($o -lt 0 -or ($o + 8) -gt $B.Length) { return [uint64]::MaxValue }
    return [BitConverter]::ToUInt64($B, [int]$o)
}
# the 0x80.. literal itself parses as a negative Int64 in 5.1, so it is cast once here
$HiBit = [uint64]9223372036854775808
function Hex32([int64]$v) { if ($v -lt 0) { return '?' } ; return ('0x' + ([uint32]$v).ToString('X8')) }
function Hex64([uint64]$v) { return ('0x' + $v.ToString('X')) }
# ASCII C string at a FILE offset, capped
function CStr([int64]$o, [int]$max = 256) {
    if ($o -lt 0 -or $o -ge $B.Length) { return '<unmapped>' }
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $max -and ($o + $i) -lt $B.Length; $i++) {
        $c = $B[$o + $i]
        if ($c -eq 0) { break }
        if ($c -lt 0x20 -or $c -gt 0x7E) { [void]$sb.Append('.') } else { [void]$sb.Append([char]$c) }
    }
    if ($sb.Length -eq 0) { return '<empty>' }
    return $sb.ToString()
}

# --- header gate -------------------------------------------------------------
if ($B.Length -lt 0x40 -or $B[0] -ne 0x4D -or $B[1] -ne 0x5A) { Abort 'no MZ at 0' }
$lfanew = U32 0x3C
if ($lfanew -lt 0 -or ($lfanew + 0x18 + 4) -gt $B.Length) { Abort ('e_lfanew out of file: ' + $lfanew) }
if ($B[$lfanew] -ne 0x50 -or $B[$lfanew + 1] -ne 0x45 -or $B[$lfanew + 2] -ne 0 -or $B[$lfanew + 3] -ne 0) {
    Abort ('no PE\0\0 signature at e_lfanew ' + (Hex32 $lfanew))
}
$opt    = $lfanew + 0x18
$magic  = U16 $opt
if ($magic -ne 0x20B) { Abort ('optional header magic ' + (Hex32 $magic) + ' is not PE32+ (0x20B)') }
$machine = U16 ($lfanew + 4)
if ($machine -ne 0x8664) { Abort ('machine ' + (Hex32 $machine) + ' is not x64 (0x8664)') }
$sizeOfOptHdr = U16 ($lfanew + 0x14)
$sectCount    = U16 ($lfanew + 6)
$sectTable    = $opt + $sizeOfOptHdr
if ($sectCount -lt 0 -or ($sectTable + ($sectCount * 40)) -gt $B.Length) { Abort ('section table out of file (count=' + $sectCount + ')') }

# section table -> rva mapping (virtual range, capped by raw data)
$Secs = @()
for ($i = 0; $i -lt $sectCount; $i++) {
    $s = $sectTable + ($i * 40)
    $vs = U32 ($s + 8); $va = U32 ($s + 12); $rs = U32 ($s + 16); $pr = U32 ($s + 20)
    $span = [Math]::Max($vs, $rs)
    $Secs += [pscustomobject]@{ Name = (CStr $s 8); VA = $va; Span = $span; Raw = $pr; RawSize = $rs }
}
function Rva2Off([int64]$rva) {
    if ($rva -lt 0) { return [int64]-1 }
    foreach ($s in $Secs) {
        if ($rva -ge $s.VA -and $rva -lt ($s.VA + $s.Span)) {
            $off = $rva - $s.VA + $s.Raw
            if ($s.Raw -eq 0 -or $off -ge $B.Length) { return [int64]-1 }
            return $off
        }
    }
    # headers are mapped 1:1 for the first SizeOfHeaders bytes
    $sizeOfHeaders = U32 ($opt + 0x3C)
    if ($rva -lt $sizeOfHeaders -and $rva -lt $B.Length) { return $rva }
    return [int64]-1
}

$imageSize = U32 ($opt + 0x38)
$entryRva  = U32 ($opt + 0x10)
$prefBase  = U64 ($opt + 0x18)

# --- data directories (index i at +0x70 + 8*i) --------------------------------
$dirReloc = 5;  $dirImp = 1;  $dirTls = 9;  $dirLc = 10
function DirRva([int]$i)  { return (U32 ($opt + 0x70 + (8 * $i))) }
function DirSize([int]$i) { return (U32 ($opt + 0x74 + (8 * $i))) }

# --- 3. imports ---------------------------------------------------------------
$impRva = DirRva $dirImp; $impSize = DirSize $dirImp
$impCount = 0; $impNames = New-Object System.Collections.ArrayList; $impNotes = New-Object System.Collections.ArrayList
$truncated = $false
if ($impRva -le 0 -or $impSize -le 0) {
    W ('import_dir=absent rva=' + (Hex32 $impRva) + ' size=' + (Hex32 $impSize))
} else {
    W ('import_dir_rva=' + (Hex32 $impRva) + ' size=' + (Hex32 $impSize))
    $impOff = Rva2Off $impRva
    if ($impOff -lt 0) {
        [void]$impNotes.Add('import dir RVA does not map to a section (rva=' + (Hex32 $impRva) + ')')
    } else {
        $d = $impOff
        $di = 0
        while ($true) {
            if ($di -gt 4096) { [void]$impNotes.Add('descriptors TRUNCATED at 4096'); break }
            if (($d + 20) -gt $B.Length) { [void]$impNotes.Add('descriptor table runs past EOF'); break }
            $nameRva = U32 ($d + 0xC); $oft = U32 $d; $ft = U32 ($d + 0x10)
            if ($nameRva -eq 0 -and $oft -eq 0 -and $ft -eq 0) { break }
            $dll = '<no name>'
            if ($nameRva -le 0) {
                [void]$impNotes.Add('descriptor ' + $di + ' has name RVA ' + (Hex32 $nameRva))
            } else {
                $dll = CStr (Rva2Off $nameRva) 128
                # a name RVA inside the import dir's own range is the sign of a
                # forwarder-ish/odd table layout - call it out instead of trusting it
                if ($nameRva -ge $impRva -and $nameRva -lt ($impRva + $impSize)) {
                    [void]$impNotes.Add('descriptor ' + $di + ' name RVA ' + (Hex32 $nameRva) + ' points INSIDE the import dir range')
                }
            }
            $thunkRva = if ($oft -ne 0) { $oft } else { $ft }
            $useWhich = if ($oft -ne 0) { 'OFT' } else { 'FT' }
            $tOff = Rva2Off $thunkRva
            if ($tOff -lt 0) {
                [void]$impNotes.Add('descriptor ' + $di + ' (' + $dll + ') thunk ' + $useWhich + '=' + (Hex32 $thunkRva) + ' does not map')
            } else {
                $t = $tOff
                while ($true) {
                    if (($t + 8) -gt $B.Length) { [void]$impNotes.Add($dll + ': thunk array runs past EOF'); break }
                    $v = U64 $t
                    if ($v -eq 0) { break }
                    if ($impCount -ge 4096) { $truncated = $true; break }
                    if (($v -band $HiBit) -ne [uint64]0) {
                        W ('  ' + $dll + '!#' + ($v -band [uint64]0xFFFF))
                    } else {
                        $nameOff = Rva2Off ([int64]$v)
                        if ($nameOff -lt 0) {
                            W ('  ' + $dll + '!<unmapped rva ' + (Hex64 $v) + '>')
                            [void]$impNotes.Add($dll + ': thunk name RVA ' + (Hex64 $v) + ' does not map')
                        } else {
                            $hint = U16 $nameOff
                            W ('  ' + $dll + '!' + (CStr ($nameOff + 2) 128) + ' (hint=' + $hint + ')')
                        }
                    }
                    $impCount++
                    $t += 8
                }
                if ($truncated) { [void]$impNotes.Add('thunks TRUNCATED at 4096 (' + $dll + ')'); break }
            }
            $d += 20; $di++
        }
        if ($di -eq 0) { [void]$impNotes.Add('import dir present but the first descriptor is all-zero') }
    }
}
W ('imports=' + $impCount)
if ($truncated) { W 'TRUNCATED import thunk walk stopped at 4096' }
foreach ($n in $impNotes) { W ('import_note: ' + $n) }

# --- 4. relocations, DIR64 only ----------------------------------------------
$relRva = DirRva $dirReloc; $relSize = DirSize $dirReloc
$relCount = 0; $relBlocks = 0; $relNotes = New-Object System.Collections.ArrayList
if ($relRva -le 0 -or $relSize -le 0) {
    W ('reloc_dir=absent rva=' + (Hex32 $relRva) + ' size=' + (Hex32 $relSize))
} else {
    W ('reloc_dir_rva=' + (Hex32 $relRva) + ' size=' + (Hex32 $relSize))
    $o = Rva2Off $relRva
    if ($o -lt 0) {
        [void]$relNotes.Add('reloc dir RVA does not map to a section')
    } else {
        $end = $o + $relSize
        if ($end -gt $B.Length) { $end = $B.Length; [void]$relNotes.Add('reloc dir size clipped to EOF') }
        $p = $o
        while (($p + 8) -le $end) {
            $pageRva = U32 $p; $blockSize = U32 ($p + 4)
            if ($blockSize -lt 8) { [void]$relNotes.Add('block ' + $relBlocks + ' size ' + $blockSize + ' < 8, stop'); break }
            $bEnd = $p + $blockSize
            if ($bEnd -gt $end) { [void]$relNotes.Add('block ' + $relBlocks + ' runs past the dir end'); $bEnd = $end }
            $e = $p + 8
            while (($e + 2) -le $bEnd) {
                $ent = U16 $e
                if ($ent -gt 0 -and ([int](($ent -shr 12) -band 0xF)) -eq 10) { $relCount++ }
                $e += 2
            }
            $relBlocks++
            $p = $bEnd
        }
        if ($relBlocks -eq 0) { [void]$relNotes.Add('reloc dir present but no block parsed') }
    }
}
W ('relocs=' + $relCount)
foreach ($n in $relNotes) { W ('reloc_note: ' + $n) }

# --- 5. LoadConfig -----------------------------------------------------------
$lcRva = DirRva $dirLc; $lcSize = DirSize $dirLc
if ($lcRva -le 0 -or $lcSize -le 0) {
    W 'loadcfg=absent'
} else {
    W ('loadcfg_rva=' + (Hex32 $lcRva) + ' size=' + (Hex32 $lcSize))
    $lcOff = Rva2Off $lcRva
    if ($lcOff -lt 0) {
        W 'securitycookie_field=<unmapped>'
    } else {
        # +0x58 is a full VA in IMAGE_LOAD_CONFIG_DIRECTORY64; a 4-byte read here
        # truncates 0x18004E0C0 to 0x8004E0C0 and reads like an RVA.
        $cookie = U64 ($lcOff + 0x58)
        W ('securitycookie_field=' + (Hex64 $cookie) + ' struct_size=' + (Hex32 (U32 ($lcOff + 0))))
        if ($cookie -gt 0 -and $prefBase -gt 0 -and $cookie -ge $prefBase) {
            W ('securitycookie_rva=' + (Hex32 ($cookie - $prefBase)))
        } elseif ($cookie -gt 0) {
            W ('securitycookie_rva=' + (Hex32 $cookie) + ' (already an RVA, below preferred base)')
        }
    }
}

# --- 6. TLS ----------------------------------------------------------------
$tlsRva = DirRva $dirTls; $tlsSize = DirSize $dirTls
if ($tlsRva -le 0 -or $tlsSize -le 0) {
    W 'tls=absent'
} else {
    W ('tls_dir_rva=' + (Hex32 $tlsRva) + ' size=' + (Hex32 $tlsSize))
    $tlsOff = Rva2Off $tlsRva
    if ($tlsOff -lt 0) {
        W 'tls_callbacks=<unmapped dir>'
    } else {
        $aoc = U64 ($tlsOff + 0x18)
        W ('tls_callbacks=' + (Hex64 $aoc))
        if ($aoc -eq 0) {
            W 'tls_cb_count=0 (null AddressOfCallBacks)'
        } elseif ($prefBase -gt 0 -and $aoc -ge $prefBase) {
            $cbOff = Rva2Off ([int64]($aoc - $prefBase))
            $n = 0; $truncCb = $false; $cbOk = $false
            while ($true) {
                if ($cbOff -lt 0 -or ($cbOff + 8) -gt $B.Length) { break }
                $p2 = U64 $cbOff
                $cbOk = $true
                if ($p2 -eq 0) { break }
                $n++
                if ($n -ge 64) { $truncCb = $true; break }
                $cbOff += 8
            }
            if (-not $cbOk) {
                W 'tls_cb_count=<unmapped>'
            } elseif ($truncCb) {
                W 'tls_cb_count=64 TRUNCATED at 64'
            } else {
                W ('tls_cb_count=' + $n)
                # A count of 0 under a NON-null AddressOfCallBacks is not "no TLS callbacks":
                # the linker can leave null padding in front of the array. Show the raw qwords
                # so the sibling probe compares bytes, not just the derived number.
                if ($n -eq 0 -and ($cbOff + 8) -le $B.Length) {
                    $q = @()
                    for ($k = 0; $k -lt 4; $k++) {
                        if (($cbOff + ($k * 8) + 8) -gt $B.Length) { break }
                        $q += (Hex64 (U64 ($cbOff + ($k * 8))))
                    }
                    if ($q.Count -gt 0) { W ('tls_note: first qwords at callbacks = ' + ($q -join ' ')) }
                }
            }
        } else {
            W ('tls_callbacks_rva=' + (Hex64 ([uint64]$aoc)) + ' (below preferred base, printed raw)')
        }
    }
}

# --- 7. header numbers -------------------------------------------------------
W ('imageSize=' + (Hex32 $imageSize) + ' dec=' + $imageSize)
W ('entryRva=' + (Hex32 $entryRva))
W ('sectioncount=' + $sectCount)
W ('preferredBase=' + (Hex64 $prefBase))
foreach ($s in $Secs) { W ('section: ' + $s.Name + ' va=' + (Hex32 $s.VA) + ' vsize=' + (Hex32 $s.Span) + ' raw=' + (Hex32 $s.Raw)) }

Emit
exit 0
