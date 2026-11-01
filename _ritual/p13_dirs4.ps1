# p13_dirs4 : timeline + foreign kernel surface + exit-code mapping
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p13_dirs4.txt'
$ErrorActionPreference = 'SilentlyContinue'
function W($s) { $s | Out-File -FilePath $out -Append -Encoding UTF8 }
$adm = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole('Administrators')
W("=== p13 dirs4 $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss') admin=$adm ===")

W("`n########## A1 ALL 'Application Popup' events ever ##########")
Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Application Popup'} -MaxEvents 500 | ForEach-Object {
  $m = ($_.Message -replace "`r?`n", ' ')
  W("$($_.TimeCreated) id=$($_.Id) :: " + $m.Substring(0, [Math]::Min(250, $m.Length)))
}

W("`n########## A2 Javelin popups per day + oldest/newest ##########")
$all = Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Application Popup'} -MaxEvents 500 |
  Where-Object { $_.Message -match 'Javelin|Security Violation' } | Sort-Object TimeCreated
if ($all) {
  $all | Group-Object { $_.TimeCreated.ToString('yyyy-MM-dd') } | ForEach-Object {
    $g = $_.Group | Sort-Object TimeCreated
    W("$($_.Name) count=$($_.Count) first=$($g[0].TimeCreated) last=$($g[-1].TimeCreated)")
  }
  W("OLDEST Javelin popup in log: $($all[0].TimeCreated)  NEWEST: $($all[-1].TimeCreated)  total=$($all.Count)")
} else { W('no Javelin popups in Application log') }
W("`n########## A2b popup string variants ##########")
$all | ForEach-Object { W((($_.Message -replace "`r?`n", ' '))) } | Out-Null
($all | ForEach-Object { ($_.Message -replace "`r?`n", ' ') } | Sort-Object -Unique) | ForEach-Object { W("   VARIANT: " + $_.Substring(0, [Math]::Min(400, $_.Length))) }

W("`n########## A3 SCM 7023/7045/7031/7034 for EA/apex/Qwen (120d) ##########")
Get-WinEvent -FilterHashtable @{LogName='System'; Id=7023,7045,7031,7034; StartTime=(Get-Date).AddDays(-120)} -MaxEvents 4000 |
  Where-Object { $_.Message -match 'EAAntiCheat|eaanticheat|apexdrv|Javelin|QwenKern' } | ForEach-Object {
    $m = ($_.Message -replace "`r?`n", ' ')
    W("$($_.TimeCreated) [$($_.ProviderName)] id=$($_.Id) :: " + $m.Substring(0, [Math]::Min(230, $m.Length)))
  }

W("`n########## A4 FilterManager events for EAAntiCheat/apexdrv (120d) ##########")
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-FilterManager'; StartTime=(Get-Date).AddDays(-120)} -MaxEvents 4000 |
  Where-Object { $_.Message -match 'EAAntiCheat|apexdrv|QwenKern' } | ForEach-Object {
    $m = ($_.Message -replace "`r?`n", ' ')
    W("$($_.TimeCreated) id=$($_.Id) :: " + $m.Substring(0, [Math]::Min(190, $m.Length)))
  }

W("`n########## A5 CodeIntegrity Operational events mentioning apexdrv/QwenKern (120d) ##########")
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-CodeIntegrity/Operational'; StartTime=(Get-Date).AddDays(-120)} -MaxEvents 5000 |
  Where-Object { $_.Message -match 'apexdrv|QwenKern' } | ForEach-Object {
    $m = ($_.Message -replace "`r?`n", ' ')
    W("$($_.TimeCreated) id=$($_.Id) [$($_.LevelDisplayName)] :: " + $m.Substring(0, [Math]::Min(280, $m.Length)))
  }

