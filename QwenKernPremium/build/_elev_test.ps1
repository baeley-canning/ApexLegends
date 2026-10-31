$out = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\_elev_test.txt'
$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr  = New-Object Security.Principal.WindowsPrincipal($id)
$admin = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
"whoami=$($id.Name)" | Out-File -FilePath $out -Encoding ascii
"elevated=$admin"   | Out-File -FilePath $out -Encoding ascii -Append
"cwd=$((Get-Location).Path)" | Out-File -FilePath $out -Encoding ascii -Append
