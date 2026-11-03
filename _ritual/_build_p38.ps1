# one-shot builder for p38_read.ps1 (kept for audit; safe to re-run)
$r = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$src = Get-Content -LiteralPath (Join-Path $r 'p37_write.ps1')
$partA = $src[0..211]      # header .. src page alloc
$rot   = $src[306..338]    # Heal/Canary + H handle rotation
$partC = $src[238..304]    # S2 MSR, S3 ntoskrnl, S4 g_CiOptions
$s1 = @'
# ---- S1: chunk ladder + all-512-entry PML4 self-map scan -> CR3 -----------
Log ''
Log '########## S1 whole-RAM PML4 self-map scan, ALL 512 entries (read-only) ##########'
$probes = [uint64[]]@([uint64]0x100000, [uint64]0x100000000)
$crep = ''
$chunk = [P38Prov]::ChunkSize($g, $probes, [ref]$crep)
foreach ($ln in ($crep -split "`r`n")) { if ($ln -ne '') { Log ("  ladder{0}" -f $ln) } }
# 0x10000 is the only size proven crash-clean (624 MB scanned at it). The ladder
# above stays purely diagnostic; its verdict is deliberately overridden.
if ($chunk -eq 0) { Log '  ladder: no size passed - using the proven 0x10000' }
elseif ($chunk -ne 0x10000) { Log ("  ladder: measured best 0x{0:x}, clamped to the proven 0x10000" -f $chunk) }
$chunk = 0x10000
Log ("  chunk = 0x{0:x}" -f $chunk)
$pnotes = ''; $scanned = [uint64]0; $selfIdx = -1
$t0 = Get-Date
if ($srcVa -ne 0) {
    try { $pn = [P38Prov]::ScanPml4All($g, $ramTop, $chunk, $srcVa, [byte]0xAB, [ref]$cr3, [ref]$pnotes, [ref]$scanned, [ref]$selfIdx) }
    catch { $pn = ''; $cr3 = [uint64]0; Log ('  S1 EXCEPTION: ' + $_.Exception.Message) }
} else { $pn = ''; Log '  S1 skipped scan (no src page to prove ownership)' }
foreach ($ln in ($pnotes -split "`r`n")) { if ($ln -ne '') { Log $ln } }
Log ("  S1 scanned=0x{0:x} accepted={1} cr3=0x{2:x} selfIdx=0x{3:x} in {4:N1}s" -f $scanned, $pn, $cr3, $selfIdx, ((Get-Date) - $t0).TotalSeconds)
if ($cr3 -ne 0) {
    $verdict.cr3 = $true
    $chk = [P38Prov]::RdQ($g, $cr3 + [uint64]$selfIdx * 8)
    $selfOk = (($chk -band 0x000FFFFFFFFFF000L) -eq $cr3)
    Log ("  S1 self-entry = 0x{0:x} self-consistent={1} - CR3 VALID (index 0x{2:x})" -f $chk, $selfOk, $selfIdx)
} else {
    Log '  S1 no CR3  FAIL'
    Log '  hint: if reads were clean, the bench (VM-B) is the place to iterate the predicate'
}
'@ -split "`r?`n"
$tail = @(
    ''
    '# ---- verdict summary -----------------------------------------------------'
    'Log '''''
    'Log ''########## VERDICT ##########'''
    'Log ("  cr3={0} nt={1} ci={2}" -f $verdict.cr3, $verdict.nt, $verdict.ci)'
    'if ($verdict.ci) { Log ("  NEXT p38b: write-probe; only 0 goes to targetPa=0x{0:x} (current 0x{1:x8}) in p38c" -f $ciPa, $civ) }'
    '''-- p38 END (read) --'' | Add-Content -LiteralPath $OUT -Encoding UTF8'
    'try { [P38Prov]::CloseHandle2($g) | Out-Null } catch { }'
)
$out = @($partA) + @($s1) + @($rot) + @($partC) + @($tail)
$text = ($out -join "`r`n")
$text = $text.Replace('P37Prov', 'P38Prov')
$text = $text.Replace('p36_badpa', '@@SEED@@')
$text = $text.Replace('p37', 'p38')
$text = $text.Replace('p38_write.txt', 'p38_read.txt')
$text = $text.Replace('p38_write_prev', 'p38_read_prev')
$text = $text.Replace('@@SEED@@', 'p37_badpa')
[System.IO.File]::WriteAllText((Join-Path $r 'p38_read.ps1'), $text, (New-Object System.Text.UTF8Encoding($false)))
"lines out = " + ($out.Count)
