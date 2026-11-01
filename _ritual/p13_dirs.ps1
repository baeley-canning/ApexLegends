$ErrorActionPreference = 'Continue'
$r = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$o = Join-Path $r 'p13_dirs.txt'
$sw = [System.IO.StreamWriter]::new($o, $false, [System.Text.Encoding]::UTF8)
function W($s) { $sw.WriteLine($s) }
function Sec($t, $sb) { W ''; W ('##### ' + $t); try { & $sb } catch { W ('ERR: ' + $_.Exception.Message) } }
function RegQ($k) { try { $x = & reg query $k /s 2>&1; foreach ($l in $x) { W $l } } catch { W ('ERR: ' + $_.Exception.Message) } }
function Cmd($c) { try { $x = & cmd /c $c 2>&1; foreach ($l in $x) { W ('> ' + $l) } } catch { W ('ERR: ' + $_.Exception.Message) } }

W ('=== p13 dirs/state ' + (Get-Date) + ' ===')

Sec 'eaanticheat programdata (recurse)' {
  $p = 'C:\ProgramData\eaanticheat'
  if (Test-Path $p) { Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue |
      ForEach-Object { W ((($_.FullName) + "`t" + $_.Length + "`t" + $_.LastWriteTime)) } } else { W 'absent' }
}

Sec 'drivers EA/apex/javelin in system32\drivers' {
  Get-ChildItem 'C:\Windows\System32\drivers' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '(?i)ea|apex|javelin|skyfall|spear' } |
    ForEach-Object {
      $sig = Get-AuthenticodeSignature $_.FullName -ErrorAction SilentlyContinue
      W ("{0}`t{1}`t{2}`t{3}`t{4}" -f $_.Name, $_.Length, $_.LastWriteTime, $sig.Status, ($sig.SignerCertificate.Subject))
    }
}

Sec 'DriverStore FileRepository EA-ish' {
  Get-ChildItem 'C:\Windows\System32\DriverStore\FileRepository' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '(?i)ea|apex|javelin|skyfall|spear|anti' } |
    ForEach-Object { W $_.Name }
}

Sec 'CodeIntegrity dir' {
  Get-ChildItem 'C:\Windows\System32\CodeIntegrity' -Force -ErrorAction SilentlyContinue |
    ForEach-Object { W ("{0}`t{1}`t{2}" -f $_.Name, $_.Length, $_.LastWriteTime) }
}

Sec 'reg: DeviceGuard' { RegQ 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard' }
Sec 'reg: CI (recursive)' { RegQ 'HKLM\SYSTEM\CurrentControlSet\Control\CI' }
Sec 'reg: SecureBoot\State' { RegQ 'HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State' }
Sec 'reg: SystemInformation start options' { RegQ 'HKLM\SYSTEM\CurrentControlSet\Control\SystemInformation' }
Sec 'reg: Session Manager BootExecute' { RegQ 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\BootExecute' }

Sec 'fltmc filters' { Cmd 'fltmc filters' }
Sec 'fltmc instances' { Cmd 'fltmc instances' }
Sec 'sc query eaanticheat' { Cmd 'sc query eaanticheat' }
Sec 'sc query type= driver state= all (EA-ish)' { Cmd 'sc query type= driver state= all | findstr /i "ea apex javelin"' }
Sec 'driverquery EA' { Cmd 'driverquery /fo table | findstr /i "ea apex javelin"' }

Sec 'CodeIntegrity/Operational events (last 40)' {
  try {
    Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 40 -ErrorAction Stop |
      ForEach-Object { W (($_.TimeCreated.ToString('MM-dd HH:mm:ss') + "`t" + $_.Id + "`t" + (($_.Message -replace "`r?`n", ' ')).Substring(0, [Math]::Min(300, $_.Message.Length)))) }
  } catch { W ('ERR: ' + $_.Exception.Message) }
}

Sec 'Application+System events mentioning EA/anticheat (last 3 days)' {
  try {
    $t0 = (Get-Date).AddDays(-3)
    Get-WinEvent -FilterHashtable @{ LogName = 'Application', 'System'; StartTime = $t0 } -MaxEvents 400 -ErrorAction Stop |
      Where-Object { $_.Message -match '(?i)eaanticheat|javelin|skyfall|security violation' } |
      Select-Object -First 40 |
      ForEach-Object { W (($_.TimeCreated.ToString('MM-dd HH:mm:ss') + "`t" + $_.LogName + "`t" + $_.Id + "`t" + $_.ProviderName + "`t" + (($_.Message -replace "`r?`n", ' ')).Substring(0, [Math]::Min(300, $_.Message.Length)))) }
  } catch { W ('ERR: ' + $_.Exception.Message) }
}

W ''
W ('=== DONE ' + (Get-Date) + ' ===')
$sw.Flush(); $sw.Close()
