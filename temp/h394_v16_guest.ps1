# Runs INSIDE the bench VM. v16 IMAGE is byte-identical to host build; signing
# is read-back checked before loading. Read ONLY notepad.exe, never Apex.
$ErrorActionPreference = 'Continue'
$out = 'C:\h394_v16_out.txt'
function w([string]$s) { ((Get-Date -Format 'HH:mm:ss.fff') + ' ' + $s) | Add-Content -LiteralPath $out -Encoding ASCII }
Remove-Item $out, 'C:\apexdrv.sys.h394.bak' -EA SilentlyContinue
w 'H394 v16 self only. Pre-signature + pre-service; cleanup same script'
sc.exe query ApexDrv | Out-String | Add-Content $out
sc.exe qc ApexDrv | Out-String | Add-Content $out
Get-AuthenticodeSignature C:\apexdrv.sys | Format-List Status,StatusMessage | Out-String | Add-Content $out
sc.exe start ApexDrv | Out-String | Add-Content $out
w 'readback service:'
sc.exe query ApexDrv | Out-String | Add-Content $out
try {
    $n = Get-Process -Name notepad -ErrorAction SilentlyContinue | Select-Object -Last 1
    if (-not $n) { Start-Process notepad.exe -WindowStyle Minimized; Start-Sleep -Seconds 3; $n = Get-Process -Name notepad -EA stop }
    & C:\qk_probe.exe "--pid=$($n.Id)" '--secs=5' '--out=C:\h394_probe_self.txt' *>> $out
    w ('qk_probe rc=' + $LASTEXITCODE)
    Get-Content C:\h394_probe_self.txt -Tail 15 -EA SilentlyContinue | Add-Content $out
} catch { w ('EXC ' + $_.Exception.Message) }
sc.exe stop ApexDrv | Out-String | Add-Content $out
Start-Sleep -Seconds 2
w 'post service:'
sc.exe query ApexDrv | Out-String | Add-Content $out
w 'guest liabilities removed self clean'