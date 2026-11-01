================================================================================
THE TEST-SIGNING GATE — MEASURED ON THIS BOX (2026-11-01)
================================================================================
Path : QwenKernPremium/docs/JAVELIN_TESTSIGNING_GATE_2026-11-01.md
Grade: every claim is either [VERIFIED-<date> by <probe>] (reproducible from _ritual\) or
       [HYPOTHESIS] / [RE] (community or reasoning only). Nothing here is hearsay.

0. THE FINDING IN ONE LINE
-------------------------------------------------------------------------------
A self-signed kernel driver (apexdrv.sys, no Microsoft-root chain) can be forced to LOAD and stay
RUNNING by booting Windows in test mode — but the box is then in a state that EA AntiCheat / Javelin
refuses: "Device Driver signing integrity checks must be enabled to start the game." Flipping the
flag off after boot silences the popup, but the game has not yet been shown to SURVIVE.

1. THE REFUSAL, EXACTLY AS DELIVERED
-------------------------------------------------------------------------------
[VERIFIED-01-11-2026 by p33 T1] Windows Application log, provider "Application Popup", level
"Application popup", event id 26, fired 21:15:27 for a game launched 21:15:21:

  Security Violation : Device Driver signing integrity checks must be enabled to start the game.

Same message seen in p9 (14:39), p27 (20:36) and p33 T1. Clicking OK on the box does not save the
match — the game dies anyway. There is a SECOND refusal family that is NOT an Application Popup and
therefore never appears in the event log: the in-game EAAC panel
  "Security Violation (2) : This software cannot be used at the same time as the game."
