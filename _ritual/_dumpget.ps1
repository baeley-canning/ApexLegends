$o = Join-Path $PSScriptRoot '_dmpget.txt'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
("dumpget {0} admin={1} elevatedChild" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'), $adm) | Set-Content -LiteralPath $o -Encoding UTF8
'--- C:\Windows\Minidump ---' | Add-Content -LiteralPath $o -Encoding UTF8
Get-ChildItem 'C:\Windows\Minidump' -Force -ErrorAction SilentlyContinue | ForEach-Object { ('   {0}   {1} bytes   {2}' -f $_.Name, $_.Length, $_.LastWriteTime) | Add-Content -LiteralPath $o -Encoding UTF8 }
$dst = Join-Path $PSScriptRoot '_dumps'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item 'C:\Windows\Minidump\*.dmp' $dst -Force -ErrorAction SilentlyContinue
'--- copied ---' | Add-Content -LiteralPath $o -Encoding UTF8
Get-ChildItem $dst | ForEach-Object { ('   {0}   {1} bytes' -f $_.Name, $_.Length) | Add-Content -LiteralPath $o -Encoding UTF8 }
'done' | Add-Content -LiteralPath $o -Encoding UTF8
