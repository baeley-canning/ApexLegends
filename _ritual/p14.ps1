$out = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p14.txt'
$adm = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole('Administrators')
function W($s){ $s | Out-File -FilePath $out -Append -Encoding UTF8 }
W("=== p14 $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss') admin=$adm ===")
W("")
W("########## 1 EA\AC folder recursive (size/date) ##########")
Get-ChildItem 'C:\Program Files\EA\AC' -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
  if ($_.PSIsContainer) { W("  DIR  " + $_.FullName) }
  else { W(("{0,12} {1} {2}" -f $_.Length, $_.LastWriteTime.ToString('dd/MM/yyyy HH:mm:ss'), $_.FullName)) }
}
W("")
W("########## 2 eaanticheat.sys / apexdrv.sys existence hunt ##########")
$paths = @(
 'C:\Windows\System32\drivers\eaanticheat.sys',
 'C:\Windows\System32\drivers\apexdrv.sys',
 'C:\ProgramData\QwenKern\apexdrv.sys',
 'C:\Program Files\EA\AC\eaanticheat.sys',
 'C:\Program Files\EA\AC\apexdrv.sys',
 'C:\Program Files\EA\AC\EAAntiCheat.sys'
)
foreach($p in $paths){ try { W(("EXIST={0} {1}" -f [IO.File]::Exists($p), $p)) } catch { W("ERR " + $p) } }
W("-- wildcard hunt in drivers dir (ea|apex|javelin):")
Get-ChildItem 'C:\Windows\System32\drivers' -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'ea|apex|javelin' } | ForEach-Object { W(("   {0,10} {1} {2}" -f $_.Length,$_.LastWriteTime.ToString('dd/MM/yyyy HH:mm:ss'),$_.FullName)) }
W("-- DriverStore hunt (eaanticheat|apexdrv|gameflt):")
Get-ChildItem 'C:\Windows\System32\DriverStore\FileRepository' -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'eaanticheat|apexdrv|gameflt' } | ForEach-Object { W("   DIR " + $_.FullName); Get-ChildItem $_.FullName -Force -ErrorAction SilentlyContinue | ForEach-Object { W("      " + $_.Name + "  " + $_.Length) } }
W("-- Win32_SystemDriver / Win32_Service state+excode:")
Get-CimInstance Win32_SystemDriver -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'eaanti|apexdrv|zzprobe|kernprobe|gdrv3' } | ForEach-Object { W("   DRV $($_.Name) State=$($_.State) Status=$($_.Status) Start=$($_.StartMode) Path=$($_.PathName)") }
Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'eaanti' } | ForEach-Object { W("   SVC $($_.Name) State=$($_.State) ExitCode=$($_.ExitCode) hex=$('0x{0:X8}' -f $_.ExitCode) Path=$($_.PathName)") }
W("")
W("########## 3 service keys live snapshot ##########")
foreach($n in 'apexdrv','zzprobe','kernprobe','EAAntiCheat','eaanticheat','EAAntiCheatService','gdrv3'){
  $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$n"
  if (Test-Path $k) {
    try {
      $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
      $so = Get-ItemProperty ($k + '\StartOverride') -ErrorAction SilentlyContinue
      W("-- $n : ImagePath=$($p.ImagePath) Type=$($p.Type) Start=$($p.Start) Group=$($p.Group) Tag=$($p.Tag) DisplayName=$($p.DisplayName) StartOverride=$($so.1) FilterType=$($p.FilterType) Altitude=$($p.Altitude)")
      $subs = (Get-ChildItem $k -ErrorAction SilentlyContinue | ForEach-Object { $_.PSChildName }) -join ','
      W("   subkeys: $subs")
      $vals = (Get-Item $k).GetValueNames() -join ','
      W("   valuenames: $vals")
    } catch { W("-- $n : ERR " + $_.Exception.Message) }
  } else { W("-- $n : KEY MISSING") }
}
W("")
W("########## 4 fltmc + driverquery (EA/apex lines) ##########")
foreach($c in 'fltmc filters','fltmc instances'){
  W("-- cmd: $c")
  try { (cmd /c $c 2>&1) | ForEach-Object { W("   " + $_) } } catch { W("   ERR " + $_.Exception.Message) }
}
W("-- cmd: driverquery /v /fo csv filtered")
try { (cmd /c 'driverquery /v /fo csv | findstr /i "eaanti apexdrv gdrv3 javelin filetrace fltmgr gameflt"' 2>&1) | ForEach-Object { W("   " + $_) } } catch { W("   ERR " + $_.Exception.Message) }

