# p44i pre-state (R3) + elevated stage.  Pure read: three narrow windows at the
# stale trio PAs, anchored on live pid 0x44b0.  Variable: the anchor PA itself.
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o    = Join-Path $repo 'temp\p44i_pre.txt'
$L    = New-Object System.Collections.Generic.List[string]
$L.Add('now ' + (Get-Date -f 's'))
$g = Get-Process -Id 17584 -EA 0
if ($g) { $L.Add("GAME alive pid=17584 ws=$([int]($g.WorkingSet64/1MB))MB") } else { $L.Add('GAME gone pid=17584') }
$L.Add('pid hex=0x44b0')
$L.Add('eac procs=' + @(Get-Process | Where-Object { $_.Name -match 'EasyAnti' }).Count)
$L.Add('drv=' + ((Get-CimInstance Win32_SystemDriver -EA 0 |
    Where-Object { $_.Name -match 'gio|gdrv' } | ForEach-Object { "$($_.Name):$($_.State):$($_.Started)" }) -join ','))
$L.Add('stale trio: LINK=0x2481D60C0(value) FL=0xFFFFA401B25A5258 BL=0xFFFFA401B7EA0258 from launch pid 0x1570')
$L.Add('p44h coverage so far: 0x0eda00000..0x7eda00000 (29 GiB), 0 decoys, 3 partial runs of low range all found=0')
Set-Content -LiteralPath $o -Value $L -Encoding UTF8
if (-not $g) { Add-Content -LiteralPath $o -Value 'ABORT game gone'; exit 2 }
$r = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -ArgumentList `
     '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\Windows\Temp\p44i_run.ps1'
Add-Content -LiteralPath $o -Value ('LAUNCHED pid=' + $r.Id + ' at ' + (Get-Date -f 'HH:mm:ss'))
Get-Content -LiteralPath $o
