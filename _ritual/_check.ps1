# _check.ps1 - syntax-parse the ritual scripts and dump the p24 evidence tail.
$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot
foreach($f in 'p24.ps1','p25.ps1'){
  if(Test-Path $f){
    $e = $null; $t = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f).Path,[ref]$t,[ref]$e)
    if($e -and $e.Count){
      "PARSE $f = {0} error(s)" -f $e.Count
      $e | ForEach-Object { "  {0} L{1} :: {2}" -f $_.ErrorId,$_.Extent.StartLineNumber,$_.Message }
    } else { "PARSE $f = OK ($((Get-Content $f).Count) lines)" }
  } else { "$f missing" }
}
''
'--- p24.txt tail (last 25 lines) ---'
if(Test-Path p24.txt){ Get-Content p24.txt -Tail 25 } else { 'p24.txt missing' }
''
'--- kernprobe registry state ---'
if(Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\kernprobe'){
  Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\kernprobe' | Select-Object ImagePath,Start,Type,ErrorControl | Format-List | Out-String
} else { 'kernprobe: NOT in registry' }
''
'--- apexdrv* copies on disk ---'
Get-ChildItem 'C:\Windows\System32\drivers\apexdrv*' -Force -ErrorAction SilentlyContinue | ForEach-Object { "  {0}  {1}  {2}" -f $_.Name,$_.Length,$_.LastWriteTime }
Get-ChildItem 'C:\ProgramData\QwenKern\apexdrv*' -Force -ErrorAction SilentlyContinue | ForEach-Object { "  {0}  {1}  {2}" -f $_.FullName,$_.Length,$_.LastWriteTime }
''
'--- gdrv3 (fallback transport) ---'
((& sc.exe query gdrv3 2>&1) -join ' ') -replace '\s+',' '
''
'--- testsigning ---'
((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions -ErrorAction SilentlyContinue).SystemStartOptions)
