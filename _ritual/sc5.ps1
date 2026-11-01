# sc5.ps1 - ELEVATED. Isolate why the SCM cannot see a well-formed service key.
# Tests: ACL, net start, sc create with binPath, hand-written key under a
# different name, and SCM enumeration sanity.
$ErrorActionPreference = 'Continue'
$log = 'C:\qkp\sc5.txt'
function W([string] $t) { $t | Out-File -Encoding utf8 -Append $log }
$drv = 'C:\Windows\System32\drivers\apexdrv.sys'

"== sc5 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==" | Out-File -Encoding utf8 $log
W "elevated : $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
W "drv sig  : $((Get-AuthenticodeSignature $drv).Status)"

$key = 'HKLM:\SYSTEM\CurrentControlSet\Services\apexdrv'
W '--- ACL of the apexdrv service key ---'
try { (Get-Acl $key).Access | ForEach-Object { W "  acl| $($_.IdentityReference) $($_.RegistryRights)" } }
catch { W "  acl| $($_.Exception.Message)" }

W '--- net start apexdrv ---'
(& cmd /c 'net start apexdrv') 2>&1 | ForEach-Object { W "  | $_" }

W '--- SCM sanity: total driver-type services enumerated ---'
$all = (& sc.exe query type= driver state= all) 2>&1
W ("  total lines : " + ($all | Measure-Object).Count)
W ("  lists apex? : " + [bool]($all | Select-String -SimpleMatch 'apex'))

W '--- TEST A: sc.exe create apexdrv WITH binPath (key removed first) ---'
Remove-Item $key -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300
(& sc.exe create apexdrv binPath= '\??\C:\Windows\System32\drivers\apexdrv.sys' type= kernel start= demand ErrorControl= normal) 2>&1 |
    ForEach-Object { W "  createA| $_" }
(& sc.exe query apexdrv) 2>&1 | ForEach-Object { W "  queryA| $_" }

if (-not (Test-Path $key)) {
    W '--- TEST B: hand-written key under a DIFFERENT name (kernprobe) ---'
    $k2 = 'HKLM:\SYSTEM\CurrentControlSet\Services\kernprobe'
    Remove-Item $k2 -Force -ErrorAction SilentlyContinue
    New-Item -Path $k2 -Force | Out-Null
    Set-ItemProperty $k2 -Name 'Type'         -Value 1 -Type DWord
    Set-ItemProperty $k2 -Name 'Start'        -Value 3 -Type DWord
    Set-ItemProperty $k2 -Name 'ErrorControl' -Value 1 -Type DWord
    Set-ItemProperty $k2 -Name 'ImagePath'    -Value 'System32\drivers\apexdrv.sys' -Type ExpandString
    Set-ItemProperty $k2 -Name 'ObjectName'   -Value 'LocalSystem' -Type String
    (& sc.exe query kernprobe) 2>&1 | ForEach-Object { W "  queryB| $_" }
}

W '--- TEST C: does the SCM see ANY newly hand-written name? (sc create zzprobe) ---'
(& sc.exe delete zzprobe) 2>&1 | Out-Null
(& sc.exe create zzprobe binPath= '\??\C:\Windows\System32\drivers\apexdrv.sys' type= kernel start= demand) 2>&1 |
    ForEach-Object { W "  createC| $_" }
(& sc.exe query zzprobe) 2>&1 | ForEach-Object { W "  queryC| $_" }

W '--- final: what IS in the registry under Services named apex/kern/zz ---'
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match 'apex|kern|zz' } | ForEach-Object { W "  KEY: [$($_.PSChildName)]" }
W 'END'
