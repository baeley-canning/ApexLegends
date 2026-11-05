# dmpcopy3.ps1 (p53d, crash #5 of 2026-11-04) - elevated: copy the 17:06:34 0x124 minidump
# out, checksum it, then dumpchk for bugcheck code/params/bucket. Read-only w.r.t. the
# source dump and C:\Windows. New number rather than overwriting dmpcopy2.ps1 (R5).
# Crash record: 41 @17:06:37, 1001 @17:06:44 0x124 (0, ffffc10d2759f028, bf800000, 200401),
# WHEA 18 @17:06:44 APIC 33 "Internal Unclassified Error". No reboot issued by us.
$src = 'C:\Windows\Minidump\110426-10531-01.dmp'
$dst = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\110426-10531-01.dmp'
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\p53d_dumpchk.txt'
$adm = [bool]([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm) {
    Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'))
    exit
}
$L = New-Object System.Collections.Generic.List[string]
$L.Add('now ' + (Get-Date).ToString('s'))
$L.Add('elevated=' + $adm)
$L.Add('--- minidump dir (elevated) ---')
try { foreach ($f in (Get-ChildItem 'C:\Windows\Minidump' -ErrorAction Stop)) { $L.Add("$($f.Name) $($f.Length) $($f.LastWriteTime.ToString('s'))") } }
catch { $L.Add('ERR list: ' + $_.Exception.Message) }
try {
    $f = Get-Item -LiteralPath $src -ErrorAction Stop
    $L.Add("src size=$($f.Length) mtime=$($f.LastWriteTime.ToString('s'))")
    Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop
    $L.Add('copied=' + (Test-Path -LiteralPath $dst) + ' size=' + (Get-Item -LiteralPath $dst).Length)
    $L.Add('sha256=' + (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash)
} catch { $L.Add('ERR copy: ' + $_.Exception.Message) }
$L.Add('--- WHEA 18 records since 17:06 (raw, first line each) ---')
try {
    foreach ($e in (Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=(Get-Date).AddMinutes(-30)} -ErrorAction Stop)) {
        $L.Add($e.TimeCreated.ToString('s') + ' id=' + $e.Id + ' :: ' + (($e.Message -split "`r`n") -join ' '))
    }
} catch { $L.Add('ERR whea: ' + $_.Exception.Message) }

# dumpchk: local symbol cache only, no srv* => no network stall
$dumpchk = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\dumpchk.exe'
if ((Test-Path -LiteralPath $dumpchk) -and (Test-Path -LiteralPath $dst)) {
    $env:_NT_SYMBOL_PATH = 'C:\Symbols'
    $so = Join-Path $env:TEMP 'p53d_dumpchk.out.txt'
    Remove-Item -LiteralPath $so -ErrorAction 0
    $L.Add('--- dumpchk (120 s cap) ---')
    try {
        $p = Start-Process -FilePath $dumpchk -ArgumentList ('-v "' + $dst + '"') -RedirectStandardOutput $so -RedirectStandardError ($so + '.err') -PassThru -ErrorAction Stop
        if (-not $p.WaitForExit(120000)) { $L.Add('TIMEOUT - killing'); try { $p.Kill() } catch {} } else { $L.Add('exit=' + $p.ExitCode) }
        if (Test-Path -LiteralPath $so) { $L.Add((Get-Content -LiteralPath $so -Raw)) }
        if (Test-Path -LiteralPath ($so + '.err')) { $L.Add('--- stderr ---'); $L.Add((Get-Content -LiteralPath ($so + '.err') -Raw)) }
    } catch { $L.Add('ERR dumpchk: ' + $_.Exception.Message) }
} else { $L.Add('dumpchk missing or copy failed: ' + $dumpchk) }
Set-Content -LiteralPath $log -Value $L -Encoding UTF8
$L.Add('--- end ---')
Set-Content -LiteralPath $log -Value $L -Encoding UTF8
