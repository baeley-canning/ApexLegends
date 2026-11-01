# runner.ps1 - detached-safe driver for catlookup2.ps1 (survives terminal reuse).
$dir = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
Set-Location -LiteralPath $dir
$log  = Join-Path $dir 'catlookup2_fix4.log'
$done = Join-Path $dir 'oracle.done'
Remove-Item -LiteralPath $done -ErrorAction SilentlyContinue
$t = Get-Date
try {
    & (Join-Path $dir 'catlookup2.ps1') "$env:SystemRoot\System32\drivers\tcpip.sys" `
                                          "$env:SystemRoot\System32\drivers\apexdrv.sys" *>&1 |
        Out-File -Encoding utf8 $log
    "EXIT=$LASTEXITCODE secs=" + [int]((Get-Date) - $t).TotalSeconds | Add-Content -Encoding utf8 $log
} catch {
    "RUNNER THREW: " + $_.Exception.Message | Add-Content -Encoding utf8 $log
}
"FINISHED " + (Get-Date).ToString('s') | Add-Content -Encoding utf8 $done
