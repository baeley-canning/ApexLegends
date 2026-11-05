# space_scan.ps1 - host-only disk audit, no VM interaction. The C: volume hit 0 bytes earlier, which
# paused the VM with VERR_DISK_FULL; ~1.2 GB of PNG/TEMP cleanup is only a stopgap. Writes the biggest
# consumers under C:\ and the largest root files so something can be deleted deliberately.
$o = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\space.txt'
'freeMB=' + [math]::Round((Get-PSDrive C).Free / 1MB, 1) | Set-Content $o -Encoding ascii
Get-ChildItem 'C:\' -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $n = (Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($null -eq $n) { $n = 0 }
    if ($n -gt 1GB) { Add-Content $o ('{0,9:N2} GB  {1}' -f ($n / 1GB), $_.FullName) } else { Add-Content $o ((([string][math]::Round($n / 1MB)) + ' MB  ') + $_.FullName) }
}
Get-ChildItem 'C:\' -File -Force -ErrorAction SilentlyContinue | Sort-Object Length -Descending | Select-Object -First 6 | ForEach-Object {
    Add-Content $o ('FILE {0,9:N2} GB  {1}' -f ($_.Length / 1GB), $_.FullName)
}
'DONE' | Add-Content $o