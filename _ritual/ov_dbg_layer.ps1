# Elevated helper: add the Graphics Tools optional capability so d3d12SDKLayers.dll
# exists and D3D12GetDebugInterface() can name the exact faulting call.
# At most 60 s of this; logs everything to C:\h320x\t129.txt.
$log = 'C:\h320x\t129.txt'
"start $(Get-Date -Format o)" | Out-File -Encoding utf8 $log
try {
    $c = Get-WindowsCapability -Online -Name 'Tools.Graphics.DirectX*'
    $c | Select-Object Name, State | Out-String | Out-File -Append -Encoding utf8 $log
    if ($c.State -ne 'Installed') {
        $r = Add-WindowsCapability -Online -Name $c.Name
        $r | Out-String | Out-File -Append -Encoding utf8 $log
    }
} catch {
    "ERROR: $($_.Exception.Message)" | Out-File -Append -Encoding utf8 $log
}
"dll=$(Test-Path 'C:\Windows\System32\d3d12SDKLayers.dll')" | Out-File -Append -Encoding utf8 $log
"done $(Get-Date -Format o)" | Out-File -Append -Encoding utf8 $log