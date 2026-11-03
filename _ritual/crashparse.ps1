$o = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\crashparse.txt'
function S($t) { $t | Out-File -FilePath $o -Encoding ascii -Append }
if (Test-Path $o) { Remove-Item $o -Force }
$KD = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'

S ("now = " + (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
S '--- minidump access ---'
foreach ($d in @('C:\Windows\Minidump\110126-9437-01.dmp', 'C:\Windows\Minidump\102726-9484-01.dmp')) {
    try {
        $f = Get-Item -LiteralPath $d -Force -EA Stop
        $fsok = 'readable'
        try { $fs = [IO.File]::Open($d, 'Open', 'Read', 'ReadWrite'); $fs.Close() } catch { $fsok = 'LOCKED:' + $_.Exception.Message }
        S ("  " + $f.Name + "  " + $f.Length + " bytes  " + $f.LastWriteTime + "  " + $fsok)
    } catch { S ("  " + $d + "  ERR " + $_.Exception.Message) }
}
S ("  dir listing: " + ((Get-ChildItem 'C:\Windows\Minidump' -Force -EA 0 | ForEach-Object { $_.Name }) -join ', '))
S ''

S '--- WER: powershell.exe user-mode crashes (today) ---'
$arch = 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive'
Get-ChildItem $arch -Directory -EA 0 | Where-Object { $_.Name -like 'AppCrash_powershell*' } | ForEach-Object {
    $w = Join-Path $_.FullName 'Report.wer'
    if (Test-Path $w) {
        S ("== " + $_.Name + "  dirTime=" + $_.LastWriteTime)
        S (((Select-String -Path $w -Pattern '^(EventTime|Sig\[0\]|Sig\[3\]|Sig\[4\]|Sig\[5\]|Sig\[6\]|Sig\[7\]|DynamicSig\[1\])' -EA 0) | ForEach-Object { $_.Line }) -join "`r`n")
        S ''
    }
}

S '--- kd !analyze -v on today 110126-9437-01.dmp ---'
try {
    $sym = 'C:\symbols'
    $args = @('-y', "srv*$sym*https://msdl.microsoft.com/download/symbols", '-z', 'C:\Windows\Minidump\110126-9437-01.dmp',
              '-c', '!analyze -v; lm; q')
    S ((& $KD @args 2>&1) -join "`r`n")
} catch { S ("kd ERR: " + $_.Exception.Message) }
S ''
S '--- end ---'
