# dmpcopy.ps1 - elevated: copy the 0x124 minidump out and checksum it (read-only w.r.t. the dump)
$src = 'C:\Windows\Minidump\110426-10656-01.dmp'
$dst = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\110426-10656-01.dmp'
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\dmpcopy.txt'
$L = New-Object System.Collections.Generic.List[string]
$L.Add('now ' + (Get-Date).ToString('s'))
$L.Add('elevated=' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
try {
    $f = Get-Item $src -ErrorAction Stop
    $L.Add("src size=$($f.Length) mtime=$($f.LastWriteTime)")
    Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop
    $L.Add('copied=' + (Test-Path $dst) + ' size=' + (Get-Item $dst).Length)
    $L.Add('sha256=' + (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash)
} catch { $L.Add('ERR: ' + $_.Exception.Message) }
Set-Content -LiteralPath $log -Value $L -Encoding UTF8
