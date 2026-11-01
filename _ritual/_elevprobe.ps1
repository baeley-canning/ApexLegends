# Minimal elevation probe: proves whether Start-Process -Verb RunAs actually
# produces an elevated child on this host (p28's own hop was silently not happening).
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
"elev probe RAN: admin=$adm when=$(Get-Date -f 'HH:mm:ss') script=$PSCommandPath" |
  Set-Content -LiteralPath (Join-Path $PSScriptRoot '_elevprobe.txt')
