# h317_post.ps1 - logon restore, armed by h317_arm.ps1 (task p317post). Runs only if the box died.
# Restores DSE to the value recorded BEFORE arming (h317.dsepre, default 6), removes the driver,
# puts AutoReboot back, deletes the task, and reports the dump if there is one.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h317_post.out'
$alt  = 'C:\Users\Public\p37\h317_post.out'
$d    = 'C:\Users\Public\p37'
function Lg([string]$s) {
    $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s
    if (-not (Add-Content -LiteralPath $out -Value $line -EA 0 -PassThru)) { Add-Content -LiteralPath $alt -Value $line -EA 0 }
    Write-Host $line
}
Add-Content -LiteralPath $out -Value ('===== h317 post ' + (Get-Date -f 's') + ' =====') -EA 0
Lg ('boot=' + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('dd/MM HH:mm:ss'))
$want = '6'
$pf = Join-Path $d 'h317.dsepre'
if (Test-Path $pf) { $want = (Get-Content $pf -EA 0 | Select-Object -First 1).Trim(); if (-not $want) { $want = '6' } }
Lg ('dse restore target=' + $want + ' (from h317.dsepre)')
$kdu = Join-Path $d 'kdu.exe'
function Kdu([string[]]$a) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $kdu; $psi.Arguments = ($a -join ' '); $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.WorkingDirectory = $d
    try { $p = [System.Diagnostics.Process]::Start($psi)
          $t1 = $p.StandardOutput.ReadToEndAsync(); $t2 = $p.StandardError.ReadToEndAsync()
          if (-not $p.WaitForExit(25000)) { try { $p.Kill() } catch { } }
          Start-Sleep -Milliseconds 150
          return (($t1.Result + $t2.Result) -replace '\s+', ' ').Trim() } catch { return ('FAIL ' + $_.Exception.Message) }
}
$cur = ''; $r = Kdu @('-prv', '20', '-dse')
if ($r -match 'value:\s*([0-9A-Fa-f]+)') { $cur = $matches[1] }
Lg ('pre read=0x' + $(if ($cur) { $cur } else { 'UNREADABLE' }))
if ($cur -and ([Convert]::ToInt32($cur, 16) -ne [int]$want)) {
    Lg ('write out=[' + (Kdu @('-prv', '20', '-dse', "$want")) + ']')
    Start-Sleep -Milliseconds 500
    $r2 = Kdu @('-prv', '20', '-dse')
    $post = if ($r2 -match 'value:\s*([0-9A-Fa-f]+)') { $matches[1] } else { '' }
    Lg ('post read=0x' + $(if ($post) { $post } else { 'UNREADABLE' }))
    $dv = if ($post -and ([Convert]::ToInt32($post, 16) -eq [int]$want)) { 'PASS' } else { 'FAIL' }
} else { $dv = 'PASS(already)' }
Lg ('dse_verify=' + $dv)
foreach ($s in 'zapexdrv', 'apexdrv') { & "$env:SystemRoot\system32\sc.exe" delete $s 2>&1 | Out-Null }
Lg ('svc after delete: ' + (((& "$env:SystemRoot\system32\sc.exe" query zapexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|does not exist' }) -join ' | ').Trim())
Set-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name AutoReboot -Value 1 -Type DWord
Lg ('AutoReboot readback=' + (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl').AutoReboot)
Get-Process notepad, regedit, mmc -EA 0 | Stop-Process -Force -EA 0
schtasks.exe /delete /tn p317post /f 2>&1 | Out-Null
$bc = @(Get-WinEvent -FilterHashtable @{LogName = 'System'; Id = 1001; StartTime = (Get-Date).AddHours(-6)} -EA 0)
if ($bc.Count) { foreach ($e in $bc) { Lg ('BUGCHECK ' + $e.TimeCreated.ToString('s') + ' :: ' + (($e.Message -replace '\s+', ' ').Trim())) } } else { Lg 'no 1001 in the last 6h' }
$dmp = @(Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -EA 0 | Sort-Object LastWriteTime -Descending | Select-Object -First 2)
foreach ($f in $dmp) { Lg ('dump ' + $f.Name + ' ' + $f.Length + 'b ' + $f.LastWriteTime.ToString('s')) }
Lg ('state: dse_verify=' + $dv + ' auto=' + (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl').AutoReboot + ' dumps=' + $dmp.Count)
