# h310 dis - disassemble a range of the faulting driver out of the triage dump.
# No elevation: the copy lives under C:\Users\Public\p37. Read-only.
# R5: every run gets its own tag/output, and the capture goes through kd's own -logo file
# because piping stdout truncates whenever `q` races the flush.
param([Parameter(Mandatory = $true)][string]$Tag, [string]$Cmds = 'u zapexdrv+0x3880 L45')
$kd  = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
$dmp = 'C:\Users\Public\p37\h310_mini.dmp'
$log = 'C:\Users\Public\p37\h310_dis_' + $Tag + '.log'
$out = 'C:\Users\Public\p37\h310_dis_' + $Tag + '.txt'
$f = New-Object System.Diagnostics.ProcessStartInfo
$f.FileName = $kd
$f.Arguments = '-y C:\symbols -logo "' + $log + '" -z "' + $dmp + '" -c ".symopt- 100; ' + $Cmds + '; q"'
$f.RedirectStandardOutput = $true; $f.RedirectStandardError = $true; $f.UseShellExecute = $false
$p = [System.Diagnostics.Process]::Start($f)
$so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()
if (-not $p.WaitForExit(180000)) { try { $p.Kill() } catch { } }
Start-Sleep -Milliseconds 800
$txt = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log } else { @() }
$start = 0
for ($i = 0; $i -lt $txt.Count; $i++) { if ($txt[$i] -match '^\d+:\s*kd>') { $start = $i; break } }
Set-Content -LiteralPath $out -Value $txt[$start..($txt.Count - 1)] -Encoding UTF8
'rc=' + $p.ExitCode + ' lines=' + $txt.Count + ' from=' + $start
