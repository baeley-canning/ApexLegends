# _p38_readchk.ps1 - is the gdrv read path actually returning memory, or zeros?
# Cross-check: the map view at PA 0xFC000000 read 13 10 00 00 ff ... - a raw read
# of the same PA must return the same bytes if reads work at all.
$log = Join-Path $PSScriptRoot '_p38.txt'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"') -Verb RunAs -Wait
    exit 0
}
Set-Content -LiteralPath $log -Value ('readchk ' + (Get-Date -f 'HH:mm:ss')) -Encoding UTF8
try { Add-Type -Path (Join-Path $PSScriptRoot 'p36_prov.cs') -ErrorAction Stop } catch { Add-Content $log ('compile FAIL ' + $_.Exception.Message); exit }
$g = [IntPtr]::Zero
$e0 = [P36Prov]::GdrvOpen([ref]$g)
Add-Content $log ('open=' + $e0 + ' h=0x' + $g.ToInt64().ToString('x'))
if ($g -ne [IntPtr]::Zero) {
    foreach ($pa in [uint64]0x0L, [uint64]0x1000L, [uint64]0xA0000L, [uint64]0xFC000000L, [uint64]0xFC001000L, [uint64]0xFC100000L) {
        try { Add-Content $log ('pa=0x' + $pa.ToString('x') + ' raw: ' + [P36Prov]::Hex([P36Prov]::GdrvReadOneRaw($g, $pa, 16))) }
        catch { Add-Content $log ('pa=0x' + $pa.ToString('x') + ' EXC ' + $_.Exception.Message) }
    }
    [P36Prov]::CloseHandle2($g) | Out-Null
}
Add-Content $log 'done'