W("`n########## B1 apexdrv / eaanticheat file + signature facts ##########")
foreach ($p in 'C:\Windows\System32\drivers\apexdrv.sys', 'C:\ProgramData\QwenKern\apexdrv.sys', 'C:\Windows\System32\drivers\eaanticheat.sys') {
  W("-- $p")
  $i = Get-Item $p
  if (-not $i) { W('   MISSING'); continue }
  $s = Get-AuthenticodeSignature $p
  W("   Len=$($i.Length) Created=$($i.CreationTime) Written=$($i.LastWriteTime) Ver=$($i.VersionInfo.FileVersion)")
  W("   SigStatus=$($s.Status) Type=$($s.SignatureType) Msg=$($s.StatusMessage)")
  W("   SHA256=" + (Get-FileHash $p -Algorithm SHA256).Hash)
  if ($s.SignerCertificate) {
    W("   Signer=$($s.SignerCertificate.Subject)")
    W("   Issuer=$($s.SignerCertificate.Issuer) NotBefore=$($s.SignerCertificate.NotBefore) NotAfter=$($s.SignerCertificate.NotAfter)")
  }
}
W("`n-- apexdrv embedded (nested) certs count via .p7b style probe")
try { (Get-AuthenticodeSignature 'C:\Windows\System32\drivers\apexdrv.sys').SignerCertificate.RawData.Length } catch {}

W("`n########## B2 cert stores: dev/test/AAA hunt ##########")
foreach ($st in 'Cert:\LocalMachine\Root', 'Cert:\LocalMachine\CA', 'Cert:\CurrentUser\Root', 'Cert:\CurrentUser\CA') {
  $items = Get-ChildItem $st
  $hits = $items | Where-Object { $_.Subject -match 'ApexDrv|Qwen|Kern|AAA Certificate|Test' }
  W("-- $st total=$($items.Count) matches=$($hits.Count)")
  $hits | ForEach-Object { W("   [$($_.Subject)] $($_.NotBefore) -> $($_.NotAfter) Thumb=$($_.Thumbprint)") }
  if ($st -eq 'Cert:\LocalMachine\Root') {
    W("   -- newest 12 by NotBefore:")
    $items | Sort-Object NotBefore -Descending | Select-Object -First 12 | ForEach-Object { W("      $($_.NotBefore) $($_.Subject) thumb=$($_.Thumbprint)") }
  }
}
W("`n-- AAA root exact match anywhere (Subject -match 'AAA Certificate Services')")
foreach ($st in 'Cert:\LocalMachine\Root', 'Cert:\LocalMachine\CA', 'Cert:\LocalMachine\AuthRoot', 'Cert:\LocalMachine\Trust', 'Cert:\CurrentUser\Root') {
  Get-ChildItem $st | Where-Object { $_.Subject -match 'AAA Certificate Services' } | ForEach-Object { W("   FOUND in $st : $($_.Subject) thumb=$($_.Thumbprint) SHA1=$($_.SerialNumber)") }
}

W("`n########## C1 kernel/file-system driver services with non-MS or invalid image ##########")
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' | ForEach-Object {
  $pr = Get-ItemProperty $_.PSPath
  if (($pr.Type -in 1, 2) -and $pr.ImagePath) {
    $ip = $pr.ImagePath -replace '^\\\?\?\\', ''
    if ($ip -match '^system32\\') { $ip = 'C:\Windows\' + $ip }
    elseif ($ip -match '^\\SystemRoot\\') { $ip = 'C:\Windows\' + ($ip -replace '^\\SystemRoot\\', '') }
    elseif ($ip -notmatch '^[A-Za-z]:') { $ip = 'C:\Windows\' + $ip }
    $s = Get-AuthenticodeSignature $ip
    $subj = if ($s.SignerCertificate) { $s.SignerCertificate.Subject } else { '<none>' }
    if (($s.Status -ne 'Valid') -or ($subj -notmatch 'Microsoft')) {
      W(($_.PSChildName + ' | Start=' + $pr.Start + ' | Type=' + $pr.Type + ' | ' + $ip + ' | Status=' + $s.Status + ' | Signer=' + $subj))
    }
  }
}

W("`n########## C2 all FSFilter-group drivers ##########")
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' | ForEach-Object {
  $pr = Get-ItemProperty $_.PSPath
  if ($pr.Group -match 'FSFilter') { W(($_.PSChildName + ' | ' + $pr.Group + ' | Tag=' + $pr.Tag + ' | Start=' + $pr.Start + ' | ' + $pr.ImagePath)) }
}

W("`n########## H1 last boot + apexdrv/zzprobe events SINCE that boot (was it resident at popup?) ##########")
$os = Get-CimInstance Win32_OperatingSystem
W("LastBootUpTime = $($os.LastBootUpTime)")
$boot = $os.LastBootUpTime
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$boot} -MaxEvents 6000 |
  Where-Object { $_.Message -match 'apexdrv|zzprobe|QwenKern' } | ForEach-Object {
    $m = ($_.Message -replace "`r?`n", ' ')
    W("   $($_.TimeCreated) id=$($_.Id) [$($_.ProviderName)] :: " + $m.Substring(0, [Math]::Min(200, $m.Length)))
  }
