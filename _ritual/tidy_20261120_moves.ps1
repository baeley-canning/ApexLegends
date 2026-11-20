# _ritual/tidy_20261120_moves.ps1 — repo de-trap tidy, Phase A (temp/ attics)
# Canon: R4 (every move reversible; manifests carry sha256+len+mtime), R5 (log to file, read the
# file), R6 (this IS the script; no chat one-liners), R7 (ledgers annotated separately, not here).
# Idempotent: safe to re-run (missing files log MISSING, manifests regenerate).
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $MyInvocation.MyCommand.Path) | Out-Null
Set-Location ..   # repo root, wherever _ritual lives
$log = @('TIDY-A ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$errs = @()

$t   = Join-Path (Get-Location) 'temp'
$a1  = Join-Path $t '_attic_zombiefossils_20261120'
$a2  = Join-Path $t '_attic_sweep_1105_bare_h'
New-Item -ItemType Directory -Force -Path $a1 | Out-Null
New-Item -ItemType Directory -Force -Path $a2 | Out-Null

# --- Family 1: zombie qk_live code fossils (11/09 era, stale copies of ext\qk_live.py history).
# Zero live deps: only _ritual\_root_scratch\tree.txt (passive listing) references them.
$zf = @(
  'qk_live_before_act_20261109.py',
  '_act_qk_live_snapshot.txt',
  '_act_qk_live_snapshot2.txt',
  '_act_qk_live_snapshot3.txt',
  '_act_qk_live_snapshot4.txt',
  '_act_qk_live_snapshot5.txt',
  '_h386_snapshot.txt',
  '_h386_snapshot_meta.txt'
)
foreach ($f in $zf) {
  $p = Join-Path $t $f
  if (Test-Path -LiteralPath $p) {
    try { Move-Item -LiteralPath $p -Destination $a1 -ErrorAction Stop; $log += ('MOVED ' + $f) }
    catch { $errs += ('ERR1 ' + $f + ' :: ' + $_.Exception.Message) }
  } else { $log += ('MISSING(already moved?) ' + $f) }
}

# --- Family 2: 11/05 bare-underscore sweep outputs _h4NN(.txt|_sign.txt) — Apex patch-version
# pings + KDU/apexdrv-era residue. Collides with the CURRENT evidence grammar hNNN_tag.* (no
# underscore, 11/19+). Removal from the flat namespace is the de-trap; _p403_prestate.txt
# documents their original listing, MANIFEST records origin path temp\<name>.
$sweep = @(Get-ChildItem $t -File | Where-Object { $_.Name -match '^_h4\d\d(_sign)?\.txt$' })
$log += ('SWEEP_TARGETS ' + $sweep.Count)
foreach ($f in $sweep) {
  try { Move-Item -LiteralPath $f.FullName -Destination $a2 -ErrorAction Stop; $log += ('MOVED ' + $f.Name) }
  catch { $errs += ('ERR2 ' + $f.Name + ' :: ' + $_.Exception.Message) }
}

# --- Manifests (sha256 + len + lastwrite), regenerated deterministically each run.
foreach ($spec in @(@($a1, 'zombiefossils'), @($a2, 'sweep1105_bare_h'))) {
  $d = $spec[0]; $lbl = $spec[1]
  $mf = Join-Path $d ('MANIFEST_SHA256_' + $lbl + '.txt')
  $lines = @('# sha256  len  lastwrite  name   (moved-from temp\<name> by tidy_20261120_moves.ps1)')
  $hf = Get-ChildItem $d -File | Where-Object { $_.Name -notlike 'MANIFEST_*' -and $_.Name -notlike 'ORIGIN_*' } | Sort-Object Name
  foreach ($f in $hf) {
    $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    $lines += ($h + '  ' + $f.Length + '  ' + $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') + '  ' + $f.Name)
  }
  Set-Content -LiteralPath $mf -Value $lines -Encoding ascii
  $log += ('MANIFEST ' + (Split-Path -Leaf $mf) + ' entries=' + ($lines.Count - 1))
}

# --- Post-state read-back (R3: the log is the verdict).
$log += ('ERRORS ' + $errs.Count)
$errs | ForEach-Object { $log += $_ }
$left = @(Get-ChildItem $t -File | Where-Object { $_.Name -match '^_h4\d\d(_sign)?\.txt$' }).Count
$log += ('TEMP_REMAINING_BARE_H4XX ' + $left)
$log += ('A1_FILES ' + @(Get-ChildItem $a1 -File).Count)
$log += ('A2_FILES ' + @(Get-ChildItem $a2 -File).Count)
$log += ('TEMP_TOTAL_NOW ' + @(Get-ChildItem $t -File).Count)
$out = Join-Path $t '_tidy_moves_a.txt'
Set-Content -LiteralPath $out -Value $log -Encoding ascii
Get-Content $out