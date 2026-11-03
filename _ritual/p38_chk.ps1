# ============================================================================
# p38_chk.ps1 - is the 64 KiB read REAL beyond its first page? (read-only)
#
# p38's clean 29.5 GB scan found ONE self-referencing page, which is the rate
# you get from random data.  Before blaming the predicate again, prove the read
# path per offset: a 64 KiB read is compared with fresh single-page reads at
# +0 / +0x4000 / +0xC000 and then repeated.  A driver that succeeds while
# copying only one page would make every bulk scan garbage.
# Plus a zero-ratio sample (degraded calls hide as all-zero chunks).
# Fire via p38_chk_task.ps1 (SYSTEM).  Nothing is written.
# ============================================================================
$ErrorActionPreference = 'Continue'
$OUT = Join-Path $PSScriptRoot 'p38_chk.txt'
$CS  = Join-Path $PSScriptRoot 'p38_prov.cs'
function Log([string]$s) { Add-Content -LiteralPath $OUT -Value $s -Encoding UTF8; Write-Host $s }

Set-Content -LiteralPath $OUT -Value ("=== p38 CHUNK-INTEGRITY CHECK {0} ===" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss')) -Encoding UTF8
try { Add-Type -Path $CS -EA Stop } catch { Log ('  !! cs compile FAIL: ' + $_.Exception.Message); exit 1 }
Log '  cs compiled'

$ramTop = [uint64]0
try { $ramTop = [uint64](Get-CimInstance Win32_ComputerSystem -EA Stop).TotalPhysicalMemory } catch { $ramTop = [uint64]0 }
if ($ramTop -eq 0) { $ramTop = [uint64]0x800000000 }
$ramRanges = ''
try { $ramRanges = [P38Prov]::RamRangesFromRegistry() } catch { $ramRanges = 'native-exc' }
if ($ramRanges -match '^(open|query|read|short|no-memory|native-exc)') { $ramRanges = '' }
[P38Prov]::SetRamRanges($ramRanges, $ramTop)
Log ("  ramTop=0x{0:x} ranges={1}" -f $ramTop, $(if ($ramRanges -eq '') { 'EMPTY' } else { $ramRanges }))

$g = [IntPtr]::Zero
$eo = [P38Prov]::GdrvOpen([ref]$g)
if ($eo -ne '') { Log ("  G0 open FAIL {0}" -f $eo); '-- p38_chk ABORT (no device) --' | Add-Content -LiteralPath $OUT -Encoding UTF8; exit 1 }
Log ("  G0 handle=0x{0:x}" -f $g.ToInt64())

# canary first: the two pages p37/p38 already read successfully
Log ("  canary 0x1000 = {0}" -f [P38Prov]::Hex([P38Prov]::GdrvProbe($g, [uint64]0x1000, 16)))

Log ''
Log '## per-offset integrity (mism=0 on every offset keeps 64 KiB chunks legal) ##'
$pas = [uint64[]]@(0x100000, 0x2000000, 0x10000000, 1GB, 2GB, 8GB, 16GB, 24GB, 30GB, 34000000000)
foreach ($ln in ([P38Prov]::ChunkIntegrity($g, $pas) -split "`r`n")) { if ($ln -ne '') { Log $ln } }

Log ''
Log '## zero-ratio samples (all-zero chunks in a 16 MB run) ##'
Log ([P38Prov]::ZeroSample($g, [uint64]0x20000000, 64, [uint64]0x10000).TrimEnd())
Log ("  issued={0} lastErr={1} h1450={2}" -f [P38Prov]::Issued, [P38Prov]::LastErr, [P38Prov]::Last1450)

Log ''
Log '## 1450 taxonomy - handle A ##'
Log ([P38Prov]::CallTest($g, [uint64]0x20100000, 0x10000, 10, [uint64]0x10000).TrimEnd())
Log ([P38Prov]::CallTest($g, [uint64]0x10100000, 0x10000, 10, [uint64]0x10000).TrimEnd())
Log ([P38Prov]::CallTest($g, [uint64]0x20100000, 0x1000, 10, [uint64]0x1000).TrimEnd())
Log ("  A totals: issued={0} h1450={1}" -f [P38Prov]::Issued, [P38Prov]::Last1450)

try { [P38Prov]::CloseHandle2($g) | Out-Null } catch { }
$g = [IntPtr]::Zero
$eo = [P38Prov]::GdrvOpen([ref]$g)
Log ('' + '## fresh handle B: ' + $(if ($eo -eq '') { ('0x{0:x}' -f $g.ToInt64()) } else { 'OPEN FAIL ' + $eo }) + ' ##')
if ($eo -eq '') {
    Log ([P38Prov]::CallTest($g, [uint64]0x20100000, 0x10000, 10, [uint64]0x10000).TrimEnd())
    Log ([P38Prov]::CallTest($g, [uint64]0x10100000, 0x10000, 10, [uint64]0x10000).TrimEnd())
    Log ([P38Prov]::CallTest($g, [uint64]0x20100000, 0x1000, 10, [uint64]0x1000).TrimEnd())
    Log ([P38Prov]::ZeroSample($g, [uint64]0x20000000, 64, [uint64]0x10000).TrimEnd())
}
Log ("  B totals: issued={0} h1450={1}" -f [P38Prov]::Issued, [P38Prov]::Last1450)
'-- p38_chk END --' | Add-Content -LiteralPath $OUT -Encoding UTF8
try { [P38Prov]::CloseHandle2($g) | Out-Null } catch { }
