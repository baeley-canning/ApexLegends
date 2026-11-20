# t7_tidy.ps1 - move dead root scratch into _ritual/_root_scratch/ and report the result.
# Additive-safe: a move that fails is listed, nothing is overwritten, no recursion, no delete
# outside the list. Run once; re-running is a no-op for files already gone.
$root = Split-Path -Parent $PSScriptRoot
$dst = Join-Path $PSScriptRoot '_root_scratch'
$o = Join-Path $PSScriptRoot '_t7_tidy.txt'
if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst | Out-Null }

$names = @(
    'nul',
    'build_output.txt', 'build_output2.txt', 'build_output3.txt', 'build_output4.txt',
    'build_output5.txt', 'build_output6.txt', 'build_output7.txt', 'build_output8.txt',
    'build_output9.txt', 'build_output_debug.txt', 'build_debug.txt', 'build_log.txt',
    'allfiles.txt', 'clean_tree.txt', 'tree.txt', 'wt_list.txt', 'dirs.txt', 'dirs_rel.txt',
    'p5_dirs.txt', 'p5_files.txt', 'p5_listing.txt',
    'phase5_all.txt', 'phase5_files.txt', 'phase5_tree.txt', 'qw_listing.txt',
    'qc', 'query', 'SPC_SP_OPUS_INFO_OBJID', '060A2B060104018237020101',
    'System.Net.Sockets.Socket',
    'UsersNew UserOneDriveDesktopcheatingcheatv2VERIFY.md',
    'UsersNew UserOneDriveDesktopcheatingcheatv2step01_output.txt',
    '_test2.obj', 'apexdrv.obj', 'vc140.pdb',
    '_catmemb.ps1', '_catmemb.txt.start', '_explore.ps1', '_rdpprobe.ps1',
    '_agents_scan.ps1', '_fix.ps1', 'dep_dll.txt', 'dep_launcher.txt',
    'w4.log', 'w4_ctx.txt', 'w4_summary.txt'
)

$moved = 0; $skipped = 0
$L = New-Object System.Collections.Generic.List[string]
$L.Add('T7 ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss'))
foreach ($n in $names) {
    $src = Join-Path $root $n
    if (-not (Test-Path -LiteralPath $src)) { $L.Add('  SKIP  ' + $n); $skipped++; continue }
    try {
        Move-Item -LiteralPath $src -Destination (Join-Path $dst $n) -ErrorAction Stop
        $L.Add('  MOVE  ' + $n); $moved++
    } catch {
        $L.Add('  FAIL  ' + $n + ' :: ' + $_.Exception.Message)
    }
}
$L.Add("moved=$moved skipped=$skipped")
$L.Add('-- root files after')
foreach ($f in @(Get-ChildItem $root -File | Sort-Object Name)) { $L.Add('  ' + $f.Name) }
$L.Add('END')
($L -join "`r`n") | Out-File -FilePath $o -Encoding ascii
