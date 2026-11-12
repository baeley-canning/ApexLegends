# h316 post-restore - runs once at logon after a bugcheck (armed by h316_run.ps1). Copy of
# h310_post.ps1 with this number's files and the same provider order as the probe.
# R4 restore half the dead process could not run: DSE back to 6 with a read-back, service gone,
# auto-reboot back on, target cleaned up. Then the only reason the crash was worth it: the dump.
# Verdict comes from the dump, never from the fact that a bugcheck happened.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h316_post.txt'
$alt  = 'C:\Users\Public\p37\h316_post.txt'
function Say([string]$s) {
    $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s
    Write-Host $line
    # OneDrive is not always mounted yet at onlogon - a failed log write must never stop the restore
    if (-not (Add-Content -LiteralPath $out -Value $line -EA 0 -PassThru)) { Add-Content -LiteralPath $alt -Value $line -EA 0 }
}
Add-Content -LiteralPath $out -Value ('===== h316 post ' + (Get-Date -f 'yyyy-MM-dd HH:mm:ss') + ' =====') -EA 0
$cc = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
$dump = Join-Path $env:SystemRoot 'MEMORY.DMP'
$d = 'C:\Users\Public\p37'
Say ('boot=' + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('dd/MM HH:mm:ss') + ' uptime=' + [math]::Round(((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalMinutes, 1) + 'min')
Say ('post svc: ' + (((& "$env:SystemRoot\system32\sc.exe" query zapexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|does not exist' }) -join ' | ').Trim())

# --- the dump, before anything is cleaned up --------------------------------------------
$haveDump = $false; $dumpLen = 0
# the kernel dump is preferred, but on a 0x50 the box can fall back to a minidump (h310 r2 did:
# event 1001 names C:\WINDOWS\Minidump\110626-9968-01.dmp while MEMORY.DMP was never created).
# A minidump still carries the faulting stack and RIP, so take the newest one unless it predates the run.
$bootT = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$mini = @(Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -EA 0 | Where-Object { $_.LastWriteTime -gt $bootT.AddMinutes(-90) } | Sort-Object LastWriteTime -Descending)
if (Test-Path $dump) {
    $di = Get-Item $dump; $dumpLen = $di.Length; $haveDump = $true
    Say ('DUMP: yes size=' + $dumpLen + ' written=' + $di.LastWriteTime.ToString('dd/MM HH:mm:ss') + ' (boot was ' + $bootT.ToString('dd/MM HH:mm:ss') + ')')
} elseif ($mini.Count) {
    $dump = $mini[0].FullName; $dumpLen = $mini[0].Length; $haveDump = $true
    Say ('DUMP: no MEMORY.DMP, falling back to minidump ' + $mini[0].Name)
    Say ('DUMP: minidump size=' + $dumpLen + ' written=' + $mini[0].LastWriteTime.ToString('dd/MM HH:mm:ss') + ' all-fresh=' + $mini.Count)
} else {
    Say ('DUMP: NONE at ' + $dump + ' minidumps=' + @(Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -EA 0).Count + ' fresh=0')
}

# --- DSE back to 6, same provider ladder, read-back is the verdict ----------------------
$kdu = Join-Path $d 'kdu.exe'
$dseVerify = 'SKIP'
if (-not (Test-Path $kdu)) {
    Say 'dse: kdu.exe missing in the work dir, cannot verify'
} else {
    $ids = @()
    # the provider that actually won is the one to restore with: h316 records every attempt in
    # h316.prov and the winner in the run log; the guest feed is the fallback for an older tag.
    foreach ($src2 in (Join-Path $d 'h316.prov'), 'C:\p37vm\guest-h316.log', 'C:\Users\Public\p37\h316.out') {
        if (Test-Path $src2) {
            foreach ($l in (Get-Content $src2 -EA 0)) { if ($l -match 'prv (\d+) -> DSE off') { $ids += [int]$matches[1] } }
        }
    }
    foreach ($row in (Get-Content (Join-Path $d 'kdu_list.csv') -EA 0)) { if ($row -match '^\s*"?(\d{1,3})') { $ids += [int]$matches[1] } }
    # 0 first (it answered on this box), DirectIo64 14/27 and WinRing0 22 only if nothing else does
    $ids = @(0) + @($ids | Select-Object -Unique | Where-Object { @(0, 14, 27, 22) -notcontains $_ } | Select-Object -First 3) + @(22) + @(14, 27)
    $ids = @($ids | Select-Object -Unique)
    $f = New-Object System.Diagnostics.ProcessStartInfo
    $f.FileName = $kdu; $f.RedirectStandardOutput = $true; $f.RedirectStandardError = $true; $f.UseShellExecute = $false
    foreach ($id in $ids) {
        $writeOut = ''
        foreach ($pass in 'write', 'read') {
            $f.Arguments = $(if ($pass -eq 'write') { '-prv ' + $id + ' -dse 6' } else { '-prv ' + $id + ' -dse' })
            $o = ''
            try {
                $p = [System.Diagnostics.Process]::Start($f)
                $t1 = $p.StandardOutput.ReadToEndAsync(); $t2 = $p.StandardError.ReadToEndAsync()
                if (-not $p.WaitForExit(20000)) { try { $p.Kill() } catch { } }
                $o = ($t1.Result + $t2.Result)
            } catch { $o = '' }
            if ($pass -eq 'write') { $writeOut = ($o -replace '\s+', ' ').Trim() }
            elseif ($o -match 'value:\s*([0-9A-Fa-f]+)') {
                Say ('  dse write out=[' + $writeOut + '] readback via prv ' + $id + ' value=0x' + $matches[1])
                $dseVerify = $(if ($matches[1] -match '^0*6$') { 'PASS' } else { 'FAIL' })
                break
            } else { Say ('  dse readback prv ' + $id + ' no value: [' + (($o -replace '\s+', ' ').Trim()) + ']') }
        }
        if ($dseVerify -eq 'PASS') { break }
    }
    if ($dseVerify -ne 'PASS') { $dseVerify = 'FAIL' }
}
Say ('dse_verify=' + $dseVerify + ' (want PASS = 0x6)')

# --- remaining host-level restore ------------------------------------------------------
Set-ItemProperty -LiteralPath $cc -Name AutoReboot -Value 1 -Type DWord
Say ('auto-reboot readback=' + (Get-ItemProperty -LiteralPath $cc).AutoReboot)
foreach ($s in 'zapexdrv', 'apexdrv') { & "$env:SystemRoot\system32\sc.exe" delete $s 2>&1 | Out-Null }
Say ('svc after delete: ' + (((& "$env:SystemRoot\system32\sc.exe" query zapexdrv 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|does not exist' }) -join ' | ').Trim())
Get-Process notepad, regedit, mmc -EA 0 | Stop-Process -Force -EA 0
Remove-Item -LiteralPath 'C:\Users\Public\apxprobe.dll' -Force -EA 0
schtasks.exe /delete /tn p316post /f 2>&1 | Out-Null

# --- kd on the dump --------------------------------------------------------------------
$kd = @('C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\kd.exe', 'C:\Program Files\Windows Kits\10\Debuggers\x64\kd.exe', 'C:\Debuggers\kd.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $haveDump) {
    Say 'RESULT: FAIL - no dump at all (kernel hang, not a bugcheck)'
    Say 'VERDICT: FAIL - nothing to analyse; the path hangs, not faulted. Re-arm with the hang route'
} elseif (-not $kd) {
    Say 'RESULT: PARTIAL - dump present but kd.exe not found'
    Say 'VERDICT: PARTIAL - dump kept, run kd by hand'
} else {
    Say ('kd=' + $kd)
    $kdOut = Join-Path $here 'h316_post_kd.txt'
    # kd 10.0.26100 gives -i a required argument, so the bare '-i' ate '-z' and only printed usage.
    $argline = '-y C:\symbols -z "' + $dump + '" -c ".symopt- 100; !analyze -v; lm; q"'
    Say ('kd ' + $argline)
    $f = New-Object System.Diagnostics.ProcessStartInfo
    $f.FileName = $kd; $f.Arguments = $argline; $f.RedirectStandardOutput = $true; $f.RedirectStandardError = $true; $f.UseShellExecute = $false
    $txt = ''
    try {
        $p = [System.Diagnostics.Process]::Start($f)
        $t1 = $p.StandardOutput.ReadToEndAsync(); $t2 = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(360000)) { try { $p.Kill() } catch { }; Say 'kd TIMEOUT 360s' }
        $txt = ($t1.Result + "`r`n" + $t2.Result)
    } catch { Say ('kd LAUNCH FAIL ' + $_.Exception.Message) }
    Set-Content -LiteralPath $kdOut -Value $txt
    Say ('kd bytes=' + $txt.Length + ' -> ' + $kdOut)
    foreach ($pat in 'BUGCHECK_CODE:\s*(\S+)', 'BUGCHECK_P\d+:\s*(\S+)', 'IMAGE_NAME:\s*(\S+)', 'MODULE CONTAINING RIP:\s*(\S+)', 'FAILURE_BUCKET_ID:\s*(\S+)', 'SYMBOL_NAME:\s*(\S+)', 'PROCESS_NAME:\s*(\S+)') {
        foreach ($m in [regex]::Matches($txt, $pat)) { Say ('  ' + $m.Value.Trim()) }
    }
    $code = ([regex]::Match($txt, 'BUGCHECK_CODE:\s*(\S+)')).Groups[1].Value
    $img = ([regex]::Match($txt, 'IMAGE_NAME:\s*(\S+)')).Groups[1].Value
    $mod = ([regex]::Match($txt, 'MODULE CONTAINING RIP:\s*(\S+)')).Groups[1].Value
    if ($img -or $mod) {
        $who = $(if ($img) { $img } else { $mod })
        Say ('RESULT: dump read - code=' + $code + ' image=' + $img + ' module=' + $mod)
        Say ('VERDICT: fault in ' + $who + ' (code ' + $code + ') - ' + $(if ($who -match 'apexdrv|zapexdrv') { 'our driver image, that line is the bug' } else { 'NOT our image by name, read kb before blaming the mapper' }))
    } else {
        Say ('RESULT: PARTIAL - dump read, no IMAGE_NAME/MODULE (code=' + $code + ')')
        Say 'VERDICT: PARTIAL - read h316_post_kd.txt frames; faulting module not named'
    }
}
Say ('state: dse_verify=' + $dseVerify + ' auto=' + (Get-ItemProperty -LiteralPath $cc).AutoReboot + ' dump=' + $haveDump + ' dumpsize=' + $dumpLen)

