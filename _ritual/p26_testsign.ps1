# p26_testsign.ps1 - the measured fix: DSE returns 577 because the self-made chain is not
# kernel-accepted (SecureBoot=False, testsigning=No, CI event 3004 "hash could not be found").
# self-elevates, enables testsigning, records state + tool availability.
$out = Join-Path $PSScriptRoot 'p26_testsign.txt'
function L([string]$s) { $s | Out-File -FilePath $out -Append -Encoding utf8; Write-Host $s }
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
L ("=== p26_testsign " + (Get-Date) + "  elevated=" + $adm)
if (-not $adm) {
    L "self-elevating via UAC"
    Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'))
    L "elevated child launched; run  shutdown /r /t 0  afterwards"
    exit 0
}
L ((bcdedit /set testsigning on 2>&1) -join "`n")
$bcd = (bcdedit /enum '{current}' 2>&1 | Out-String)
foreach ($k in 'testsigning', 'nointegritychecks', 'hypervisorlaunchtype') {
    $m = [regex]::Match($bcd, "(?im)^\s*$k\s+(\S+)")
    L ("bcd." + $k + "=" + $(if ($m.Success) { $m.Groups[1].Value } else { '(not set)' }))
}
foreach ($t in 'makecat.exe', 'inf2cat.exe', 'signtool.exe', 'certutil.exe') {
    $c = Get-Command $t -ErrorAction SilentlyContinue
    L ("tool " + $t + " = " + $(if ($c) { $c.Source } else { 'NOT IN PATH' }))
}
L "NEXT: shutdown /r /t 0  -> then run _ritual\p26_drv.ps1 (expect RUNNING + IOCTL_PROBE SUCCESS)"
L "=== done ==="
