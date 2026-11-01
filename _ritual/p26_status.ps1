# p26_status.ps1 - ONE COMMAND VISIBILITY. Shows the whole current state in one screen.
# run:  powershell -NoProfile -ExecutionPolicy Bypass -File _ritual\p26_status.ps1
$d = $PSScriptRoot
function Sec($t) { "`n===== $t =====" }
function Show($f, $n) {
    if (Test-Path -LiteralPath $f) { Sec "$f  (last $n)"; Get-Content -LiteralPath $f -Tail $n }
    else { Sec "$f  (MISSING)" }
}

Sec "ORACLE (coverage of apexdrv/tcpip vs installed catalogs)"
"oracle.done = " + (Test-Path (Join-Path $d 'oracle.done'))
Show (Join-Path $d 'catlookup2_fix4.log') 22

Sec "DRIVER SERVICE / SIG / HOST"
"kernprobe = " + (Get-Service kernprobe -ErrorAction SilentlyContinue).Status
$ap = Join-Path $env:SystemRoot 'System32\drivers\apexdrv.sys'
if (Test-Path -LiteralPath $ap) {
    "apexdrv.sys len=" + (Get-Item -LiteralPath $ap).Length
    $s = Get-AuthenticodeSignature -LiteralPath $ap
    "sig=" + $s.Status + " signer=" + $(if ($s.SignerCertificate) { $s.SignerCertificate.Subject } else { '(none)' })
    "sha1=" + (Get-FileHash -LiteralPath $ap -Algorithm SHA1).Hash
}

Sec "GAME PROCESS"
Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'apex|EasyAnti|r5' } |
    Select-Object ProcessName, Id, @{ n = 'MB'; e = { [int]($_.WorkingSet64 / 1MB) } } | Format-Table -AutoSize

Sec "ENGINE SELF-TEST (last line)"
if (Test-Path (Join-Path $d 'fix5_selftest.txt')) { Get-Content (Join-Path $d 'fix5_selftest.txt') -Tail 2 } else { 'run cateng.ps1 -SelfTest' }

Sec "TARGETS"
Show (Join-Path $d 'p26_player.txt') 20
Show (Join-Path $d 'p26_testsign.txt') 10
Show (Join-Path $d 'p26_drv.txt') 30
"`n== end =="
