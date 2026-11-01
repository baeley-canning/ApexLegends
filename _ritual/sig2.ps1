$out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\sig2.txt'
$strip = '^\?\?\??'   # placeholder, set properly below
function P2([string]$p) { return ($p -replace '^\\\?\?\\', '') }

'=== signature of suspect / non-MS driver services ===' | Set-Content -LiteralPath $out

$names = 'gdrv3','MSIO','CTIIO','npcap','VBoxSup','VBoxUSBMon','VBoxNetLwf','VBoxNetAdp','TeamViewer','TeamViewerVPN','tv_x64','tv_w32','apexdrv'
foreach ($n in $names) {
  $d = Get-CimInstance Win32_SystemDriver -Filter "Name='$n'" -ErrorAction SilentlyContinue
  if ($d) {
    $p = P2 $d.PathName
    $s = Get-AuthenticodeSignature -LiteralPath $p -ErrorAction SilentlyContinue
    $fv = (Get-Item -LiteralPath $p -ErrorAction SilentlyContinue).VersionInfo.FileVersion
    ("{0} | State={1} | Start={2} | SigStatus={3} | Path={4} | FileVersion={5}" -f $n, $d.State, $d.StartMode, $(if ($s) { [string]$s.Status } else { 'NOFILE' }), $p, $fv) | Add-Content -LiteralPath $out
    if ($s -and $s.SignerCertificate) {
      ("   Signer={0}" -f $s.SignerCertificate.Subject) | Add-Content -LiteralPath $out
      ("   Issuer={0} | NotBefore={1} | NotAfter={2}" -f $s.SignerCertificate.Issuer, $s.SignerCertificate.NotBefore, $s.SignerCertificate.NotAfter) | Add-Content -LiteralPath $out
      ("   StatusMessage={0}" -f $s.StatusMessage) | Add-Content -LiteralPath $out
    }
  } else {
    ("{0} : service NOT present" -f $n) | Add-Content -LiteralPath $out
  }
}

'=== ALL running drivers with a non-Microsoft signer (detailed) ===' | Add-Content -LiteralPath $out
foreach ($d in (Get-CimInstance Win32_SystemDriver | Where-Object { $_.State -eq 'Running' })) {
  $p = P2 $d.PathName
  $s = Get-AuthenticodeSignature -LiteralPath $p -ErrorAction SilentlyContinue
  if ($s -and $s.SignerCertificate -and $s.SignerCertificate.Subject -notmatch 'Microsoft') {
    ("{0} | {1} | {2} | {3}" -f $d.Name, $s.Status, $s.SignerCertificate.Subject, $p) | Add-Content -LiteralPath $out
  }
}

'=== every running driver from a non-Windows vendor path (teamviewer/npcap/vbox/gigabyte/msi/creative/sandboxie) ===' | Add-Content -LiteralPath $out
(Get-CimInstance Win32_SystemDriver | Where-Object { $_.PathName -match '(?i)teamviewer|npcap|vbox|gigabyte|msio|ctiio|gdrv|sandbox|winring|glckio|ausb' } | Select-Object Name, State, StartMode, PathName | Format-Table -Auto | Out-String -Width 250) | Add-Content -LiteralPath $out

'=== apexdrv service query ===' | Add-Content -LiteralPath $out
(sc.exe query apexdrv 2>&1 | Out-String) | Add-Content -LiteralPath $out
'=== sc qc apexdrv (config / start type after p9) ===' | Add-Content -LiteralPath $out
(sc.exe qc apexdrv 2>&1 | Out-String) | Add-Content -LiteralPath $out

'=== bcdedit /enum {current} ===' | Add-Content -LiteralPath $out
(bcdedit /enum '{current}' 2>&1 | Out-String) | Add-Content -LiteralPath $out

'=== is testsigning / nointegritychecks currently ON? (Win32 query) ===' | Add-Content -LiteralPath $out
(Get-CimInstance -Namespace root\wmi -ClassName SystemBootConfigurationString -ErrorAction SilentlyContinue | Format-List * | Out-String) | Add-Content -LiteralPath $out

'=== CodeIntegrity operational events since today 00:00 ===' | Add-Content -LiteralPath $out
(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-CodeIntegrity/Operational'; StartTime = (Get-Date).Date } -ErrorAction SilentlyContinue | Select-Object TimeCreated, Id, @{ n = 'Msg'; e = { ($_.Message -split "`r?`n")[0] } } | Format-Table -Auto | Out-String -Width 250) | Add-Content -LiteralPath $out

'=== currently running anti-cheat / apex related processes ===' | Add-Content -LiteralPath $out
(Get-Process | Where-Object { $_.Name -match '(?i)apex|anticheat|javelin|easy|eac|teamviewer|gdrv|vbox|npcap' } | Select-Object Name, Id, Path | Format-Table -Auto | Out-String -Width 250) | Add-Content -LiteralPath $out

'DONE ' + (Get-Date) | Add-Content -LiteralPath $out
