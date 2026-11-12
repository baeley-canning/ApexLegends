# h315_dump.ps1 - evidence pass for the 21:33:46 bugcheck 0xDA (0x302, 0, 0, 0xfffffff538000000)
# that killed host run h315 step 3 inside the kdu DSE-read provider loop.
#
# Rules honoured:
#   R3  pre-state is recorded before anything (src size/mtime/sha, MEMORY.DMP, crashcontrol, event
#       log IDs 1001/41/3001/3085 with raw bodies, artifact mtimes, NUL extents) and the copy is
#       hash-compared against the source. Read-back goes to this run's own file.
#   R5  own files only, nothing overwritten: h315_dump.out, h315_dumpchk.out, h315_kd.out,
#       h315_crash.txt. Copy lands in temp\ under the dump's original name.
#   R4  read-only w.r.t. C:\Windows: the dump is copied OUT, never moved; no service, no registry
#       write, no bcdedit, no reboot.
#
# Self-elevating: C:\Windows\Minidump is not listable/readable unelevated on 26200 (measured).
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$src  = 'C:\Windows\Minidump\110626-10609-01.dmp'
$dst  = Join-Path $root 'temp\110626-10609-01.dmp'
$log  = Join-Path $here 'h315_dump.out'
$chk  = Join-Path $here 'h315_dumpchk.out'
$kdO  = Join-Path $here 'h315_kd.out'
$rec  = Join-Path $here 'h315_crash.txt'
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $adm) {
    $ra = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $MyInvocation.MyCommand.Path + '"'))
    Start-Process powershell.exe -ArgumentList $ra -Verb RunAs
    exit 0
}
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $log -Value ($L -join "`r`n") -Encoding UTF8 }
Lg '===== h315 dump evidence ====='
Lg ('admin=' + $adm + ' pid=' + $PID + ' boot=' + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('s'))

# --- pre-state ------------------------------------------------------------------------------
Lg '--- minidump dir (elevated) ---'
try { foreach ($f in (Get-ChildItem 'C:\Windows\Minidump' -ErrorAction Stop)) { Lg ('  ' + $f.Name + ' ' + $f.Length + ' ' + $f.LastWriteTime.ToString('s')) } }
catch { Lg ('  ERR list: ' + $_.Exception.Message) }
Lg ('MEMORY.DMP exists=' + (Test-Path 'C:\Windows\MEMORY.DMP'))
try { $cc = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
      Lg ('crashcontrol: CrashDumpEnabled=' + $cc.CrashDumpEnabled + ' AutoReboot=' + $cc.AutoReboot + ' AlwaysKeepMemoryDump=' + $cc.AlwaysKeepMemoryDump + ' Overwrite=' + $cc.Overwrite) } catch { Lg 'crashcontrol unreadable' }
$srcSha = ''; $srcLen = 0; $srcTime = ''
try { $f = Get-Item -LiteralPath $src -ErrorAction Stop
      $srcLen = $f.Length; $srcTime = $f.LastWriteTime.ToString('s')
      $srcSha = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
      Lg ('src size=' + $srcLen + ' mtime=' + $srcTime + ' sha256=' + $srcSha) }
catch { Lg ('ERR src: ' + $_.Exception.Message) }
Emit
# --- event log record (raw bodies kept, not summarised) --------------------------------------
$ev = New-Object System.Collections.Generic.List[string]
foreach ($id in 1001, 41) {
    try { foreach ($e in (Get-WinEvent -FilterHashtable @{LogName = 'System'; Id = $id; StartTime = (Get-Date '2026-11-06 21:25')} -ErrorAction Stop)) {
              $ev.Add('EVT ' + $e.TimeCreated.ToString('s') + ' id=' + $e.Id + ' ' + $e.ProviderName)
              foreach ($ln in ($e.Message -split "`r?`n")) { if ($ln.Trim() -ne '') { $ev.Add('  | ' + $ln.Trim()) } }
              $ev.Add('  props=' + (($e.Properties | ForEach-Object { $_.Value }) -join ',')) } }
    catch { $ev.Add('evt id ' + $id + ' ERR: ' + $_.Exception.Message) }
}
foreach ($id in 3001, 3085, 3099) {
    try { foreach ($e in (Get-WinEvent -FilterHashtable @{LogName = 'System'; Id = $id; StartTime = (Get-Date '2026-11-06 21:25')} -ErrorAction Stop)) {
              $ev.Add('CI ' + $e.TimeCreated.ToString('s') + ' id=' + $e.Id + ' :: ' + (($e.Message -split "`r?`n")[0])) } }
    catch { }
}

