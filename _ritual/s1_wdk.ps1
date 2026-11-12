# s1_wdk.ps1 - Stage-1 recon feed (read-only): WDK VAD/EPROCESS surface, apexdrv anchors,
# staging recipe, M2 spec text. Writes _ritual\s1_wdk.out (read the file, not the console).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File <this>
$ws  = 'C:\Users\New User\OneDrive\Desktop\cheating'
$out = Join-Path $ws '_ritual\s1_wdk.out'
if (Test-Path $out) { Remove-Item -LiteralPath $out }
function L([string]$s) { Add-Content -LiteralPath $out -Value $s }
function LT($n, $txt) { $t = [string]$txt; if ($t.Length -gt 150) { $t = $t.Substring(0,150) }; L ("L{0}: {1}" -f $n, $t.Trim()) }
function LM($f, $n, $txt) { $t = [string]$txt; if ($t.Length -gt 150) { $t = $t.Substring(0,150) }; L ("{0}:{1}: {2}" -f $f, $n, $t.Trim()) }

L ("S1 WDK/ANCHOR RECON " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

L '=== WDK include versions ==='
Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\Include' -Directory -ErrorAction SilentlyContinue | ForEach-Object { L $_.Name }

$km = 'C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\km'
L '=== WDK km headers: EPROCESS/VAD surface ==='
foreach ($h in 'ntifs.h','ntddk.h','wdm.h') {
  $p = Join-Path $km $h
  if (-not (Test-Path $p)) { L "--- $h MISSING ---"; continue }
  L "--- $h ---"
  foreach ($pat in 'VadRoot','typedef struct _EPROCESS','UniqueProcessId','_MMVAD','PsGetProcessSectionBaseAddress','MmGetNextVadNode','SUBSECTION','MmCopyMemory','RTL_AVL_TREE','VadList','SeLocateProcessImageName') {
    $m = @(Select-String -LiteralPath $p -Pattern $pat -SimpleMatch -ErrorAction SilentlyContinue | Select-Object -First 4)
    L ("PAT {0} -> {1} hit(s)" -f $pat, $m.Count)
    $m | ForEach-Object { LT $_.LineNumber $_.Line }
  }
}

L '=== apexdrv.c copies ==='
$cs = @(Get-ChildItem $ws -Recurse -Filter 'apexdrv.c' -File -ErrorAction SilentlyContinue)
$cs | ForEach-Object { L $_.FullName }
if ($cs.Count -gt 0) {
  $drv = $cs | Sort-Object Length -Descending | Select-Object -First 1
  $lc = (Get-Content -LiteralPath $drv.FullName | Measure-Object -Line).Lines
  L ("PICK {0} ({1} lines)" -f $drv.FullName, $lc)
  foreach ($pat in 'APEXDRV_VERSION','IOCTL_APEXDRV','ApexdrvReadProcessMemory','ApexdrvWriteProcessMemory','ApexdrvProbeProcess','ApexdrvWalkModules','MmGetSystemRoutineAddress','PsGetProcessPeb','KeStackAttachProcess','ApexdrvOpenProcess') {
    L "--- $pat ---"
    @(Select-String -LiteralPath $drv.FullName -Pattern $pat -SimpleMatch -ErrorAction SilentlyContinue) | ForEach-Object { LT $_.LineNumber $_.Line }
  }
}

L '=== apex_driver_ioctl.h ==='
$hd = @(Get-ChildItem $ws -Recurse -Filter 'apex_driver_ioctl.h' -File -ErrorAction SilentlyContinue | Select-Object -First 1)
if ($hd.Count -gt 0) {
  L ("HDR {0}" -f $hd[0].FullName)
  @(Select-String -LiteralPath $hd[0].FullName -Pattern 'IOCTL_APEXDRV|APEXDRV_VERSION|typedef struct|#define APEXDRV' -ErrorAction SilentlyContinue) | ForEach-Object { LT $_.LineNumber $_.Line }
}

L '=== BuildDriver.ps1 (head 140) ==='
$bd = @(Get-ChildItem $ws -Recurse -Filter 'BuildDriver.ps1' -File -ErrorAction SilentlyContinue | Select-Object -First 1)
if ($bd.Count -gt 0) { L ("BUILD {0}" -f $bd[0].FullName); Get-Content -LiteralPath $bd[0].FullName -TotalCount 140 | ForEach-Object { L $_ } }

L '=== _ritual h3x/cur/drvbuild/s1 files ==='
@(Get-ChildItem (Join-Path $ws '_ritual') -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(h3|cur|_h518|s1)' }) | ForEach-Object { L $_.Name }

L '=== staging/ABI greps in _ritual + tools (first 24 each) ==='
foreach ($pat in 'zapexdrv','System32\\drivers','sc\.exe create|sc create|New-Service','8080','HttpListener','IOCTL_APEXDRV|APEXDRV_','E906CEE9|9B119FD0') {
  L "--- $pat ---"
  @(Select-String -Path (Join-Path $ws '_ritual\*.ps1'),(Join-Path $ws 'QwenKernPremium\tools\*.ps1') -Pattern $pat -ErrorAction SilentlyContinue | Select-Object -First 24) | ForEach-Object { LM $_.Filename $_.LineNumber $_.Line }
}

L '=== M2 spec lines 30-125 ==='
$m2 = Join-Path $ws 'M2_KERNEL_CHEAT_HANDOFF_PROMPT.md'
if (Test-Path $m2) { $i = 0; Get-Content -LiteralPath $m2 | ForEach-Object { $i++; if ($i -ge 30 -and $i -le 125) { L ("M2:{0}: {1}" -f $i, $_) } } }

L '=== STATE.md version/Base hits (first 30) ==='
@(Select-String -LiteralPath (Join-Path $ws 'STATE.md') -Pattern 'APEXDRV_VERSION|apexdrv v|v13|version 13|Base\(pid\)' -ErrorAction SilentlyContinue | Select-Object -First 30) | ForEach-Object { L ("STATE:{0}: {1}" -f $_.LineNumber, $_.Line.Trim()) }

L ("DONE " + (Get-Date -Format 'HH:mm:ss'))