hit in p29 RUN2 (20:39) after our driver had been STOPPED. Any harness that only greps the event log
(p33's `$RX` filter does exactly that) is blind to family (2).

2. WHY THE DRIVER NEEDS TEST MODE AT ALL  (DSE, not Javelin)
-------------------------------------------------------------------------------
[VERIFIED-01-11-2026 by p24-p26, p33] With `testsigning off`, `sc start apexdrv` fails with
WIN32_EXIT_CODE 577 "Windows cannot verify the digital signature for this file" — that is the kernel's
Driver Signature Enforcement refusing a self-signed .sys at load time. p24-p26 tried to fake a
Microsoft-root chain by hand (catalog + cross-sign shapes, `/kp` variants) and never satisfied it.
In BOOT test mode the same binary loads first try: p33 21:15:10 `STATE 4 RUNNING`, exit code 0,
still RUNNING at 21:18:45 after three game launches.

=> The 577 is load-time DSE only. It has nothing to do with Javelin, and "boot in test mode" is a
   complete workaround for it.

3. THE ISOLATION A/B — THE FLAG IS THE POPUP TRIGGER
-------------------------------------------------------------------------------
[VERIFIED-01-11-2026 by p27/p29/p31]
  p27 as-is      : apexdrv RUNNING + testsigning ON  -> popup family (1) at 20:36:21, game dead.
  p29 RUN2       : apexdrv STOPPED + testsigning ON  -> NO popup event, but the family (2) in-game
                   panel appeared and the game still died.
  p30            : `sc delete apexdrv`, every apexdrv*.sys in System32\drivers renamed *.off.
  p31 (20:52)    : reboot with testsigning OFF -> popup GONE, r5apex_dx12 + EAAntiCheat.GameService
                   alive at T+300 s, eaanticheat + EAAntiCheatService RUNNING, 0 CI events.
=> TWO independent variables are fatal, and removing our driver only changes WHICH refusal you get.
   Both must be dealt with; testsigning was proven to be one of them.

4. THE FLAG-FLIP EXPERIMENT (p33) — DESIGN AND RAW RESULT
-------------------------------------------------------------------------------
Design: boot WITH testsigning ON so the driver can load, then flip the flag off live (BCD first, then
the registry `SystemStartOptions`) and relaunch the game after each flip — the driver stays loaded the
whole time because there is no reboot. If Javelin reads a flag instead of the live kernel CI state,
one of those flip states must run the game WITH the driver up.

Result (p33_flagflip.txt, 21:15-21:18) [VERIFIED-01-11-2026 by p33]:

  T1 flag ON everywhere        popup=True  died=False  alive=False  apexdrv_RUNNING=True
  T2 BCD testsigning cleared   popup=False died=False  alive=False  apexdrv_RUNNING=True
  T3 T2 + SystemStartOptions   popup=False died=False  alive=False  apexdrv_RUNNING=True
     scrubbed to 'NOEXECUTE=OPTIN HYPERVISORLAUNCHTYPE=AUTO NODEBUG FVEBOOT=2666496 NOVGA'
     (backup of the original string: _ritual\_p33_sso.bak)

So: the popup follows the FLAG SOURCE (BCD and the mirrored SystemStartOptions string), and clearing
both silences it completely. That part is solid and is the useful half of p33.

5. THE BUG IN p33's VERDICT — WHY "GREEN" OVER-CLAIMS
-------------------------------------------------------------------------------
`$died` only ticks when a poll first SAW the game up: `if($first -ne 0 -and -not $p -and -not $died)`.
The poll interval is 5 s and the game exits in ~6 s, so a fast exit is recorded as `died=False`.
`alive=False` in all three trials means the game was NOT running when the window closed.
The GREEN branch tests only `(-not popup) -and (-not died)` -> it fires on T3, printing
"Javelin reads the FLAG SOURCE ... SHIP IT", while the game was in fact dead every time.

=> p33 proves: popup is flag-driven. p33 does NOT prove: game survives with the driver loaded.
   (Re-checked on the machine at 21:22: 0 r5apex_dx12 processes, apexdrv still RUNNING.)

6. CORRECTED STATE OF PLAY (2026-11-01 21:22, this machine)
-------------------------------------------------------------------------------
  [VERIFIED] testsigning ON  -> apexdrv loads and stays RUNNING (STATE 4); Javelin popup id 26.
  [VERIFIED] testsigning OFF -> game runs 300 s clean (driver absent); apexdrv refused at load (577).
  [VERIFIED] the popup is silenced by clearing BCD `testsigning` AND the SystemStartOptions mirror.
  [OPEN]     game survival while the driver is loaded, in ANY flag state.
Machine snapshot at doc time: 0 `r5apex_dx12` processes, `EADesktop` running, `apexdrv` STATE 4 RUNNING,
`bcdedit /enum` reports neither testsigning nor nointegritychecks, SystemStartOptions scrubbed.
The box is therefore sitting in "flag off + driver loaded" and the game does not survive it.

7. MECHANISM — WHY "FLAG SOURCE" AND "LIVE CI STATE" ARE DIFFERENT THINGS
-------------------------------------------------------------------------------
[RE] The kernel state DSE acts on is `g_CiOptions`, patched ONCE at boot from the BCD `testsigning`
element (0x8 TESTSIGNING, 0x1 NOINTEGRITYCHECKS). Editing BCD afterwards does NOT rewrite
`g_CiOptions` until the next boot, so: an already-loaded driver stays loaded, no *new* self-signed
driver can load, while the *string* that BCD/registry reports flips to "off" immediately. That string
is what Javelin's user-mode side can read cheaply (EAAntiCheat.GameService also mirrors it into
`Control\SystemStartOptions`, hence T3). This is exactly why T2/T3 silence the popup without touching
live kernel state — and why "no popup" must never be read as "CI state is clean".

Corollary that decides the project: if Javelin/EAAC additionally queries LIVE CI state (its own
test-signed helper, NtQuerySystemInformation(SystemCodeIntegrityInformation), its minifilter's view of
the load), then booting in test mode is fatal no matter what the strings say. That is the RED branch,
and it is what p34 exists to detect.