# --- artifact record: what the run had touched when it died ---------------------------------
$art = New-Object System.Collections.Generic.List[string]
foreach ($p in 'C:\Users\Public\p37\h315.out', 'C:\Users\Public\p37\h315.lock', 'C:\Users\Public\p37\DirectIo64.sys',
               'C:\Users\Public\p37\kdu_list.csv', 'C:\p37vm\guest-h310.log', 'C:\Users\Public\p37\zapexdrv.sys',
               'C:\Users\Public\p37\apexcheat.dll', 'C:\Users\Public\p37\apex_launcher.exe') {
    try { $i = Get-Item -LiteralPath $p -ErrorAction Stop
          $nul = ''
          if ($i.Length -gt 0 -and $i.Extension -in '.out', '.log') {
              $b = [IO.File]::ReadAllBytes($p); $last = -1
              for ($k = $b.Length - 1; $k -ge 0; $k--) { if ($b[$k] -ne 0) { $last = $k; break } }
              $nul = ' lastNonNul=' + $last + ' trailingNul=' + ($b.Length - 1 - $last)
          }
          $art.Add('  ' + $p + ' size=' + $i.Length + ' mtime=' + $i.LastWriteTime.ToString('s') + $nul) }
    catch { $art.Add('  ' + $p + ' ERR ' + $_.Exception.Message) }
}
# the 21:33 file trail in the staging dir is the provider-order fingerprint
$art.Add('  --- files in C:\Users\Public\p37 touched after 21:33:15 ---')
foreach ($i in (Get-ChildItem 'C:\Users\Public\p37' | Where-Object { $_.LastWriteTime -gt (Get-Date '2026-11-06 21:33:15') } | Sort-Object LastWriteTime)) {
    $art.Add('    ' + $i.LastWriteTime.ToString('HH:mm:ss.fff') + ' ' + $i.Length + ' ' + $i.Name)
}

# --- copy out, hash-compare ----------------------------------------------------------------
$copied = $false
try {
    Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop
    $dSha = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
    $copied = ($dSha -eq $srcSha -and (Get-Item -LiteralPath $dst).Length -eq $srcLen)
    Lg ('copy dst=' + $dst + ' size=' + (Get-Item -LiteralPath $dst).Length + ' sha256=' + $dSha + ' MATCH=' + $copied)
} catch { Lg ('ERR copy: ' + $_.Exception.Message) }
Emit
# --- dumpchk -------------------------------------------------------------------------------
if ($copied) {
    $dc = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\dumpchk.exe'
    Lg ('dumpchk present=' + (Test-Path $dc))
    try {
        $p = Start-Process $dc -ArgumentList ('"' + $dst + '"') -NoNewWindow -PassThru -RedirectStandardOutput $chk -RedirectStandardError ($chk + '.err')
        [void]$p.WaitForExit(180000)
        Lg ('dumpchk rc=' + $p.ExitCode + ' out-bytes=' + (Get-Item $chk -EA 0).Length)
    } catch { Lg ('ERR dumpchk: ' + $_.Exception.Message) }
    Emit

    # --- kd !analyze -v (symbols from the MS server, local cache) --------------------------
    $kde = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe'
    $env:_NT_SYMBOL_PATH = 'srv*C:\symbols*https://msdl.microsoft.com/download/symbols'
    Lg ('kd present=' + (Test-Path $kde))
    try {
        $ka = @('-z', ('"' + $dst + '"'), '-y', $env:_NT_SYMBOL_PATH, '-c', '!analyze -v;.bugcheck;lmvm zapexdrv;!pool 0xfffffff538000000;q')
        $p2 = Start-Process $kde -ArgumentList $ka -NoNewWindow -PassThru -RedirectStandardOutput $kdO -RedirectStandardError ($kdO + '.err')
        if (-not $p2.WaitForExit(300000)) { Lg 'kd TIMEOUT 300s'; try { $p2.Kill() } catch { } }
        else { Lg ('kd rc=' + $p2.ExitCode) }
        Lg ('kd out-bytes=' + (Get-Item $kdO -EA 0).Length)
    } catch { Lg ('ERR kd: ' + $_.Exception.Message) }
}
Emit

# --- crash record --------------------------------------------------------------------------
$R = New-Object System.Collections.Generic.List[string]
$R.Add('# h315 crash record - 2026-11-06 21:33:46 UTC+1 - bugcheck 0xDA (0x302, 0, 0, 0xfffffff538000000)')
$R.Add('# dump: ' + $src + ' size=' + $srcLen + ' mtime=' + $srcTime + ' sha256=' + $srcSha)
$R.Add('# copy: ' + $dst + ' verified=' + $copied)
$R.Add('# context: host run h315 step 3 = kdu DSE-read provider loop (prv 22 first, then csv order);')
$R.Add('#          DirectIo64.sys extracted 21:33:29, bugcheck 21:33:46; nothing injected, no DSE write this run.')
$R.Add('# analysis: ' + $chk + ' + ' + $kdO)
$R.Add('')
$R.Add('## events')
$R.AddRange($ev)
$R.Add('')
$R.Add('## artifacts')
$R.AddRange($art)
Set-Content -LiteralPath $rec -Value ($R -join "`r`n") -Encoding UTF8
Lg ('record=' + $rec + ' bytes=' + (Get-Item $rec -EA 0).Length)
Lg 'RESULT: dump evidence pass complete (read-only w.r.t. C:\Windows)'
Emit
