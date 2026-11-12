# ============================================================================
# _ritual\ov72_hookinject.ps1 - get apexcheat.dll into the live game WITHOUT
# touching the game's memory from outside.
#
# ov69/ov70/ov71 measured the wall: OpenProcess is granted for every right set,
# but VirtualAllocEx=5, ReadProcessMemory=5 and CreateRemoteThread=5 on this
# build - an access jail, not an allocation problem.  So ov72 lets the OS do it:
# SetWindowsHookEx maps ov72hook.dll into the game's GUI thread (the loader runs
# inside the game), and that hook does one LoadLibraryW of the real payload.
#
# Variable vs ov71: injection MECHANISM (hook/loader vs remote thread).
# Reversibility: both hooks are unhooked in the same run; the payload then stays
# in the game until the game exits (the state the user asked for).
# ============================================================================
param([int] $Pid0 = 0, [string] $HookDll = 'C:\h330\ov72hook.dll',
      [int] $WaitSec = 240, [switch] $Elevate, [string] $Tag = 'ov72', [int] $WaitGameSec = 0)

$ErrorActionPreference = 'Stop'
$rit  = $PSScriptRoot
$out  = Join-Path $rit ($Tag + '_hook.out')
$utf8 = [Text.UTF8Encoding]::new($false)
function W([string] $s) { [IO.File]::AppendAllText($out, $s + "`r`n", $utf8); Write-Host $s }
function Finish([string] $v, [int] $c) { W ''; W "RESULT: $v"; W "$Tag DONE $v"; exit $c }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and $Elevate) {
    if (Test-Path $out) { Remove-Item -LiteralPath $out -Force }
    $a = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Elevate -Pid0 {1} -Tag {2} -HookDll "{3}" -WaitGameSec {4}' -f $PSCommandPath, $Pid0, $Tag, $HookDll, $WaitGameSec)
    Start-Process powershell -Verb RunAs -ArgumentList $a
    Write-Host 'ov72: relaunched elevated'
    exit 0
}
$t0 = Get-Date   # start time - the payload log freshness gate compares against this
[IO.File]::WriteAllText($out, ($Tag + " - hook/loader injection - " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "`r`n"), $utf8)

$p = if ($Pid0) { Get-Process -Id $Pid0 -ErrorAction SilentlyContinue } else { @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue) | Select-Object -First 1 }
if (-not $p -and $WaitGameSec -gt 0) {
    W "waiting up to $WaitGameSec s for r5apex_dx12 with a window..."
    $wdl = (Get-Date).AddSeconds($WaitGameSec)
    while ((Get-Date) -lt $wdl) {
        Start-Sleep -Seconds 3
        $cand = @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue) | Select-Object -First 1
        if ($cand -and $cand.MainWindowHandle -ne 0) { $p = $cand; break }
    }
    if ($p) { W "game appeared: pid=$($p.Id) - 8 s settle"; Start-Sleep -Seconds 8 }
}
if (-not $p) { Finish 'FAIL no-game' 1 }
$procId = [int] $p.Id
$hwnd   = (Get-Process -Id $procId).MainWindowHandle
W "target   : pid=$procId hwnd=$hwnd elevated=$isAdmin"
if ($hwnd -eq 0) { Finish 'FAIL no-window' 1 }
if (-not (Test-Path -LiteralPath $HookDll)) { Finish "FAIL hook dll missing: $HookDll" 1 }

$hookLog   = Join-Path $rit 'ov72_hooklog.txt'
$payLog    = Join-Path $env:LOCALAPPDATA "QwenKern\payload_$procId.log"   # primary (log.cpp)
$payLogAlt = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\payload_' + $procId + '.log'  # log.cpp fallback dir
$canary    = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium\build\apexcheat_attach.log'         # raw DllMain canary (main.cpp)
if (Test-Path $hookLog) { Remove-Item -LiteralPath $hookLog -Force }
if (Test-Path $canary) { Remove-Item -LiteralPath $canary -Force }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Sp72 {
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)] public static extern IntPtr LoadLibraryW(string p);
    [DllImport("kernel32", CharSet = CharSet.Ansi, SetLastError = true)] public static extern IntPtr GetProcAddress(IntPtr m, string n);
    [DllImport("user32", SetLastError = true)] public static extern IntPtr SetWindowsHookExW(int id, IntPtr fn, IntPtr mod, uint tid);
    [DllImport("user32", SetLastError = true)] public static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32", SetLastError = true)] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32", SetLastError = true)] public static extern bool EnumWindows(EnumProcW cb, IntPtr lp);
    public delegate bool EnumProcW(IntPtr h, IntPtr lp);
    [DllImport("user32", SetLastError = true)] public static extern bool PostMessageW(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32", SetLastError = true)] public static extern IntPtr SendMessageTimeoutW(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint ms, out IntPtr res);
}
'@

