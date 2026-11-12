# h320_va.ps1 -- elevate once and run the external entity reader (P1).
# Read-only: device open only, no driver load, no service touch.
# Usage: powershell -File _ritual\h320_va.ps1 [--secs=180] [--hz=1] [--out=_ritual\h320_vaN.txt]
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$rid = Get-Date -f 'yyyyMMdd_HHmmss'
$out = "_ritual\h320_va1.txt"
$userOut = @($args | Where-Object { $_ -like '--out=*' }).Count -gt 0
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator))
$pyExe = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $pyExe) { $pyExe = "python" }
[IO.File]::AppendAllText("$root\_ritual\h320_va_launch.trace",
    ((Get-Date -f 'HH:mm:ss') + " adm=$adm cwd=$PWD args=$($args -join ' ')`n"))
if (-not $adm) {
    $al = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"") + $args
    Start-Process powershell -Verb RunAs -ArgumentList $al
    exit 0
}
$alive = @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue).Count
[IO.File]::AppendAllText("$root\_ritual\h320_va_launch.trace",
    ((Get-Date -f 'HH:mm:ss') + " alive=$alive`n"))
if (-not $alive) { "NOGAME $rid" | Out-File $out; exit 4 }
$pyArgs = @($args)
if (-not $userOut) { $pyArgs += "--out=$out" }
[IO.File]::AppendAllText("$root\_ritual\h320_va_launch.trace",
    ((Get-Date -f 'HH:mm:ss') + " about to run py exe=$pyExe pyargs=$($pyArgs -join ' ')`n"))
& $pyExe ext\h320_va.py @pyArgs > C:\h320x\h320.std 2>> C:\h320x\h320.err
$rc = $LASTEXITCODE
[IO.File]::AppendAllText("$root\_ritual\h320_va_launch.trace",
    ((Get-Date -f 'HH:mm:ss') + " py rc=$rc`n"))
Add-Content -LiteralPath $out -Value ("rc=$rc end=" + (Get-Date -f 'HH:mm:ss'))
"rid=$rid out=$(if ($userOut) { 'caller --out' } else { $out }) rc=$rc"
exit $rc
