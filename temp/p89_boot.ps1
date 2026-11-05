$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
Set-Location -LiteralPath $repo
$o = 'C:\Users\New User\AppData\Local\Temp\_boot_report.txt'
Remove-Item -LiteralPath $o -ErrorAction SilentlyContinue
function W($s) { $s | Out-File -LiteralPath $o -Append -Encoding utf8 }

$os = Get-CimInstance Win32_OperatingSystem
W ("now={0} boot={1} up_min={2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss'), [Math]::Round(((Get-Date) - $os.LastBootUpTime).TotalMinutes, 1))

W '--- shutdown/bugcheck events (20 min) ---'
try {
  $ev = Get-WinEvent -FilterHashtable @{LogName = 'System'; StartTime = (Get-Date).AddMinutes(-20)} -ErrorAction Stop
  $ev | Where-Object { $_.Id -in 41, 1001, 6008, 6009, 1101, 109 } | Select-Object -First 8 | ForEach-Object {
    W ("{0} id={1} src={2} :: {3}" -f $_.TimeCreated.ToString('HH:mm:ss'), $_.Id, $_.ProviderName, (($_.Message -replace '\s+', ' ').Trim()))
  }
} catch { W ('event query threw: ' + $_) }

W '--- dumps ---'
$md = Get-ChildItem 'C:\Windows\Minidump' -ErrorAction SilentlyContinue
W ('minidump_count=' + ($md | Measure-Object).Count + ' memory_dmp=' + (Test-Path 'C:\Windows\MEMORY.DMP'))
$md | Sort-Object LastWriteTime -Descending | Select-Object -First 3 | ForEach-Object { W ("dump {0} {1} {2}" -f $_.Name, $_.LastWriteTime.ToString('HH:mm:ss'), $_.Length) }

W '--- driver ---'
$q = & sc.exe query gdrv3 2>&1
$q | ForEach-Object { W ('  ' + ($_ -replace '\s+', ' ').Trim()) }

W '--- leftover probes ---'
Get-CimInstance Win32_Process -Filter "Name='python.exe'" | ForEach-Object {
  $cl = [string]$_.CommandLine
  if ($cl -match 'p8[0-9]_') { W ("  py {0} {1}" -f $_.ProcessId, $cl) }
}

W '--- p88 log tail ---'
if (Test-Path 'temp\_p88_last.txt') {
  $p = (Get-Content 'temp\_p88_last.txt' -TotalCount 1).Trim()
  if (Test-Path -LiteralPath $p) { Get-Content -LiteralPath $p -Tail 12 | ForEach-Object { W ('  ' + $_) } }
}
W '--- p85 log tail ---'
if (Test-Path 'temp\_p85_refresh.txt') { Get-Content 'temp\_p85_refresh.txt' -Tail 12 | ForEach-Object { W ('  ' + $_) } }
W '--- p85 prog tail ---'
if (Test-Path 'temp\_p85_prog.txt') { Get-Content 'temp\_p85_prog.txt' -Tail 3 | ForEach-Object { W ('  ' + $_) } }
