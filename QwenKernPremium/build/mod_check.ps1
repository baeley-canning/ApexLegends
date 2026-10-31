# Elevated cross-check: is r5apex_dx12.exe's module list readable at all, or is
# our TH32CS_SNAPMODULE instrument the thing that fails?
$out = 'C:\apex_mod.txt'
$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
'elevated=' + $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) |
    Set-Content -Encoding ascii $out

try {
    'ps_modules=' + (Get-Process -Id 1512).Modules.Count |
        Add-Content -Encoding ascii $out
} catch {
    'ps_modules=ERR ' + $_.Exception.Message | Add-Content -Encoding ascii $out
}

$snap = Get-Process -Id 1512
'ps_threads=' + $snap.Threads.Count | Add-Content -Encoding ascii $out
'ps_path=' + $snap.Path | Add-Content -Encoding ascii $out

'--- tasklist /m ---' | Add-Content -Encoding ascii $out
(tasklist /m /fi "PID eq 1512") | Add-Content -Encoding ascii $out
