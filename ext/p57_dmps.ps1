# p57_dmps.ps1 -- read-only: newest minidumps + newest BugCheck 1001 text.
# For the 18:00:02 stop. Run elevated via RunAs; verdict lands in temp\p57_dmp.txt.
$out = Join-Path (Split-Path -Parent $PSScriptRoot) 'temp\p57_dmp.txt'
Start-Transcript -Path $out -Force | Out-Null
"# p57_dmps " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Get-ChildItem C:\Windows\Minidump -Filter *.dmp |
    Sort-Object LastWriteTime -Descending | Select-Object -First 3 Name, Length, LastWriteTime |
    Format-Table -AutoSize
Get-WinEvent -FilterHashtable @{LogName = 'System'; Id = 1001; StartTime = (Get-Date).AddHours(-2) } `
    -MaxEvents 2 -ErrorAction SilentlyContinue | ForEach-Object {
        "---- " + $_.TimeCreated
        $_.Message
    }
Stop-Transcript | Out-Null
