# p18.ps1 - live capture of EAAC driver lifecycle + window/exit evidence
# Non-elevated OK. Writes _ritual\p18.txt and copies the driver out if it ever appears.
$ErrorActionPreference = 'Continue'
$root = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$o    = Join-Path $root 'p18.txt'
$cap  = Join-Path $root 'eaac_capture'
New-Item -ItemType Directory -Force -Path $cap | Out-Null
function W([string]$m) { Add-Content -LiteralPath $o (('{0}  {1}' -f (Get-Date -Format 'HH:mm:ss.fff'), $m)) }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
('=== p18 ' + (Get-Date) + ' admin=' + $isAdmin + ' ===') | Set-Content -LiteralPath $o

$drv = 'C:\Windows\System32\drivers\eaanticheat.sys'
W ('pre exists(driver path)=' + (Test-Path -LiteralPath $drv))
W 'pre sc query eaanticheat'
(sc.exe query eaanticheat)  2>&1 | ForEach-Object { W ('   ' + $_) }
W 'pre sc query EAAntiCheat'
(sc.exe query EAAntiCheat)  2>&1 | ForEach-Object { W ('   ' + $_) }
W 'pre processes'
Get-Process EAAntiCheat*,eaanticheat* -ErrorAction 0 | ForEach-Object { W ('   PID ' + $_.Id + ' ' + $_.ProcessName) }

$exe = 'C:\Program Files\EA Games\Apex\EAAntiCheat.GameServiceLauncher.exe'
W ('launching ' + $exe)
$p = $null
try { $p = Start-Process -FilePath $exe -WorkingDirectory 'C:\Program Files\EA Games\Apex' -PassThru } catch { W ('launch failed: ' + $_) }
if ($p) { W ('launcher pid=' + $p.Id) }

$seen = $false
for ($i = 0; $i -lt 320; $i++) {
    Start-Sleep -Milliseconds 250
    $ex = Test-Path -LiteralPath $drv
    if ($ex -and -not $seen) {
        $seen = $true
        W '*** DRIVER FILE APPEARED ***'
        $dst = Join-Path $cap ('eaanticheat_' + (Get-Date -Format 'HHmmss') + '.sys')
        try { Copy-Item -LiteralPath $drv -Destination $dst -Force; W ('copied -> ' + $dst) } catch { W ('copy fail: ' + $_) }
        try { W ('sha256 ' + (Get-FileHash -LiteralPath $drv -Algorithm SHA256).Hash) } catch {}
        try { $sg = Get-AuthenticodeSignature -LiteralPath $drv; W ('sig=' + $sg.Status + ' signer=' + $sg.SignerCertificate.Subject) } catch {}
        try { $vi = (Get-Item -LiteralPath $drv).VersionInfo; W ('FileVersion=' + $vi.FileVersion + ' Product=' + $vi.ProductName + ' Orig=' + $vi.OriginalFilename) } catch {}
    }
    if ((-not $ex) -and $seen) { W '*** DRIVER FILE DISAPPEARED ***'; break }
    if ($i % 20 -eq 0) {
        $pr = Get-Process EAAntiCheat*,eaanticheat* -ErrorAction 0
        $names = ''
        if ($pr) { $names = (($pr | ForEach-Object { $_.ProcessName + ':' + $_.Id }) -join ',') }
        W ('t=' + [int]($i / 4) + 's drv=' + $ex + ' procs=' + $names)
    }
    if ($p -and $p.HasExited -and -not $seen -and $i -gt 40) { W ('launcher exited code=' + $p.ExitCode); break }
}

W 'window snapshot (titled windows)'
Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object { W ('   ' + $_.ProcessName + ' :: ' + $_.MainWindowTitle) }
W 'post sc query eaanticheat'
(sc.exe query eaanticheat) 2>&1 | ForEach-Object { W ('   ' + $_) }
W 'post exists(driver path)=' + (Test-Path -LiteralPath $drv)
W 'fltmc attempt'
(fltmc.exe filters) 2>&1 | ForEach-Object { W ('   ' + $_) }
W ('=== end ' + (Get-Date) + ' ===')
