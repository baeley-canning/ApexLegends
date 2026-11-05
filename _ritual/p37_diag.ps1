# p37_diag.ps1 - READ-ONLY guest diagnosis of the dead tick chain. Writes diag.out.
# No mutation: no task re-register, no service create, no dse write.
$d = 'C:\Users\Public\p37'
$o = New-Object System.Collections.ArrayList
function W([string]$s) { [void]$o.Add($s) }
W ('now=' + (Get-Date -f 'HH:mm:ss') + ' pid=' + $PID + ' as=' + [Security.Principal.WindowsIdentity]::GetCurrent().Name)
W ('os=' + (Get-CimInstance Win32_OperatingSystem).Caption + ' build=' + (Get-CimInstance Win32_OperatingSystem).BuildNumber)
W ('dir exists=' + (Test-Path $d))
if (Test-Path $d) { foreach ($f in (Get-ChildItem $d -Force -EA 0 | Sort-Object LastWriteTime)) { W ('  file ' + $f.Name + ' ' + $f.Length + 'B ' + $f.LastWriteTime.ToString('MM-dd HH:mm:ss')) } }
W '--- task ---'
$t = & "$env:SystemRoot\system32\schtasks.exe" /query /tn p37tick /v /fo list 2>&1
if ($LASTEXITCODE -ne 0) { W ('schtasks rc=' + $LASTEXITCODE) }
foreach ($l in $t) { if ($l -match 'TaskName|Status|Next Run|Last Run|Last Result|Task To Run|Run As User|Scheduled Task State|Start In|Repeat|Task Type|Logon Mode|Author|Schedule Type|Start') { W ('  t| ' + $l.Trim()) } }
W '--- service ---'
W ((& "$env:SystemRoot\system32\sc.exe" query apexdrv 2>&1) -join ' ')
W ('svc regkey=' + (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\apexdrv'))
$ip = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\apexdrv' -EA 0).ImagePath
W ('svc imagepath=[' + $ip + ']')
W '--- boot ---'
W (((& "$env:SystemRoot\system32\bcdedit.exe" /enum '{current}' 2>&1) | Select-String 'testsigning|nointegritychecks|hypervisorlaunchtype') -join ' | ')
W '--- who is listening / agent ---'
W ('explorer pid=' + ((Get-Process explorer -EA 0).Id -join ','))
W '--- newest outs ---'
foreach ($f in (Get-ChildItem $d -Filter '*.out' -EA 0 | Sort-Object LastWriteTime -Desc | Select-Object -First 2)) {
    W ('  tail ' + $f.Name)
    Get-Content -LiteralPath $f.FullName -Tail 12 -EA 0 | ForEach-Object { W ('    | ' + $_) }
}
W '--- guest log tail ---'
$g = Join-Path $d 'guest.log'
if (Test-Path $g) { Get-Content -LiteralPath $g -Tail 25 -EA 0 | ForEach-Object { W ('  g| ' + $_) } } else { W '  no guest.log' }
Set-Content -LiteralPath (Join-Path $d 'diag.out') -Value ($o -join "`r`n")
