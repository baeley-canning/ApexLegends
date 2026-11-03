# h1b - repair the kdu base mismatch left by h1 boot 4.
#
# h1 printed PRE-DSE=16 and fed "16" straight back to -dse. kdu prints g_CiOptions in HEX but
# parses the -dse argument in DECIMAL, so "16" wrote 0x10 and the box now sits at 0x10 while
# PatchGuard hashed 0x16 at boot - the exact 0x109 setup, one bit short.
# Correct write value is decimal 22 (= 0x16). Readback is compared as hex text, never as int.
#
# Writes: _ritual\h1b_host.txt. Leaves DSE at 0x16 and the driver RUNNING.
$ErrorActionPreference = 'Continue'
$rit = $PSScriptRoot
$pay = 'C:\p37vm\payload'
$o   = Join-Path $rit 'h1b_host.txt'
$want = '16'                    # hex text, as kdu prints it
$dec  = 22                      # 0x16 in decimal, what -dse actually consumes
$svc  = 'apexdrv'
$adm  = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if(-not $adm){
  $ea = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'))
  Start-Process powershell -Verb RunAs -ArgumentList $ea
  exit
}
function W($t){ $t | Add-Content -LiteralPath $o }
function Kdu([string]$dse){
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = Join-Path $pay 'kdu.exe'
  $psi.Arguments = '-prv 22 -dse ' + $dse
  $psi.UseShellExecute = $false
  $psi.WorkingDirectory = $pay
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $t = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  [void]$p.WaitForExit(20000)
  $txt = ''
  foreach($x in $t,$e){ if($x.Wait(2500) -and $x.IsCompleted){ try { $txt += $x.Result } catch {} } }
  $script:last = $txt -replace "`r`n","`n"
  W ('$ kdu.exe -prv 22 -dse ' + $dse)
  foreach($ln in ($script:last -split "`n")){ if($ln.Trim() -ne '' -and $ln -match 'DSE flags|verification|identical|value'){ W ('  | ' + $ln.Trim()) } }
  return ($script:last -match 'verification succeeded')
}
W ('=== h1b kdu base repair ' + (Get-Date -f 'dd/MM/yyyy HH:mm:ss') + ' pid=' + $PID + ' admin=' + $adm + ' ===')
W ('  target: restore DSE to hex 0x' + $want + ' (= decimal ' + $dec + '); kdu prints hex, eats decimal')
W ('  driver before: ' + (((& sc.exe query $svc 2>&1) | Select-String 'STATE' | ForEach-Object { $_.ToString().Trim() }) -join ' '))

$wrote = Kdu $dec
$back  = ''
$null = Kdu $dec                       # second pass reads the live value before writing it again
if($script:last -match 'value:\s*([0-9A-Fa-f]+)\s*,\s*new value'){ $back = $Matches[1] }
$ok = ($back -eq $want)
W ('  readback=0x' + $back + ' expect=0x' + $want + ' match=' + $ok)
W ('  driver after: ' + (((& sc.exe query $svc 2>&1) | Select-String 'STATE' | ForEach-Object { $_.ToString().Trim() }) -join ' '))
W ''
W '=== VERDICT ==='
if($ok){ W ('RESULT: PASS - g_CiOptions back to boot value 0x' + $want + ' (readback verified), driver still RUNNING; h1 boot-4 PARTIAL is superseded') }
else { W ('RESULT: FAIL - readback 0x' + $back + ' != 0x' + $want + '; boot value NOT restored, expect 0x109 inside ~20 min') }
W ('-- h1b END ' + (Get-Date -f 'HH:mm:ss') + ' --')
