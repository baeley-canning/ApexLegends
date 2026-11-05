$r = 'c:\Users\New User\OneDrive\Desktop\cheating\_ritual\p270_wr3.txt'
Remove-Item -LiteralPath $r -EA 0
# Where does the provider db actually live? drv64.dll is what KDU documents, but a 0-hit ASCII
# scan for a name we KNOW is in the db means either the scan or the assumption is wrong.
foreach ($f in 'C:\p37vm\payload\drv64.dll', 'C:\p37vm\payload\kdu.exe') {
    $b = [IO.File]::ReadAllBytes($f)
    $s = [Text.Encoding]::ASCII.GetString($b)
    $hits = 0; $i = 0
    while (($i = $s.IndexOf('WinRing0x64', $i)) -ge 0) { $hits++; $i++ }
    $h2 = 0; $i = 0
    while (($i = $s.IndexOf('MmMapIoSpace', $i)) -ge 0) { $h2++; $i++ }
    $fi = Get-Item -LiteralPath $f
    ('{0} len={1} name_hits={2} mmio_hits={3} sha={4}' -f $fi.Name, $fi.Length, $hits, $h2, (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.Substring(0, 16)) | Add-Content -LiteralPath $r
}
'--- 30-byte readable chunks around each name_hit in drv64.dll ---' | Add-Content -LiteralPath $r
$b = [IO.File]::ReadAllBytes('C:\p37vm\payload\drv64.dll')
$s = [Text.Encoding]::ASCII.GetString($b)
$i = 0; $n = 0
while (($i = $s.IndexOf('WinRing0x64', $i)) -ge 0 -and $n -lt 6) {
    ($i.ToString() + ' | ' + ($s.Substring([Math]::Max(0, $i - 40), 90) -replace '[^\x20-\x7E]', '.')) | Add-Content -LiteralPath $r
    $i++; $n++
}
Add-Content -LiteralPath $r ('sample_csv_row: ' + (Get-Content 'C:\p37vm\payload\list.csv' | Select-String 'WinRing0x64' | Select-Object -First 1).Line)
'done' | Add-Content -LiteralPath $r