$hMod = [Sp72]::LoadLibraryW($HookDll)
if ($hMod -eq [IntPtr]::Zero) { Finish ("FAIL LoadLibraryW hook dll err=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error()) 1 }
$proc = [Sp72]::GetProcAddress($hMod, 'OV72Hook')
W ("hook dll : hMod={0} proc=0x{1:X}" -f $hMod, $proc.ToInt64())
if ($proc -eq [IntPtr]::Zero) { Finish 'FAIL OV72Hook export not found' 1 }

$winPid = 0
$tid = [Sp72]::GetWindowThreadProcessId($hwnd, [ref] $winPid)
W "thread   : gui tid=$tid windowPid=$winPid"

# ---- arm on EVERY thread owning a top-level game window ------------------------
# ov75 lesson: at arm time MainWindowHandle was the SPLASH window; its thread had
# stopped pumping, so the single hook never fired while the console-side instance
# ran fine (all lines [g<waiter>], zero [g<game>]).  Now: scan ALL windows of the
# pid, re-scan every pass (splash -> menu spawns NEW threads), post to every window.
$script:gpid     = $procId
$script:gwins    = New-Object System.Collections.ArrayList
$script:armed    = @{}
$script:allHooks = New-Object System.Collections.ArrayList
$enumCb = [Sp72+EnumProcW]{
    param($h, $l)
    $wp = 0
    [void][Sp72]::GetWindowThreadProcessId($h, [ref] $wp)
    if ($wp -eq $script:gpid) { [void]$script:gwins.Add($h) }
    return $true
}
function Arm-Tids {
    $script:gwins = New-Object System.Collections.ArrayList
    [void][Sp72]::EnumWindows($enumCb, [IntPtr]::Zero)
    foreach ($w in $script:gwins) {
        $wp2 = 0; $wt = [Sp72]::GetWindowThreadProcessId($w, [ref] $wp2)
        if ($wt -ne 0 -and -not $script:armed.ContainsKey($wt)) {
            $h1 = [Sp72]::SetWindowsHookExW(3, $proc, $hMod, [uint32] $wt)
            $h2 = [Sp72]::SetWindowsHookExW(4, $proc, $hMod, [uint32] $wt)
            $script:armed[$wt] = @($h1, $h2)
            [void]$script:allHooks.Add($h1); [void]$script:allHooks.Add($h2)
            W ("arm      : tid=$wt hwnd=$w getmsg={0} callwnd={1} err={2}" -f $h1, $h2, [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
    }
}
[void](Arm-Tids)
W ("tids     : armed $($script:armed.Count) window thread(s): " + (($script:armed.Keys | Sort-Object) -join ','))
if ($script:allHooks.Count -eq 0) { Finish 'FAIL SetWindowsHookEx (all tids)' 1 }

$deadline = (Get-Date).AddSeconds($WaitSec)
$fired = $false
while ((Get-Date) -lt $deadline) {
    [void](Arm-Tids)                                                          # catch new threads (splash -> menu)
    foreach ($w in $script:gwins) {
        [void][Sp72]::PostMessageW($w, 0, [IntPtr]::Zero, [IntPtr]::Zero)      # WM_NULL
        [void][Sp72]::PostMessageW($w, 0x0400, [IntPtr]::Zero, [IntPtr]::Zero) # WM_USER
    }
    $res = [IntPtr]::Zero
    [void][Sp72]::SendMessageTimeoutW($hwnd, 0, [IntPtr]::Zero, [IntPtr]::Zero, 0x2, 500, [ref] $res)
    Start-Sleep -Milliseconds 700
    # Evidence = a line written by the GAME-side instance, tagged [g<gamepid>].
    # The console instance writes the same file from the moment we LoadLibraryW
    # this DLL for the proc address, so mere existence is NOT proof (ov73 trap).
    if ((Test-Path -LiteralPath $hookLog) -and
        ((Get-Content -LiteralPath $hookLog -Raw) -match ('\[g' + $procId + '\]'))) { $fired = $true; break }
    if (-not (Get-Process -Id $procId -ErrorAction SilentlyContinue)) { break }
}
W "hook ran (game-side [g$procId] line present) : $fired"
if (Test-Path $hookLog) { W '---- hook log ----'; W ([IO.File]::ReadAllText($hookLog)); Copy-Item -LiteralPath $hookLog -Destination (Join-Path $rit ($Tag + '_hooklog.txt')) -Force }

if ($fired) { Start-Sleep -Seconds 2 }        # let any concurrent loader finish before refs drop
foreach ($h in $script:allHooks) { if ($h -and $h -ne [IntPtr]::Zero) { [void][Sp72]::UnhookWindowsHookEx($h) } }
W ("hooks    : unhooked $($script:allHooks.Count) handle(s) (R4; hook dll self-pins, heartbeat continues)")


$payNow = $null
foreach ($c in @($payLog, $payLogAlt)) {
    if ((Test-Path -LiteralPath $c) -and ((Get-Item -LiteralPath $c).LastWriteTime -gt $t0.AddSeconds(-2))) { $payNow = $c; break }
}
$fresh = [bool] $payNow
W "paylog   : $payLog fresh=$fresh (alt: $payLogAlt)"
if ($fresh) { W ([IO.File]::ReadAllText($payNow)) }
$alive = [bool](Get-Process -Id $procId -ErrorAction SilentlyContinue)
W "game     : alive=$alive"
if ($fresh) { Copy-Item -LiteralPath $payNow -Destination (Join-Path $rit ($Tag + '_payload_' + $procId + '.log')) -Force }

# ---- payload readiness gate (Initialize finished, hooks live) -----------------
$ready = $false
$rdl = (Get-Date).AddSeconds(90)
while ((Get-Date) -lt $rdl) {
    foreach ($c in @($payLog, $payLogAlt)) {
        if ((Get-Content -LiteralPath $c -Raw -ErrorAction SilentlyContinue) -match 'main loop started|Render hook installed|overlay ready') { $ready = $true; break }
    }
    if ($ready) { break }
    if (-not (Get-Process -Id $procId -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 500
}
W "payload ready: $ready"

# ---- frames -----------------------------------------------------------------
$keyOut = Join-Path $rit ($Tag + '_key.txt')
$k = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $rit 'h159_insertkey.ps1') -GamePid $procId -Out $keyOut) -join ' | '
W "INSERT   : $k"
Start-Sleep -Seconds 3
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $rit 'shot_desk.ps1') | Out-Null
Copy-Item -LiteralPath (Join-Path $rit 'shot_desk.png') -Destination (Join-Path $rit ($Tag + '_shot_menu.png')) -Force
Start-Sleep -Seconds 8
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $rit 'shot_desk.ps1') | Out-Null
Copy-Item -LiteralPath (Join-Path $rit 'shot_desk.png') -Destination (Join-Path $rit ($Tag + '_shot_menu_late.png')) -Force
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $rit 'ocr.ps1') `
    -Path (Join-Path $rit ($Tag + '_shot_menu.png')) -Out (Join-Path $rit ($Tag + '_ocr_menu.txt')) | Out-Null
$menuTxt = if (Test-Path (Join-Path $rit ($Tag + '_ocr_menu.txt'))) { [IO.File]::ReadAllText((Join-Path $rit ($Tag + '_ocr_menu.txt'))) } else { '' }
if (Test-Path $canary) { W '---- payload attach canary (tail 40) ----'; W (((Get-Content -LiteralPath $canary -Tail 40 -ErrorAction SilentlyContinue) | Out-String).Trim()) } else { W '---- payload attach canary: MISSING ----' }
$pc = if ($payNow) { $payNow } elseif (Test-Path -LiteralPath $payLogAlt) { $payLogAlt } elseif (Test-Path -LiteralPath $payLog) { $payLog } else { $null }
if ($pc) { W "---- payload log tail ($pc) ----"; W (((Get-Content -LiteralPath $pc -Tail 40) | Out-String).Trim()) }
W '---- OCR (menu) ----'
W $menuTxt

$menuHit = ($menuTxt -match 'QWENKERN|AIMBOT|VISUALS|MISCELLANEOUS|EXPLOITS|SETTINGS|ESP')
W "check menu on screen : $menuHit"
$pass = $alive -and $fresh -and $ready -and $menuHit
Finish $(if ($pass) { 'PASS payload loaded by the loader, menu on screen' } else { 'FAIL see checks above' }) $(if ($pass) { 0 } else { 2 })
