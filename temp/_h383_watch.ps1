# _h383_watch.ps1 -- passive observer for the elevated h383 run (started hidden).
# Appends one line per 15 s to temp\_h383_watch.txt until the probe process ends
# or 20 min pass: wall clock, probe CPU, whether _h383_out.txt exists, and the
# tail of the probe's stdout (temp\_h383_console.txt, UTF-16 from '>>').
param([int]$Pid_ = 0, [int]$Minutes = 20)

$root = Split-Path -Parent $PSScriptRoot
$watch = Join-Path $root 'temp\_h383_watch.txt'
$con = Join-Path $root 'temp\_h383_console.txt'
$outf = Join-Path $root 'temp\_h383_out.txt'
$deadline = (Get-Date).AddMinutes($Minutes)

'--- watch ' + (Get-Date -Format 'HH:mm:ss') + ' pid=' + $Pid_ | Set-Content -LiteralPath $watch

while ((Get-Date) -lt $deadline) {
    $p = if ($Pid_ -gt 0) { Get-Process -Id $Pid_ -ErrorAction SilentlyContinue } else { $null }
    $line = (Get-Date -Format 'HH:mm:ss')
    if ($p) { $line += '  cpu=' + [math]::Round($p.CPU, 1) + '  ws=' + [int]($p.WorkingSet64 / 1MB) + 'MB' }
    else { $line += '  PROBE-EXITED' }
    $line += '  out=' + (Test-Path $outf)
    $line | Add-Content -LiteralPath $watch

    if (Test-Path $con) {
        try {
            $fs = [IO.File]::Open($con, 'Open', 'Read', 'ReadWrite')
            $br = New-Object IO.BinaryReader($fs)
            $data = $br.ReadBytes([int]$fs.Length)
            $br.Close(); $fs.Close()
            $txt = [Text.Encoding]::Unicode.GetString($data) -replace "`0", ''
            $tailLines = ($txt -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 6)
            foreach ($t in $tailLines) { ('    | ' + $t.Trim()) | Add-Content -LiteralPath $watch }
        } catch { ('    ! console locked: ' + $_.Exception.Message) | Add-Content -LiteralPath $watch }
    }

    if (-not $p) { break }
    Start-Sleep -Seconds 15
}

'--- watch end ' + (Get-Date -Format 'HH:mm:ss') | Add-Content -LiteralPath $watch
