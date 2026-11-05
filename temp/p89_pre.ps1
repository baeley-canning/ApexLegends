$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
Set-Location -LiteralPath $repo
$o = 'C:\Users\New User\AppData\Local\Temp\_p89_pre.txt'
Remove-Item -LiteralPath $o -ErrorAction SilentlyContinue

$t = Get-ScheduledTask -TaskName 'cheat_p64_arm' -ErrorAction SilentlyContinue
if ($t) {
  $info = $t | Get-ScheduledTaskInfo
  "task_state=$($t.State) last_result=$($info.LastTaskResult) last_run=$($info.LastRunTime)" | Out-File -LiteralPath $o -Encoding utf8
} else {
  'task_state=MISSING' | Out-File -LiteralPath $o -Encoding utf8
}

$ln = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'arm_queue|cmd\.txt' })
"listener_count=$($ln.Count)" | Out-File -LiteralPath $o -Append -Encoding utf8
foreach ($p in $ln) { "  listener pid=$($p.ProcessId)" | Out-File -LiteralPath $o -Append -Encoding utf8 }

"python_count=$(@(Get-Process python -ErrorAction SilentlyContinue).Count)" | Out-File -LiteralPath $o -Append -Encoding utf8
"cmd_exists=$(Test-Path -LiteralPath 'temp\cmd.txt') cmd_lines=$(@(Get-Content -LiteralPath 'temp\cmd.txt' -ErrorAction SilentlyContinue).Count)" | Out-File -LiteralPath $o -Append -Encoding utf8
"prog_lines=$(@(Get-Content -LiteralPath 'temp\_p85_prog.txt' -ErrorAction SilentlyContinue).Count) prog_mtime=$((Get-Item 'temp\_p85_prog.txt' -ErrorAction SilentlyContinue).LastWriteTime)" | Out-File -LiteralPath $o -Append -Encoding utf8
"targets_exists=$(Test-Path -LiteralPath 'temp\_p85_targets.txt')" | Out-File -LiteralPath $o -Append -Encoding utf8
$drv = & sc.exe query gdrv3 2>&1
"drv=$((($drv -join ' ') -replace '\s+', ' ').Trim())" | Out-File -LiteralPath $o -Append -Encoding utf8
