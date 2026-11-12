# Inventory existing signed drivers with no more host driver loading.
$r='C:\Users\New User\OneDrive\Desktop\cheating'
$out=Join-Path $r 'temp\h395_existing.txt'
Get-CimInstance Win32_SystemDriver | Select-Object Name,State,PathName |
  Where-Object { $_.Name -match 'gdrv|GIO|NTKERNEL|iqvw|winring|RTCore|dbutil|scream|CPU|Nal|Hw|Ene|Asra|lcx|Vbox' -or $_.State -eq 'Running' } |
  Sort-Object State,Name | Format-Table Name,State,PathName -AutoSize | Out-String -Width 200 | Set-Content $out
sc.exe query gdrv3 | Out-String | Add-Content $out
Get-FileHash C:\Windows\System32\ntoskrnl.exe | Format-List | Out-String | Add-Content $out
Get-Item C:\Windows\System32\ntoskrnl.exe | Select-Object -ExpandProperty VersionInfo | Format-List FileVersion,ProductVersion | Out-String | Add-Content $out
Get-ChildItem C:\Windows\System32\drivers -File -Filter '*.sys' |
  Where-Object { $_.Name -match 'gdrv|alpha|capcom|dbutil|iqvw|RTCore|cpu|alm|HW|rw|Vbox' } |
  ForEach-Object { Get-AuthenticodeSignature $_.FullName; Get-Item $_.FullName } | Format-Table Name,Length,@{N='Signature';E={$_.SignerCertificate.Subject}} -AutoSize | Out-String -Width 220 | Add-Content $out