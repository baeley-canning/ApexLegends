# h318_decontam.ps1 - put ci!g_CiOptions back on the boot byte 0x16 before anything else.
# Why: our h316/h317 fiddling left DSE at 0 (and my 22:10 park wrote 6 = DSE on but NOT the byte
# PatchGuard hashed at boot - h1_dse_host.ps1's own header records the resulting 0x109). Both are
# wrong for Javelin: 0 trips "signing integrity checks must be enabled", 6 sets up a 0x109.
# kdu prints HEX and -dse eats DECIMAL, so the argument is 22 and the gate is the printed text "16".
# R3: read, write, read-back; nothing continues without the read-back. R5: own file. Self-elevating.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h318_decontam.out'
$d    = 'C:\Users\Public\p37'
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm) { Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $MyInvocation.MyCommand.Path + '"')) -Verb RunAs; exit 0 }
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $out -Value ($L -join "`r`n") }
function Kdu([string[]]$a, [int]$cap = 25000) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $d 'kdu.exe'; $psi.Arguments = ($a -join ' '); $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.WorkingDirectory = $d
    try { $p = [System.Diagnostics.Process]::Start($psi)
          $t1 = $p.StandardOutput.ReadToEndAsync(); $t2 = $p.StandardError.ReadToEndAsync()
          if (-not $p.WaitForExit($cap)) { try { $p.Kill() } catch { } }
          Start-Sleep -Milliseconds 150
          return (($t1.Result + $t2.Result) -replace '\s+', ' ').Trim() } catch { return ('FAIL ' + $_.Exception.Message) }
}
Lg '===== h318 dse decontam (target boot byte 0x16) ====='
$game = @(Get-Process r5apex_dx12 -EA 0).Count
Lg ('game=' + $game + $(if ($game) { ' (flip with the game up is the h1 pre-flight violation)' } else { '' }))
$o = Kdu @('-prv', '20', '-dse')
Lg ('pre out=[' + $o + ']')
$pre = if ($o -match 'value:\s*([0-9A-Fa-f]+)') { $matches[1] } else { '' }
Lg ('dse_pre=0x' + $(if ($pre) { $pre } else { 'UNREADABLE' }))
if (-not $pre) { Lg 'RESULT: FAIL - DSE unreadable via prv 20'; Emit; exit 1 }
if ($pre -match '^0*16$') { Lg 'dse already 0x16 (boot byte) - nothing to do'; Lg 'RESULT: PASS - dse=0x16 (already clean)'; Emit; exit 0 }
$w = Kdu @('-prv', '20', '-dse', '22')
Lg ('write out=[' + $w + ']')
if ($w -notmatch 'verification succeeded') { Lg 'RESULT: FAIL - provider did not report a verified write'; Emit; exit 1 }
Start-Sleep -Milliseconds 500
$chk = Kdu @('-prv', '20', '-dse')
$post = if ($chk -match 'value:\s*([0-9A-Fa-f]+)') { $matches[1] } else { '' }
Lg ('post out=[' + $chk + ']')
Lg ('dse_post=0x' + $(if ($post) { $post } else { 'UNREADABLE' }))
if ($post -match '^0*16$') { Lg ('RESULT: PASS - dse 0x' + $pre + ' -> 0x16 (boot byte restored)'); Emit; exit 0 }
Lg ('RESULT: FAIL - dse 0x' + $pre + ' -> 0x' + $(if ($post) { $post } else { 'UNREADABLE' })); Emit
exit 1
