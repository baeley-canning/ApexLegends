# t8_tidy2.ps1 - second tidy pass: the `nul` redirect artifact + leftover listing dumps.
$root = Split-Path -Parent $PSScriptRoot
$dst = Join-Path $PSScriptRoot '_root_scratch'
$o = Join-Path $PSScriptRoot '_t8_tidy.txt'
$L = New-Object System.Collections.Generic.List[string]
$L.Add('T8 ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss'))

$before = @{}
foreach ($f in @(Get-ChildItem $root -File)) { $before[$f.Name] = $f.Length }

# `nul` cannot be addressed normally; the \\?\ prefix is required.
$nul = '\\?\' + (Join-Path $root 'nul')
(& cmd /c "del `"$nul`"" ) 2>&1 | ForEach-Object { $L.Add('  DEL nul :: ' + $_) }
$L.Add('  nul exists after = ' + (Test-Path -LiteralPath (Join-Path $root 'nul')))

$names = @(
    'p1.log', 'p1_summary.txt', 'p2.log', 'p2_summary.txt', 'p2_tail.txt', 'p5.txt',
    'gate_run.txt', 'gate_run2.txt', 'gate3.txt',
    'hk_a.txt', 'hk_b.txt', 'hk_c.txt', 'lm_a.txt', 'lm_b.txt', 'lm_c.txt', 'inj_a.txt',
    'ft_a.txt', 'mh.txt', 'kern_listing.txt', 'kern2.txt', 'kb_listing.txt', 'kb2.txt',
    'files.txt', 'find_dumpbin.txt', 'listing.txt', 'listing2.txt', 'names.txt',
    'M2_KERNEL_CHEAT_HANDOFF_PROMPT.md', 'apexr - run after reboot.lnk'
)
$moved = 0
foreach ($n in $names) {
    $src = Join-Path $root $n
    if (-not (Test-Path -LiteralPath $src)) { $L.Add('  SKIP  ' + $n); continue }
    try { Move-Item -LiteralPath $src -Destination (Join-Path $dst $n) -ErrorAction Stop
          $L.Add('  MOVE  ' + $n); $moved++ }
    catch { $L.Add('  FAIL  ' + $n + ' :: ' + $_.Exception.Message) }
}
$L.Add("moved=$moved")
$L.Add('-- root files after')
foreach ($f in @(Get-ChildItem $root -File | Sort-Object Name)) { $L.Add('  ' + $f.Name) }
$L.Add('END')
($L -join "`r`n") | Out-File -FilePath $o -Encoding ascii
