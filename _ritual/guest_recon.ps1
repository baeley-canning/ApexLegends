# guest_recon.ps1 - runs INSIDE the VM.  Answers: can this guest host the providers?
$log = 'C:\Users\vboxuser\guest_recon.txt'
function S($t) { $t | Out-File -FilePath $log -Encoding ascii -Append }
if (Test-Path $log) { Remove-Item $log -Force }
S ("=== guest_recon {0} host={1} user={2} ===" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'), $env:COMPUTERNAME, $env:USERNAME)
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
S ("admin={0}" -f $adm)
$os = Get-CimInstance Win32_OperatingSystem
S ("os={0} build={1}.{2} ramVisibleMB={3}" -f $os.Caption, $os.BuildNumber, $os.Version, [math]::Round($os.TotalVisibleMemorySize / 1KB))
S ("startopts=[{0}]" -f (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -EA 0).SystemStartOptions)
S ("testsigning/f8: " + ((& bcdedit.exe /enum '{current}' 2>&1 | Select-String 'testsigning|nointegritychecks|hypervisorlaunchtype') -join ' ; '))
S ("GA VBoxService=" + (Get-Service VBoxService -EA 0).Status + "  VBoxTray=" + ((Get-Process VBoxTray -EA 0) | Select-Object -First 1).Id)
S ("secureboot=" + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -EA 0).UEFISecureBootEnabled)
S ("pae/dynmem: " + ((Get-CimInstance Win32_ComputerSystem).AutomaticManagedPagefile))
foreach ($s in 'gdrv3', 'MsIo', 'apexdrv') {
    $q = ((& sc.exe query $s 2>&1) -join ' ')
    S ("svc {0,-10} {1}" -f $s, ($(if ($q -match 'SERVICE_NAME') { ($q -replace '\s+', ' ') } else { 'ABSENT' })))
}
foreach ($f in 'gdrv3.sys', 'MsIo64.sys', 'apexdrv.sys') {
    $p = "C:\Windows\System32\drivers\$f"
    S ("file {0,-14} exists={1} size={2}" -f $f, (Test-Path $p), (Get-Item $p -EA 0).Length)
}
S ("csc.NET4=" + (Test-Path 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'))
S ("pwsh=" + (Get-Command pwsh.exe -EA 0).Source)
S ("python=" + ((Get-Command python.exe -EA 0).Source))
S ("dumps dir=" + (Test-Path 'C:\Windows\Minidump'))
S ("crashdump enabled=" + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -EA 0).CrashDumpEnabled)
Get-PSDrive -PSProvider FileSystem | ForEach-Object { S ("drive {0} free={1}MB" -f $_.Name, [math]::Round($_.Free / 1MB)) }
S '--- resmap (real RAM ranges) ---'
if (Test-Path 'C:\Users\vboxuser\resmap.ps1') {
    try { & 'C:\Users\vboxuser\resmap.ps1' -Out 'C:\Users\vboxuser\resmap_guest.txt' } catch { S ('resmap ERR ' + $_.Exception.Message) }
    if (Test-Path 'C:\Users\vboxuser\resmap_guest.txt') { S ((Get-Content 'C:\Users\vboxuser\resmap_guest.txt') -join "`r`n") }
} else { S '  resmap.ps1 not staged' }
S '--- end ---'