W("-- Win32_SystemDriver matches:")
Get-CimInstance Win32_SystemDriver | Where-Object { $_.Name -match 'apex|zzprobe|eaac|EAAnti' } | ForEach-Object { W("   $($_.Name) state=$($_.State) start=$($_.StartMode) path=$($_.PathName)") }
W("-- service keys now:")
foreach ($k in 'apexdrv', 'zzprobe', 'EAAntiCheat', 'EAAntiCheatService', 'eaanticheat') {
  $p = Get-ItemProperty ("HKLM:\SYSTEM\CurrentControlSet\Services\" + $k)
  if ($p) { W("   $k : Start=$($p.Start) Type=$($p.Type) Image=$($p.ImagePath) Group=$($p.Group) Tag=$($p.Tag)") } else { W("   $k : <no key>") }
}
W("-- object namespace Device scan:")
try { Get-ChildItem -Path '\\.\GLOBALROOT\Device' -Force | Where-Object { $_.Name -match 'apex|Apex|zzprobe|eaac|EAAnti' } | ForEach-Object { W("   DEV $($_.Name)") } } catch { W("   Device scan failed: $($_.Exception.Message)") }

W("`n########## H2 boot history (system uptime events) ##########")
Get-WinEvent -FilterHashtable @{LogName='System'; Id=6005,6006,6008,6013; StartTime=(Get-Date).AddDays(-14)} -MaxEvents 200 | ForEach-Object { W("   $($_.TimeCreated) id=$($_.Id) [$($_.ProviderName)]") }

W("`n########## D1 exit code 0xFFFF57A6 / 0x000057A6 occurrences in GameService.exe ##########")
$f = 'C:\Program Files\EA\AC\EAAntiCheat.GameService.exe'
$b = [IO.File]::ReadAllBytes($f)
W("file=$f bytes=$($b.Length)")
foreach ($pat in @(@(0xA6, 0x57, 0xFF, 0xFF), @(0xA6, 0x57, 0x00, 0x00))) {
  $hits = New-Object System.Collections.ArrayList
  $o = -1
  while (($o = [Array]::IndexOf($b, [byte]$pat[0], $o + 1)) -ge 0) {
    if (($o + 3) -lt $b.Length -and $b[$o + 1] -eq $pat[1] -and $b[$o + 2] -eq $pat[2] -and $b[$o + 3] -eq $pat[3]) { [void]$hits.Add($o) }
    if ($hits.Count -gt 300) { break }
  }
  $name = ($pat | ForEach-Object { $_.ToString('X2') }) -join ' '
  W("pattern $name -> $($hits.Count) hit(s)")
  $n = 0
  foreach ($h in $hits) {
    $n++; if ($n -gt 15) { break }
    $st = [Math]::Max(0, $h - 40)
    $ctx = [Text.Encoding]::ASCII.GetString($b, $st, [Math]::Min(110, $b.Length - $st)) -replace '[^\x20-\x7E]', '.'
    W(("   off=0x{0:X}  ...{1}..." -f $h, $ctx))
  }
}

W("`n########## D2 ascii strings with 57A6 / attest / testsign / secureboot / hvci ##########")
$txt = [Text.Encoding]::ASCII.GetString($b)
foreach ($k in '57A6', 'Attest', 'attest', 'TestSign', 'testsign', 'SecureBoot', 'Secure Boot', 'HVCI', 'VBS', 'Hypervisor', 'hypervisor', 'Javelin', 'Skyfall', 'skyfall', 'unacceptable', 'tampering') {
  $idx = 0; $c = 0
  while (($idx = $txt.IndexOf($k, $idx)) -ge 0 -and $c -lt 6) {
    $c++
    $st = [Math]::Max(0, $idx - 45)
    W("$k @0x$($idx.ToString('X')) : " + ($txt.Substring($st, [Math]::Min(100, $txt.Length - $st)) -replace '[^\x20-\x7E]', '.'))
    $idx += $k.Length
  }
}

W("`n########## E1 EA log dirs + Javelin/attestation grep ##########")
$logDirs = 'C:\ProgramData\EA Desktop\Logs', 'C:\ProgramData\eaanticheat', 'C:\Users\New User\AppData\Local\Electronic Arts', 'C:\Users\New User\AppData\Roaming\Electronic Arts', 'C:\Users\New User\AppData\Local\EA'
foreach ($d in $logDirs) {
  W("-- $d")
  Get-ChildItem $d -Recurse -Force -File | Select-Object -First 60 | ForEach-Object { W("   $($_.LastWriteTime) $($_.Length) $($_.FullName)") }
}
W("`n-- grep: Javelin|attest|Session ID|Violation|unacceptable|apexdrv in EA logs")
Get-ChildItem 'C:\ProgramData\EA Desktop\Logs' -Recurse -File | Where-Object { $_.Extension -match 'log|txt' } | ForEach-Object {
  $fp = $_.FullName
  Select-String -Path $fp -Pattern 'Javelin', 'attest', 'Session ID', 'Violation', 'unacceptable', 'apexdrv', 'skyfall' -ErrorAction SilentlyContinue |
    Select-Object -First 40 | ForEach-Object { W("   [$([IO.Path]::GetFileName($fp)):$($_.LineNumber)] " + ($_.Line -replace "`r?`n", ' ')) }
}

W("`n########## E2 crashdumps + WER for EA AC ##########")
Get-ChildItem 'C:\ProgramData\eaanticheat' -Recurse -Force | ForEach-Object { W("   $($_.LastWriteTime) $($_.Length) $($_.FullName)") }
foreach ($wdir in 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive', 'C:\ProgramData\Microsoft\Windows\WER\ReportQueue', 'C:\Users\New User\AppData\Local\Microsoft\Windows\WER') {
  W("-- $wdir")
  Get-ChildItem $wdir -Recurse -Force | Where-Object { $_.Name -match 'EAnti|EAAnti|GameService|eaanti' } | Sort-Object LastWriteTime -Descending | Select-Object -First 20 | ForEach-Object { W("   $($_.LastWriteTime) $($_.FullName)") }
}
$wer = Get-ChildItem 'C:\ProgramData\Microsoft\Windows\WER' -Recurse -Force -Filter 'Report.wer' | Sort-Object LastWriteTime -Descending | Select-Object -First 6
foreach ($w in $wer) { W("-- $($w.FullName)"); Get-Content $w.FullName -TotalCount 45 | ForEach-Object { W("     " + ($_ -replace "`r?`n", '')) } }

W("`n########## F1 pending rename / reboot flags ##########")
(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations).PendingFileRenameOperations | ForEach-Object { W("   PFR : $_") }
$p2 = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations2).PendingFileRenameOperations2
$p2 | ForEach-Object { W("   PFR2: $_") }
W("RebootPending=" + (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') + " WU_RebootRequired=" + (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'))

W("`n########## G1 System32\drivers written last 7 days ##########")
Get-ChildItem 'C:\Windows\System32\drivers\*.sys' -Force | Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-7) } | Sort-Object LastWriteTime -Descending | ForEach-Object { W("   $($_.LastWriteTime) $($_.Length) $($_.Name)") }
W("`n### G2 C:\Boot + SystemStartOptions")
Get-ChildItem 'C:\Boot' -Force | ForEach-Object { W("   $($_.LastWriteTime) $($_.Length) $($_.Name)") }
W("   SystemStartOptions=" + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions).SystemStartOptions)
W("`n=== END $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss') ===")


