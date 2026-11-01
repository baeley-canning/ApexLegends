# p31c: run p28 ELEVATED with full error capture - p28's own output file never appeared
# even though the -Verb RunAs hop provably works (see _elevprobe.ps1). This says why.
$err = Join-Path $PSScriptRoot '_p28_err.txt'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
"=== _p28run $(Get-Date -f 'HH:mm:ss') admin=$adm ps=$($PSVersionTable.PSVersion) ===" | Set-Content -LiteralPath $err
try {
  & (Join-Path $PSScriptRoot 'p28_esp.ps1') -Method nt *>> $err
} catch {
  "HOST EXCEPTION: $($_.Exception.GetType().FullName): $($_.Exception.Message)" | Add-Content -LiteralPath $err
}
"exit=$LASTEXITCODE p28_esp.txt=$(Test-Path (Join-Path $PSScriptRoot 'p28_esp.txt')) game=$(Test-Path (Join-Path $PSScriptRoot 'p28_esp.txt'))" | Add-Content -LiteralPath $err
"-- _p28run END $(Get-Date -f 'HH:mm:ss') --" | Add-Content -LiteralPath $err
