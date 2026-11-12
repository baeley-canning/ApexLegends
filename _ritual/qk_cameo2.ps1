# qk_cameo2.ps1 - apexdrv exists for ~2 seconds: create service, start, read DTB+base,
# stop, delete service, restore DSE.  The game must stay alive for the DTB to be useful,
# so the driver is never resident while anything else happens.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$out = Join-Path $here 'qk_cameo2.out'
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm) {
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $MyInvocation.MyCommand.Path + '"')) -Verb RunAs
    exit 0
}
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $out -Value ($L -join "`r`n") }
$kdu = 'C:\Users\Public\p37\kdu.exe'
function Kdu([string[]]$a) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $kdu; $psi.Arguments = ($a -join ' '); $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = 'C:\Users\Public\p37'
    try {
        $p = [System.Diagnostics.Process]::Start($psi)
        $t1 = $p.StandardOutput.ReadToEndAsync(); $t2 = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(25000)) { try { $p.Kill() } catch { } }
        return ($t1.Result + $t2.Result)
    } catch { return $_.Exception.Message }
}
Lg '===== cameo2 ====='
$game = Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $game) { Lg 'RESULT: FAIL no game'; Emit; exit 1 }
Lg ('game pid=' + $game.Id)

$bld = Join-Path $root 'QwenKernPremium\build\apexdrv.sys'
$sys = Join-Path $env:WINDIR 'System32\drivers\apexdrv.sys'
Copy-Item -LiteralPath $bld -Destination $sys -Force -ErrorAction Continue
if (-not (Test-Path -LiteralPath $sys)) { Lg 'RESULT: FAIL stage'; Emit; exit 1 }

$w = Kdu @('-prv', '20', '-dse', '0')
$pre = ''
if ($w -match 'value:\s*([0-9A-Fa-f]+)') { $pre = $matches[1] }
Lg ('DSE pre=0x' + $(if ($pre) { $pre } else { '?' }) + ' (written 0 by the read)')

& sc.exe create ApexDrv type= kernel start= demand 'binPath=' "C:\WINDOWS\System32\drivers\apexdrv.sys" 2>&1 | ForEach-Object { Lg ('  create| ' + $_) }
$s = & sc.exe start ApexDrv 2>&1 | Out-String
Lg ('start: ' + (($s -replace '\s+', ' ').Trim()))

$py = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'
$scp = Join-Path $root 'ext\qk_va.py'
$qout = Join-Path $here 'qk_va_cameo2.txt'
& $py $scp ('--pid=' + $game.Id) '--pe' '--no-driver' ('--out=' + $qout) '--no-elevate' | ForEach-Object { Lg ('  | ' + $_) }

& sc.exe stop ApexDrv 2>&1 | ForEach-Object { Lg ('  stop| ' + $_) }
& sc.exe delete ApexDrv 2>&1 | ForEach-Object { Lg ('  del| ' + $_) }
Lg ('driver now: ' + ((& sc.exe query ApexDrv 2>&1 | Out-String) -replace '\s+', ' ').Trim())

if ($pre -and $pre -notmatch '^0+$') {
    $dec = [Convert]::ToInt32($pre, 16)
    $w2 = Kdu @('-prv', '20', '-dse', "$dec")
    Lg ('DSE restore 0x' + $pre + ' (dec ' + $dec + ') verified=' + ($w2 -match 'verification succeeded'))
}
Lg ('game alive=' + [bool](Get-Process -Id $game.Id -ErrorAction SilentlyContinue))
Emit