8. THE MISSING DISCRIMINATOR — p34  (run34.cmd / p34_matrix.ps1)
-------------------------------------------------------------------------------
Same flag-off box, two trials, only the driver's presence varies:
  TA: `sc stop apexdrv`  -> launch game -> 1 s poll, 120 s
  TB: `sc start apexdrv` -> launch game -> 1 s poll, 120 s
Fixes over p33: 1 s sampling (a 6 s exit cannot hide), per-trial process exit code and uptime, ALL
Application/System events in the window captured verbatim instead of only the popup regex (so the
family (2) panel and EAAC service errors become visible), EAAC service state sampled during the run,
driver state re-asserted and logged before each launch.

How to read it:

  TA alive, TB dead  -> the DRIVER'S PRESENCE is the fatal variable when the flag is off. Fix the shape
                        and the timing of the load, not the signature. Try, in order: load AFTER the
                        game is up; unique service name; drop the MajorFunction overwrite; comm over a
                        shared-memory section; no system thread in unbacked memory; no collision on
                        \Device\apexdrv; re-test with the driver never having existed before the game.
  TA dead too        -> the LIVE CI STATE is fatal (test mode itself). RED: get a real chain (EV ->
                        Microsoft attestation signing needs no HLK) or never register a service at all
                        (BYOVD manual map with a device Javelin tolerates).
  TA and TB alive    -> GREEN: boot test mode + logon scrub ships, driver stays live with the game.
  TB alive, TA dead  -> the driver is required, or the stop/start transition leaves residue behind
                        (check EAAC service state and any leftover device object between trials).

9. OPERATIONAL RECIPES (for whichever branch p34 selects)
-------------------------------------------------------------------------------
Boot in test mode and let the driver load (this is what p33 phase A does):

  copy QwenKernPremium\build\apexdrv.sys C:\Windows\System32\drivers\apexdrv.sys
  bcdedit /set {current} testsigning on
  bcdedit /set {current} nointegritychecks off
  shutdown /r /t 0
  :: after logon
  sc create apexdrv type= kernel binPath= \SystemRoot\System32\drivers\apexdrv.sys
  sc start apexdrv                      :: STATE 4 RUNNING, exit code 0

Silence the popup while keeping the loaded driver (T2/T3; must run at EVERY logon because the kernel
rewrites SystemStartOptions from BCD at boot):

  bcdedit /set {current} testsigning off
  $p = 'HKLM:\SYSTEM\CurrentControlSet\Control'
  (Get-ItemProperty $p -Name SystemStartOptions).SystemStartOptions | Set-Content _p33_sso.bak
  Set-ItemProperty $p -Name SystemStartOptions -Value (
     ((Get-ItemProperty $p -Name SystemStartOptions).SystemStartOptions -replace '\s*TESTSIGNING\s*',' ') -replace '\s+',' ').Trim()

Order matters: bcdedit first (it rewrites the BCD element), then scrub the mirror. Consequence to
design around: the kernel only accepts the self-signed driver on a boot whose BCD said testsigning ON,
so the driver must be loaded/staged in that session — a logon task that does "load driver + scrub
flags" is the productised form of T3.

10. IF RED — THE REAL-SIGNATURE PATH, AND ITS ALTERNATIVES
-------------------------------------------------------------------------------
Goal: make `apexdrv.sys` load on a NORMAL boot so no test mode, no scrub, no popup.
  [B] EV code-signing certificate -> Microsoft attestation signing (dev portal). No HLK needed, gives an
      MS-root chain, driver loads with DSE on. This is option B3 in INJECTION_MENU_AND_RISK_MATRIX.txt
      and the clean long-term answer. Cost: certificate + portal submissions per revision.
  [B] WHQL / HLK signing — stronger, more setup, only needed for the portal listing.
  [B] Cross-signing with the old cross-certificates — attempted in p24-p26, never satisfied /kp in 2026.
  [B] BYOVD: never register a service at all; manual-map apexdrv into kernel memory with a vulnerable
      driver the AC tolerates (gdrv3 is present and read-only today; MsIo64 loads but its map path is
      unproven). Trade-off: unbacked memory is itself a Javelin signal, and mapping is not persistent.
  [B] Ship external-only: the ACG-safe usermode ladder, driver only for users who accept a test-mode
      boot. Zero signing cost, immediate.

