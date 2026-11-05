$r = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p269de_verify.txt'
Remove-Item -LiteralPath $r -EA 0
$a = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\h269_cur.ps1'
$b = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\h270_cur.ps1'
foreach ($f in $a, $b) {
    $err = $null
    [void][Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$err)
    '{0} parse_errors={1} len={2}' -f (Split-Path $f -Leaf), $err.Count, (Get-Item $f).Length | Add-Content -LiteralPath $r
}
$la = Get-Content -LiteralPath $a
$lb = Get-Content -LiteralPath $b
Add-Content -LiteralPath $r '--- diff (only the intended lines) ---'
(Compare-Object $la $lb) | ForEach-Object { $_.SideIndicator + ' ' + $_.InputObject } | Add-Content -LiteralPath $r
Add-Content -LiteralPath $r '--- h269 refs left in h270 ---'
(Select-String -LiteralPath $b -Pattern 'h269|h268' | ForEach-Object { $_.LineNumber.ToString() + ': ' + $_.Line }) | Add-Content -LiteralPath $r
Add-Content -LiteralPath $r '--- functional lines ---'
(Select-String -LiteralPath $b -Pattern "^\`$tag|\`$pref = @") | ForEach-Object { $_.LineNumber.ToString() + ': ' + $_.Line } | Add-Content -LiteralPath $r
$u = (Select-String -LiteralPath $b -Pattern '\$tag\s*=\s*''h(\d+)''' | Select-Object -First 1)
Add-Content -LiteralPath $r ('TAG_SET: ' + ($(if ($u.Matches.Groups[1].Value -eq '270') { 'h270 OK' } else { 'WRONG ' + $u.Matches.Groups[1].Value })))
$pf = (Select-String -LiteralPath $b -Pattern '\$pref = @\((.+)\)')
Add-Content -LiteralPath $r ('PREF: ' + $pf.Matches.Groups[1].Value)
Add-Content -LiteralPath $r ('PREF_22_LAST: ' + ($(if ($pf.Matches.Groups[1].Value -match ',\s*22\s*$') { 'YES' } else { 'NO' })))
'done' | Add-Content -LiteralPath $r
