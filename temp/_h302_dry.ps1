# dry-generate h302's guest .cmd on the host to prove the parenthesised joins produce ONE line each
$p = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\h302_elev.ps1'
$all = Get-Content -LiteralPath $p
$i0 = ($all | Select-String -Pattern 'Set-Content -LiteralPath \$payload' | Select-Object -First 1).LineNumber
$i1 = $i0
while ($all[$i1 - 1].Trim() -ne ')') { $i1++ }
$block = ($all[($i0 - 1)..($i1 - 1)]) -join "`r`n"
$sid = 'S-1-5-21-1957909355-363273533-3916154183-1000'
$payload = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\_h302_preview.cmd'
& ([scriptblock]::Create($block))
$lines = Get-Content -LiteralPath $payload
$bad = 0
foreach ($ln in $lines) {
    $q = ([regex]::Matches($ln, '"')).Count
    $tag = 'ok'
    if ($q % 2 -ne 0) { $tag = 'UNBALANCED'; $bad++ }
    if ($ln -match '^[A-Za-z]:\\' -or $ln -match '^\d') { $tag = 'SPLIT'; $bad++ }
    Write-Output ('{0,-10} {1}' -f $tag, $ln)
}
Write-Output ('lines=' + $lines.Count + ' defects=' + $bad)
