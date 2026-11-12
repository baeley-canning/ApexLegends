# h316_order_selftest.ps1 - proves the provider-order/name-parse logic in cur_h316_live.ps1 against a
# REAL kdu csv (C:\Users\Public\p37\kdu_list_h316.csv) without loading a single driver. Read-only.
# R5: own output file, new number.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h316_order_selftest.out'
$csv  = 'C:\Users\Public\p37\kdu_list_h316.csv'
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $L.Add($s); Write-Host $s }
Lg ('===== h316 order selftest ' + (Get-Date -f 'HH:mm:ss') + ' =====')
Lg ('csv=' + $csv + ' exists=' + (Test-Path $csv) + ' bytes=' + (Get-Item $csv -EA 0).Length)
if (-not (Test-Path $csv)) { Lg 'RESULT: FAIL - no csv'; Set-Content -LiteralPath $out -Value $L; exit 1 }

# --- verbatim copies of the two snippets from cur_h316_live.ps1 -------------------------------
$ids = @(); $names = @{}
foreach ($row in (Get-Content $csv -EA 0)) {
    if ($row -match '^\s*"?(\d{1,3})"?,[^,]*,"([^"]*)"') { $ids += [int]$matches[1]; $names[[int]$matches[1]] = $matches[2] }
}
$ids = @($ids | Select-Object -Unique)
$suspect = @(14, 27, 22)
$order = @($ids | Where-Object { $suspect -notcontains $_ }) + @($suspect | Where-Object { $ids -contains $_ })

# --- assertions ------------------------------------------------------------------------------
$fail = 0
function Check([string]$what, [bool]$ok) { Lg (('  {0} {1}' -f $(if ($ok) { 'OK  ' } else { 'FAIL' }), $what)); if (-not $ok) { $script:fail++ } }
Check ('ids parsed (>60)' + ' = ' + $ids.Count) ($ids.Count -gt 60)
Check ('first is 0 (NalDrv)' + ' = ' + $order[0]) ($order[0] -eq 0)
Check ('last three are the suspects in order 14,27,22 = ' + (($order | Select-Object -Last 3) -join ',')) ((($order | Select-Object -Last 3) -join ',') -eq '14,27,22')
Check ('14 maps to DirectIo64 = ' + $names[14]) ($names[14] -eq 'DirectIo64')
Check ('27 also DirectIo64 = ' + $names[27]) ($names[27] -eq 'DirectIo64')
Check ('no suspect before position ' + ($order.Count - 3)) (@($order[0..($order.Count - 4)] | Where-Object { $suspect -contains $_ }).Count -eq 0)
Check ('count preserved (no id lost/duplicated) ' + $order.Count + ' vs ' + $ids.Count) (($order.Count -eq $ids.Count) -and (@($order | Select-Object -Unique).Count -eq $ids.Count))
Lg ('order head=' + (($order | Select-Object -First 6) -join ',') + ' tail=' + (($order | Select-Object -Last 6) -join ','))
Lg ('RESULT: ' + $(if ($fail -eq 0) { 'PASS - order/parse logic holds on the real csv' } else { "FAIL - $fail assertion(s)" }))
Set-Content -LiteralPath $out -Value ($L -join "`r`n")
exit $(if ($fail -eq 0) { 0 } else { 1 })