W("")
W("########## 5 popup-string scan of EA\AC binaries ##########")
$pats = @('Security Violation','SECURITY VIOLATION','Security violation','Test Signing','TESTSIGNING','testsigning','HVCI','Virtualization Based Security','issuer_fetcher','trust certificate','AAA Certificate','device_attestation','antitamper','unsupported')
foreach($f in (Get-ChildItem 'C:\Program Files\EA\AC' -Recurse -Force -File -ErrorAction SilentlyContinue)){
  if ($f.Extension -notmatch '^\.(exe|dll|sys|cfg|json)$') { continue }
  if ($f.Length -eq 0) { continue }
  $found = New-Object System.Collections.ArrayList
  try {
    $fs=[IO.File]::Open($f.FullName,'Open','Read','ReadWrite')
    $buf=New-Object byte[] 4194304
    $pos=0
    while(($read=$fs.Read($buf,0,$buf.Length)) -gt 0){
      $t=[Text.Encoding]::ASCII.GetString($buf,0,$read)
      foreach($pt in $pats){
        $i=0
        while(($i=$t.IndexOf($pt,$i)) -ge 0){
          $st=[Math]::Max(0,$i-50)
          $ctx=$t.Substring($st,[Math]::Min(200,$t.Length-$st)) -replace "[^\x20-\x7E]","."
          [void]$found.Add(("[{0}] @0x{1:X} :: {2}" -f $pt,($pos+$i),$ctx))
          $i += $pt.Length
          if($found.Count -gt 220){break}
        }
        if($found.Count -gt 220){break}
      }
      $pos += $read
      if($found.Count -gt 220){break}
    }
    $fs.Dispose()
  } catch { W("ERRSCAN " + $f.FullName + " : " + $_.Exception.Message) }
  if($found.Count){
    W("== " + $f.FullName + "  len=" + $f.Length + "  hits=" + $found.Count)
    $found | Select-Object -First 40 | ForEach-Object { W("   " + $_) }
  }
}
W("")
W("########## 6 EA log inventory + tails ##########")
$roots = @('C:\ProgramData\EA','C:\ProgramData\Electronic Arts',($env:LOCALAPPDATA + '\EA Desktop'),'C:\Program Files\EA\AC')
$logs = @()
foreach($r in $roots){ if(Test-Path $r){ $logs += Get-ChildItem $r -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 -and $_.Extension -match '^\.(log|txt|dmp|json)$' } } }
W("-- newest 30 EA logs:")
$logs | Sort-Object LastWriteTime -Descending | Select-Object -First 30 | ForEach-Object { W(("   {0} {1,10} {2}" -f $_.LastWriteTime.ToString('dd/MM/yyyy HH:mm:ss'),$_.Length,$_.FullName)) }
foreach($lg in ($logs | Where-Object { $_.Name -match 'eaanti|javelin|anticheat|GameService' } | Sort-Object LastWriteTime -Descending | Select-Object -First 4)){
  W("-- tail 70 of: " + $lg.FullName)
  try { Get-Content $lg.FullName -Tail 70 -ErrorAction SilentlyContinue | ForEach-Object { W("   " + $_) } } catch { W("   ERR") }
}
W("")
W("########## 7 PendingFileRenameOperations now ##########")
try { $pf=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager').PendingFileRenameOperations; if($pf){ $pf | ForEach-Object { W("   " + $_) } } else { W("   <none>") } } catch { W("   ERR " + $_.Exception.Message) }
W("")
W("########## 8 boot options / VBS / DeviceGuard ##########")
try { W("SystemStartOptions=" + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions).SystemStartOptions) } catch { W("ERR startoptions") }
try { $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
  W("   VbsStatus=$($dg.VirtualizationBasedSecurityStatus) ServicesConfigured=$($dg.SecurityServicesConfigured -join ',') ServicesRunning=$($dg.SecurityServicesRunning -join ',') CiPolicyEnforcement=$($dg.CodeIntegrityPolicyEnforcementStatus) UsermodeCiEnforcement=$($dg.UsermodeCodeIntegrityPolicyEnforcementStatus)")
} catch { W("   ERR deviceguard: " + $_.Exception.Message) }
try { W("   CiPolicyActive=" + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\State' -ErrorAction SilentlyContinue).CiPolicyActive) } catch {}
W("")
W("== p14 END $(Get-Date -Format 'HH:mm:ss') ==")

