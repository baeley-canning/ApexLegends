# ============================================================================
# build\_probe_bcd.ps1 - READ-ONLY probe.  No BCD writes, no service changes.
#   * which bcdedit invocation form actually works from PowerShell here
#   * current testsigning / nointegritychecks state
#   * BitLocker protection state for C: (a BCD edit can force a recovery prompt)
# Output: build\phase1_evidence\_bcdtest.txt (UTF-8)
# Run:    powershell -NoProfile -ExecutionPolicy Bypass -File build\_probe_bcd.ps1
# ============================================================================
$ErrorActionPreference = 'Continue'


$evidence = Join-Path $PSScriptRoot 'phase1_evidence'
if (-not (Test-Path $evidence)) { New-Item -ItemType Directory -Path $evidence -Force | Out-Null }
$out = Join-Path $evidence '_bcdtest.txt'

$script:buffer = New-Object System.Collections.Generic.List[string]

function Add-Lines([object[]]$text) {
    foreach ($t in $text) { $script:buffer.Add([string]$t) }
}

function Add-Section([string]$title, [object[]]$text) {
    Add-Lines ''
    Add-Lines "--- $title ---"
    if ($null -eq $text -or ($text -join '').Trim().Length -eq 0) {
        Add-Lines '(no output)'
    } else {
        Add-Lines @($text | ForEach-Object { "$_".TrimEnd() })
    }
}

Add-Lines "== bcd probe $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') =="
Add-Lines "powershell      : $($PSVersionTable.PSVersion)"
Add-Lines "elevated        : $((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"

# A. does the plain store open?  /enum all takes no brace identifier at all.
$rawAll = & bcdedit /enum all 2>&1
Add-Section 'A: bcdedit /enum all (first 25 lines)' ($rawAll | Select-Object -First 25)

# B. {current} through cmd.exe - avoids PowerShell's brace/encodedCommand rewrite.
$viaCmd = & cmd /c 'bcdedit /enum {current}' 2>&1
Add-Section 'B: cmd /c bcdedit /enum {current}' $viaCmd

# C. flags we care about, from the full store dump.
$flags = $rawAll | Select-String -Pattern 'testsigning|nointegritychecks|hypervisorlaunchtype'
Add-Section 'C: loader flags in store' ($flags | ForEach-Object { $_.Line.Trim() })

# D. BitLocker - is a BCD change going to cost a recovery key?
$bde = & manage-bde -status C: 2>&1
Add-Section 'D: manage-bde -status C:' $bde

# E. Secure Boot / VBS.
Add-Lines ''
Add-Lines '--- E: Secure Boot / VBS ---'
try {
    $sb = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
    Add-Lines "security services running : $($sb.SecurityServicesRunning -join ',')"
} catch {
    Add-Lines "DeviceGuard CIM failed: $($_.Exception.Message)"
}
try {
    $uefi = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction Stop
    Add-Lines "UEFISecureBootEnabled     : $($uefi.UEFISecureBootEnabled)"
} catch {
    Add-Lines "SecureBoot\State read failed: $($_.Exception.Message)"
}

Add-Lines 'END'

$script:buffer | Set-Content -Encoding utf8 $out
Write-Host "wrote $out"