11. ENVIRONMENT FACTS THAT SHAPED EVERY PROBE (kept so nobody re-discovers them)
-------------------------------------------------------------------------------
  - Apex install is DX12-only: `r5apex_dx12.exe`; there is no `r5apex.exe`. It statically imports a
    single module, `Core/Activation64.dll`; `d3d12.dll`/`dxgi.dll` are resolved dynamically, and
    "d3d11" appears nowhere in the image. A byte-identical copy "baeleys game.exe" sits in the folder.
  - Javelin userspace root: `C:\Program Files\EA\AC\EAAntiCheat.GameService.exe` (service
    `EAAntiCheatService`, LocalSystem, session 0). Kernel side: service `EAAntiCheat`, type 2,
    group "FSFilter Activity Monitor", altitude 363250, DependOnService FltMgr, ImagePath
    `system32\drivers\eaanticheat.sys` — RUNNING while that .sys is absent from disk.
  - EA app path used by the harness: `...\EA Desktop\...\EA Desktop\EADesktop.exe`.
  - Game exe: `C:\Program Files\EA Games\Apex\r5apex_dx12.exe`.
  - Launch elevation is a constant across run27 and p33 (both launched from an elevated shell) and
    run27 survived, so elevation alone is not the variable.

12. TRAPS / HOW NOT TO RE-BREAK THIS
-------------------------------------------------------------------------------
  - `sc start` right after `sc create` can race the device object; query STATE before trusting a load.
  - `bcdedit` rewrites BOTH the element and the SystemStartOptions mirror at boot — scrub at every logon.
  - The popup regex misses the in-game EAAC panel (section 1). Capture all events.
  - p33-style "died" flags need the game to have been seen up; with a 5 s poll that is a coin flip.
  - PowerShell 5.1: `Func()` on a zero-arg function breaks in expression context.
  - Do not overwrite R5AC-monitored VMT slots without a trampoline; do not allocate PAGE_EXECUTE inside
    the game and assume success; do not build a system thread in unbacked memory.
  - Do not statically import a module the game does not load (verify with `dumpbin /dependents`).

13. EVIDENCE MAP
-------------------------------------------------------------------------------
| Claim | File |
|---|---|
| popup id 26 with driver loaded | `_ritual\p27_gate*.txt`, `p33_flagflip.txt` (T1 21:15:27) |
| driver loads + stays RUNNING in test mode | `_ritual\p33_flagflip.txt` (21:15:10-21:18:45) |
| 577 at load with testsigning off | `_ritual\p24*`-`p26*`, `QwenKernPremium\build\phase1_evidence\driver_sign_load.txt` |
| flag is the popup trigger (A/B) | `_ritual\p29_gate2*`, `p31*`, `run27.cmd` |
| vanilla box is clean for 300 s | `_ritual\p31_bootverify.txt` (20:58:29) |
| T2/T3 silence the popup without a reboot | `_ritual\p33_flagflip.txt` (21:16:07, 21:17:26) |
| original SystemStartOptions | `_ritual\_p33_sso.bak` |
| full BCD snapshots | `_ritual\bcd_before_20261101_*.bcd` |

OPEN: (1) does the game survive with the driver loaded (p34 TA/TB); (2) does Javelin read live CI state
or only the strings — answered by the same matrix; (3) if the driver is the blocker, which load-shape
detail triggers it (service name, dispatch table, device path, load timing); (4) does the answer hold on
a normal reboot vs a live flip (needs one confirmation boot); (5) does Javelin care that `apexdrv` was
loaded BEFORE the game started.


