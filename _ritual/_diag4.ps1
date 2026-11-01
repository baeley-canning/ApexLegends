$o='C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_diag4.txt'
"d4 "+(Get-Date -Format s) | Set-Content -LiteralPath $o
function A($x){ $x | Add-Content -LiteralPath $o }
A '-- bcdedit current --'; (bcdedit /enum '{current}' 2>&1) | Add-Content -LiteralPath $o
A '-- bcdedit all --'; (bcdedit /enum 2>&1) | Add-Content -LiteralPath $o
A '-- SystemStartOptions --'; (reg query 'HKLM\SYSTEM\CurrentControlSet\Control\SystemStartOptions' 2>&1) | Add-Content -LiteralPath $o
A '-- SecureBoot State --'; (reg query 'HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State' 2>&1) | Add-Content -LiteralPath $o
A '-- CI Policy --'; (reg query 'HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy' 2>&1) | Add-Content -LiteralPath $o
A '-- CI Config --'; (reg query 'HKLM\SYSTEM\CurrentControlSet\Control\CI\Config' 2>&1) | Add-Content -LiteralPath $o
A '-- CI Protected --'; (reg query 'HKLM\SYSTEM\CurrentControlSet\Control\CI\Protected' 2>&1) | Add-Content -LiteralPath $o
A '-- HVCI --'; (reg query 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 2>&1) | Add-Content -LiteralPath $o
A '-- os --'; (Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber | Format-List | Out-String).Trim() | Add-Content -LiteralPath $o
$st='C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe'
foreach($f in @('C:\Windows\System32\drivers\apexdrv.sys','C:\p26cat\apexdrv_build.sys','C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\apexdrv.sys')){
 A ('-- file '+$f)
 $r=Get-AuthenticodeSignature -LiteralPath $f
 A ('   authz status='+$r.Status+' signer='+$r.SignerCertificate.Subject)
 A '   -- /pa embedded only:'
 (& $st verify /pa $f 2>&1) | Add-Content -LiteralPath $o
}
A 'done'
