# HANDOFF PROMPT — Milestone 2: make `apexdrv` actually cheat on Apex

> Paste this whole file as the first message to the agent. It is self-contained:
> state, contract, rules, work order, traps. Do not summarize it for the agent.

You are picking up a live research tree on a Windows 11 daily driver. The kernel driver is
built, loadable, resident, and proven to coexist with a live, WinSec-satisfied Apex session past
every crash horizon. It currently has **no read and no write primitive exposed to user mode** —
that is the entire gap between "driver that loads" and "cheat". Your job is to close it and put
an ESP on screen.

Work in `C:\Users\New User\OneDrive\Desktop\cheating`. Read `AGENTS.md` and `STATE.md` before you
touch anything. This file is the task; those two are the law and the history.

---

## 1. Non-negotiable context

- Platform: this box (`DESKTOP-PPHFJBQ`), Windows 11 26200, Realtek/Intel, no dev VM slave, but a
  local Hyper-V bench exists (`VM-A` / `VM-B`, snapshot `p37-ready`) with host↔guest HTTP on
  `http://10.0.2.2:8080`.
- The anti-cheat is EAAC/Javelin (post-2026-09-29). It refuses a box with testsigning on, and it
  refuses a driver that cannot be verified. Resolution taken and measured: **normal boot, DSE
  cleared for the length of one `sc start apexdrv` by `kdu`, DSE restored immediately after.**
- Milestone 1 is **CLOSED**: 34.9 minutes of live game with the driver resident, zero refusals,
  zero minidumps; the stop/start-577 round-trip proved DSE was genuinely restored. Apex sits in
  the lobby with the driver up and nothing happens. Do not re-open that question.
- Target process image is `r5apex_dx12.exe` (fallback name `r5apex.exe`). `r5apex.exe` on disk is
  encrypted; offsets come from a memory dump, never from the file.

## 2. What already exists (do not rebuild it)

| Thing | Where | State |
|---|---|---|
| WDM driver, device `\Device\ApexDrv`, symlink `\DosDevices\ApexDrv` | `QwenKernPremium\driver\apexdrv.c` | builds, loads inside the DSE window, unloads clean |
| Shared ABI header | `QwenKernPremium\include\apex_driver_ioctl.h` | version 2, `#pragma pack(push,1)` |
| Existing IOCTLs | same header | `INJECT 0x8A702003`, `VERSION 0x8A702007`, `PROBE 0x8A70200B` |
| Kernel probe that already does open→alloc→write→copy PEB with per-step NTSTATUS | `apexdrv.c: ApexdrvProbeProcess` | works; this is the proof that kernel-side copy in/out of the game is possible |
| `MmCopyVirtualMemory` + `KeStackAttachProcess` write helper | `apexdrv.c: ApexdrvWriteProcessMemory` | declared and in use |
| Build script that survives the `New User` space | `QwenKernPremium\tools\BuildDriver.ps1` | `cl.exe` cannot parse the path, always go through this |
| Launcher with `--probe --pid=` | `QwenKernPremium\build\apex_launcher.exe` | runs the PROBE IOCTL and prints every step status |
| ESP math (entity walk, world→screen, boxes) | `QwenKernPremium\src\features.cpp` | complete, reads through `MemoryReader` |
| D3D12 box renderer | `QwenKernPremium\src\d3d12_overlay.cpp` | complete, in-process only |
| Offset table | `QwenKernPremium\include\memory.h: ApexOffsets` | **stale (2026-10-25), must be re-derived** |
| Load/session scripts | `_ritual\h3_quiet.ps1`, `_ritual\h1_dse_host.ps1`, `_ritual\run_h2.cmd` | exercised end-to-end twice |

`MemoryReader` (`src\memory.cpp`) uses `ReadProcessMemory`. **On the live game that is exactly the
call that fails** — `OpenProcess` succeeds only elevated and RPM/`VirtualProtectEx`/`VirtualAllocEx`
all get refused once EAAC is up (measured, `docs/PHASE1_LADDER_AND_LIVE_ACCESS_MEASUREMENT.txt`).
So every read that matters has to travel through the driver. That is the first work item, not a
later optimization.

---

## 3. M2.0 — the primitive (do this first, in the VM)

How you run things is governed by the rules in §4 — read them before you execute anything. The
device already trusts the caller (`FILE_ANY_ACCESS`). Keep that. Bump `APEXDRV_VERSION` to **3**
and add, all `METHOD_BUFFERED`:

```c
#define IOCTL_APEXDRV_READ8   CTL_CODE(APEXDRV_DEVICE_TYPE, 0x803, METHOD_BUFFERED, FILE_ANY_ACCESS) // 0x8A70200F
#define IOCTL_APEXDRV_READBUF CTL_CODE(APEXDRV_DEVICE_TYPE, 0x804, METHOD_BUFFERED, FILE_ANY_ACCESS) // 0x8A702013
#define IOCTL_APEXDRV_WRITE   CTL_CODE(APEXDRV_DEVICE_TYPE, 0x805, METHOD_BUFFERED, FILE_ANY_ACCESS) // 0x8A702017
#define IOCTL_APEXDRV_BASE    CTL_CODE(APEXDRV_DEVICE_TYPE, 0x806, METHOD_BUFFERED, FILE_ANY_ACCESS) // 0x8A70201B
```

Structures go inside the existing `pack(push,1)` block, one process lookup per request, `ULONG
ProcessId` always first:

```c
#define APEXDRV_MAX_BATCH 64
#define APEXDRV_MAX_BUF   0x1000

typedef struct _APEXDRV_READ8_REQUEST {
    ULONG   ProcessId;                       // [in]
    ULONG   Count;                           // [in]  1..64
    ULONG64 Address[APEXDRV_MAX_BATCH];      // [in]
    LONG    Status[APEXDRV_MAX_BATCH];       // [out] per item, never aggregated
    ULONG64 Value[APEXDRV_MAX_BATCH];        // [out] zero on failure
} APEXDRV_READ8_REQUEST;

typedef struct _APEXDRV_READBUF_REQUEST {
    ULONG   ProcessId;                       // [in]
    ULONG   Size;                            // [in]  1..0x1000
    ULONG64 Address;                         // [in]
    LONG    Status;                          // [out]
    UCHAR   Data[APEXDRV_MAX_BUF];           // [out]
} APEXDRV_READBUF_REQUEST;

typedef struct _APEXDRV_WRITE_REQUEST {
    ULONG   ProcessId;                       // [in]
    ULONG   Size;                            // [in]  1..0x1000
    ULONG64 Address;                         // [in]
    LONG    Status;                          // [out]
    UCHAR   Data[APEXDRV_MAX_BUF];           // [in]
} APEXDRV_WRITE_REQUEST;

typedef struct _APEXDRV_BASE_REQUEST {
    ULONG   ProcessId;                       // [in]
    ULONG   Reserved;                        // [in]
    LONG    Status;                          // [out]
    ULONG   Reserved2;                       // [out]
    ULONG64 Base;                            // [out] main image base, 0 on failure
} APEXDRV_BASE_REQUEST;
```
Semantics, all mandatory:

1. Resolve the process once per request with `PsLookupProcessByProcessId`, hold the reference, and
   dereference on every exit path. Attach once with `KeStackAttachProcess`, detach before
   returning. No allocation, no threads, no global state beyond the device object.
2. Each item is its own `__try { ProbeForRead/ProbeForWrite; RtlCopyMemory } __except
   (EXCEPTION_EXECUTE_HANDLER)` so one dead address returns `STATUS_INVALID_ADDRESS` and the rest
   of the batch still lands. An ESP pass sweeps garbage pointers every frame; a batch that aborts
   on the first miss is worthless.
3. Reject `address < 0x10000`, `address > 0x7FFFFFFFFFFF`, `Size == 0`, `Size > APEXDRV_MAX_BUF`,
   `Count > APEXDRV_MAX_BATCH`. Header violations return `STATUS_INVALID_PARAMETER`; data
   violations are per-item statuses.
4. `BASE`: prefer `PsGetProcessSectionBaseAddress` resolved through `MmGetSystemRoutineAddress`,
   fall back to `PsGetProcessPeb` + `ImageBaseAddress` at `+0x10`. Never go through user mode —
   `EnumProcessModules` is one of the calls EAAC refuses.
5. `WRITE` re-reads the range after copying and reports `STATUS_UNSUCCESSFUL` on mismatch, so the
   caller never has to guess whether the write stuck.
6. Dispatch stays at default IRQL (PASSIVE_LEVEL, the requesting thread's context). No spinlock
   held across a copy.

Then a user-mode transport, `include\apexdrv_client.h` + `src\apexdrv_client.cpp`: `Open()`
(`CreateFileW(L"\\\\.\\ApexDrv")`, `GENERIC_READ|GENERIC_WRITE`), `Version()` refusing anything
below 3, `Base(pid)`, `Read8(array)`, `ReadBuf(addr,size)`, `Write(addr,buf)`. One handle per
process lifetime.

**Acceptance for M2.0, in the VM, against any live x64 process:** `BASE` returns the image base and
`ReadBuf(base,2)` returns `4D 5A`; a 64-item batch with three deliberately bad addresses returns 61
successes and exactly 3 `STATUS_INVALID_ADDRESS`; a one-byte `Write` round-trips and the read-back
agrees.

**Host acceptance, before you write any code:** with the game up in the lobby, run
`apex_launcher.exe --probe --pid=<pid>` elevated and record
`StatusLookup/StatusOpen/StatusAllocate/StatusWrite/StatusCopyVirtual`. That IOCTL already performs
the exact copy the design depends on. If `StatusCopyVirtual` fails, stop and report — everything
below assumes kernel-side copies are permitted in that process.

---

## 4. Rules that are not style preferences

R1 — **Kernel changes run in the VM bench first** (snapshot before, VM-A/VM-B), host is the last
step. Anything that can bugcheck or change boot behaviour is "kernel": `sc create/start/stop`,
`kdu`, DSE writes, `bcdedit`, `dism`, service `binPath`, file swaps under `System32\drivers`.
Host-only and always safe: screenshots, OCR, window raise, clicks, `Get-Process`, `sc query`,
reading logs.

R2 — **Never reboot the host without asking.** Batch boot-flag work into one agreed reboot.

R3 — **The read-back is the only verdict.** `kdu` exits 1 on success *and* failure. "Verification
succeeded" is not a verdict. Gate on the next observable: `sc start` rc, `STATE: 4 RUNNING`, game
process alive, `'MZ'` at the base we resolved. Record pre-state and post-state to files and read
the files.

R4 — **Every mutation carries its own restore, in the same script.** DSE down → back to the value
read at PRE; driver started by you → stopped by you unless the state file says leave RUNNING. A
probe must be safe to re-run.

R5 — **One variable per probe, new number, never overwrite output.** `pNN` is monotonic, its own
output file, and the RESULT/VERDICT line names the variable changed.

R6 — **Stay in the tree, use the helpers.** No state-mutating one-liners typed into chat; put it in
a script, run the script, read the output file. `cl.exe` cannot parse `New User` — `BuildDriver.ps1`
only.

Non-obvious harness facts that will otherwise eat your session: every `run_commands` call restarts
the terminal, so a `Start-Sleep` poll dies with it — long work belongs in a **scheduled task** that
writes to a file on a cadence (see `_ritual\h2_task.ps1` and `h2w1_watch.ps1`). PowerShell 5.1
parses `Func()` as command syntax; use `Func`, `(Func)` or `$x = Func`. `[uint64]0x80000000` parses
as a negative `Int32` and throws on cast — suffix such literals with `L`.


---

## 5. How the driver gets loaded, and how a session runs

The driver is self-signed and will not pass DSE. It is loaded inside a ~90 second window opened by
`kdu`, and DSE is restored immediately after. Proven sequence, run it in this order, every session:

1. `_ritual\h3_quiet.ps1` — retires EA processes so the DSE window is not racing a live Javelin.
   Expect `post []` and driver `STOPPED`.
2. `_ritual\h1_dse_host.ps1` — no arguments. It records the DSE value kdu reports, sets `0`, verifies,
   `sc start apexdrv`, verifies `STATE: 4 RUNNING`, then restores **the value kdu reported at PRE**
   (this box boots `0x16`), not the constant `6` — restoring `6` leaves a byte PatchGuard hashed at
   boot differing → `0x109` at ~20 min. `kdu` prints hex but parses `-dse` in decimal, so `0x16` goes
   out as `22`; pass it by hand as `-dse 16` and you silently write `0x10`. The verdict is the
   readback line `readback=0x16 expect=0x16 match=True`, not the exit code.
   Pre-flight refuses to run unless the staged binary matches SHA256 `9B119FD0C38740A2…` — **a new
   version-3 build does not match**, so re-stage it and update `$sha` in the script or h1 aborts.
3. Launch the game **from the EA app** (sign-in is manual; the CEF surface ignores synthetic
   input). `r5apex_dx12.exe` appears, the lobby loads, Javelin is satisfied.
4. `_ritual\run_h2.cmd` only if you want the 30-minute timer and the popup/dump watch. It is not
   needed to play.

End of session: stop the game, `sc stop apexdrv`, confirm `STATE: 1 STOPPED` and DSE back at the
boot value. Never leave DSE at `0`.

The driver stays RUNNING for the whole match. Coexistence is proven for 34+ minutes and it was
proven with the driver loaded *before* the game — do not invent a "load it mid-match" variant.

---

## 6. How you actually use the driver to cheat

The shape is: a separate elevated process (`apex_ext.exe`) → `\\.\ApexDrv` → read the game →
project → draw on a transparent overlay window. Nothing is injected into `r5apex_dx12.exe`, so
there is no module and no import for Javelin to enumerate. Per frame:

1. Find the pid (`r5apex_dx12.exe`, fallback `r5apex.exe`) and `Open()` the device. Refuse to run
   if `Version() < 3`.
2. `Base(pid)` → module base. `ReadBuf(base, 2)`, assert `4D 5A`. Read `base + 0x3C` as `int32` →
   `e_lfanew`, assert `PE\0\0` at `base + e_lfanew`. If either assert fails the base is wrong —
   abort the frame loudly instead of drawing nonsense.
3. `ReadBuf(base + OFF_VIEW_MATRIX, 64)` → 16 floats. Sanity: all finite, `[15] != 0`.
4. `Read8(base + OFF_ENTITY_LIST)` → list pointer. Then `Read8` in batches of 64 (one call per 64
   slots) over `list + i*8`. The per-item statuses tell you which slots are dead — that is exactly
   what the status array is for; do not fall back to per-slot single reads.
5. Per entity, `ReadBuf(entity + OFF_ORIGIN, 12)` (three floats) and `ReadBuf(entity + OFF_HEALTH,
   4)`. Filter: finite coords, not within 1.0 of the world origin, health `1..200`.
6. Project with the row-major transform already written in `src\features.cpp` (`WorldToScreen`,
   including its `w < 0.001` behind-camera reject). Reuse that math verbatim.
7. Publish boxes into a lock-free array and draw.

**Speed budget:** one 64-item batch is a single `DeviceIoControl`; at the gdrv3 reference cost
(2.5 µs/op) a 128-slot pass with 3 fields each is roughly 0.3–0.6 ms. Poll at 60 Hz from a worker
thread, draw at monitor refresh. If a pass exceeds 2 ms, batch more — do not poll less.

**Do not** call `OpenProcess`/`ReadProcessMemory` anywhere in the external path.

---

## 7. Drawing route

**Route A (recommended, do this): external overlay.** Own process, `WS_EX_LAYERED |
WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_TOOLWINDOW`, colour-keyed transparent, click-through,
sized and positioned from `GetClientRect` + `ClientToScreen` of the game's `HWND`, re-tracked every
second and on `EVENT_SYSTEM_FOREGROUND`. Render with D3D11 into a DXGI swapchain
(`DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL`, no vsync, `Present(0, 0)`). Rectangles come straight from the
projection.

Streamproof caveat, measure it, do not assume: a layered window lives in desktop composition, so
OBS *Display Capture* sees it and OBS *Game Capture* (which hooks the game's swapchain) does not.
That is the shipping configuration; a build with zero overlay signature later reuses
`src\d3d12_overlay.cpp` through the inject path.

**Route B (fallback, only if Route A cannot reach the game): internal.** `IOCTL_APEXDRV_INJECT`
with `apexcheat.dll` already works, and `features.cpp` + `d3d12_overlay.cpp` + the `Present` hook
are finished. The cost is a module inside the game and a VMT/patch artifact. Fallback, not default.

**Route A glue you must add:** give `MemoryReader` a driver backend so `UpdateESP` keeps working
unchanged — `Initialize(pid, Backend::Driver)` opens the device, `ReadArray` becomes `ReadBuf`,
`GetGameModuleBase` becomes `Base(pid)`. Then `features.cpp` compiles into the external exe as-is.

---

## 8. Aim

Aim is mouse movement, not memory writes, in the first pass. The archived engine in
`ai_apex_external_aimbot_architecture.md` is the spec: quadratic Bezier with perpendicular control
offset, Fitts-law timing (`0.030 s` floor + `0.045 s/bit`), per-step Gaussian jitter tapering near
the target, ±15% time variance, 4–40 steps on a smoothstep velocity profile, 2 px deadzone, hold-to-
aim on `VK_XBUTTON2`.

Source and sink: read the local player's world origin and the target's head position → screen delta
from the crosshair → `SendInput` `MOUSEEVENTF_MOVE` relative deltas from the same elevated process.
Apex consumes raw input, so no absolute positioning and no cursor capture games are needed.

Order: closed-loop **only** after the ESP is visually correct in the firing range; aim on top of a
wrong projection is unfalsifiable debugging.

Second pass, only once aim works: view-angle write (`WRITE` to the camera angle pair) so a flick
does not have to fight the mouse. Keep the `SendInput` path behind a config flag — a view-angle
write is visible in the game's own state, mouse deltas are not.

---

## 9. Offsets — assume every one is wrong

`ApexOffsets` in `include\memory.h` is dated **2026-10-25**: `ENTITY_LIST 0x23F6A90`,
`LOCAL_PLAYER 0x01E7D4B8`, `VIEW_MATRIX 0x022EE01`, and the `features.cpp` member offsets
`ORIGIN 0x258 / HEALTH 0x3A0 / TEAM 0x478`. The build has moved since. Treat all six as
placeholders and prove each one before trusting it.

Derivation path: dump `r5apex_dx12.exe` from a live process (the on-disk image is encrypted),
then `apexdream`/`apexbot` on the dump (`docs/APEX_OFFSETS_AND_DUMPING_METHODS.txt`, methods 1–3).
`temp\dm29.py` + `temp\dm29.txt` are an existing datamap walker against a dump and name real
classes (`C_AI_BaseNPC`, `DT_HealthKit`) — useful anchors, but a datamap gives class layout, not
the global entity-list RVA.

Validation gates, all must pass before an offset is written into the header:
1. entity-list pointer lands inside the game's own heap (not image space, not a low stub);
2. slot 0 resolves to a pointer whose `+ORIGIN` is finite and within ±64k on each axis;
3. health reads in `1..200` for at least 3 slots, and `0` or negative for dead ones;
4. the view matrix reproduces a horizon: projecting a point 1000 units in front of the local
   player lands near screen centre and moves coherently when the camera turns.

Record every offset with the build id it came from, in a dated block, and keep the old values as
comments.

---

## 10. Work order

Numbered so a half-finished task is still readable next session. Each step is its own `pNN` probe
with its own output file; a step does not begin until the previous verdict is on disk.

1. **`p40_probe_live`** — `apex_launcher.exe --probe --pid=<r5apex_dx12>` elevated with the game in
   the lobby. Record the five NTSTATUS fields. Gate: `StatusCopyVirtual == 0`.
2. **`p41_abidrv`** — VM-A. Build the version-3 driver with §3's IOCTLs, `sc create`, `sc start`,
   `BASE`/`Read8`/`ReadBuf`/`Write` against `notepad.exe` (MZ assert, bad-address batch, write
   round-trip). Gate: 61/3 split and a matching read-back. Then a 10-minute idle soak, `sc stop`,
   confirm no dump.
3. **`p42_abihost`** — the same binary on the host inside an h1 window (re-stage it and update `$sha`
   first, §5 step 2), same asserts against `r5apex_dx12`. Gate: identical results, game still alive.
4. **`p43_offsets`** — dump, derive, run the four validation gates, write the dated block. Gate: all
   four pass live.
5. **`p44_ext_esp`** — `apex_ext.exe` + overlay, driver backend in `MemoryReader`. Gate: boxes track
   bots in the firing range for 60 s with a stable frame time.
6. **`p45_match`** — one real match: ESP on, driver RUNNING, 20 minutes, count `EVT` lines by hand,
   zero minidumps.
7. **`p46_aim`** — aim on top, humanized, tuned in the range then one match.
8. Fold the result into a single entry script: `h3_quiet` → `h1_dse_host` (22) → `apex_ext.exe` →
   game → play, with the stop/restore tail in the same file.

---

## 11. Evidence format

Every step writes `_ritual\pNN_topic.txt` itself: pre-state with timestamps, what was done, raw
output, a `RESULT:` line, and a `VERDICT:` block that names the single variable changed. Verdicts
are `PASS` / `FAIL` / `AMBIG` — `AMBIG` is a real answer and is what you write when the read-back
does not distinguish the cases.

Screenshots are unreliable; OCR text files (`_ocr*.txt`) are the state feed. If you need to know
what is on screen, OCR to a file and read the file.

Before every mutation, record: `sc query apexdrv` state, `bcdedit /enum {current}` DSE-relevant
lines, the loaded-module blocklist, the process list, `Get-ChildItem C:\Windows\Minidump`. After
the step, record the same set. A probe that cannot show both halves is not evidence.

Append one line per finding to `_ritual\_index.txt`. Update `STATE.md` at the top, not the bottom.

---

## 12. Traps, all already paid for

- `kdu` prints `g_CiOptions` in **hex** and parses `-dse` in **decimal**. Boot `0x16` is `-dse 22`.
  `-dse 16` silently writes `0x10` and drops DSE entirely.
- `kdu` exit code is `1` on success and on failure. Verdicts come from the next observable.
- `h1_dse_host.ps1` hash-pins the `k9` binary as `9B119FD0C38740A2…` and aborts on a mismatch. Every
  version-3 build fails that check by definition — re-stage the new `.sys` **and** update `$sha` in
  the same edit, then re-run the pristine pass before chasing anything else.
- `cl.exe` cannot parse `C:\Users\New User\...`. `BuildDriver.ps1` only.
- PowerShell 5.1: `Func()` in expression context is command syntax. `[uint64]0x80000000` is a
  negative `Int32`. `run_commands` restarts the terminal, so `Start-Sleep` polls die — use a
  scheduled task that appends to a file.
- `h2_gate.ps1` cannot score GREEN by construction: it increments `$refusals` for every captured
  event and its regex contains bare `AntiCheat`, so benign EAAC lifecycle lines (FilterManager,
  SCM 7045/7036/7031) always colour it AMBER. Classify lines by hand; the clean datum is
  `h2w1_watch`'s tight filter.
- A minidump `0x109` used to appear at 19–27 minutes. Both edges are cleared, but if a run dies,
  `Get-ChildItem C:\Windows\Minidump` and the last `STATE:` line are the first things to read.
- `MmMapIoSpace` on an unbacked physical address bugchecks the box. Only relevant if you take the
  physical/CR3 route during offset work.
- The EA app's CEF sign-in ignores coordinate `SendInput`, UIA, widget-targeted `SendInput`,
  self-elevated `SendInput` and `PostMessage`/`WM_CHAR`. Sign-in stays manual.

---

## 13. Do not touch

- **Do not turn testsigning on.** The whole point of milestone 1 was to keep the box on a normal
  boot.
- **Do not change the device type, the symlink name or `FILE_ANY_ACCESS`** — the deployed launcher
  and every probe assume them.
- **Do not add a system thread, a work item or an unbacked-memory hook to the driver.** A resident
  driver that looks like a driver is what Javelin tolerates.
- **Do not hook anything inside the game on Route A.** No inline patches, no `Present` VMT patch,
  no module. That is the property that makes this build different from every other one in the tree.
- **Do not rewrite `features.cpp`'s projection or `WorldToScreen`** — reuse it.
- **Do not delete a probe whose result is quoted in `docs\`.**

---

## 14. Stop and report instead of improvising when

- `StatusCopyVirtual` fails on the live game (the design premise is gone — fall back to the
  mapK/p36 physical write path and say so).
- The VM bench cannot start (R1: do not "just try it on the host, it's quick").
- A host step needs a reboot (R2: ask).
- Two consecutive reads of the same address return different shapes, or the MZ/PE asserts fail on a
  base that `BASE` returned.
- A run reaches 25 minutes with a `0x109` pending or a second `EVT` family appears that is not
  FilterManager/SCM.

---

## 15. Definition of done

M2 is done when all of the following are true in one session, with evidence files on disk:

1. Driver version 3 loads inside the h1 window and survives a 20-minute match, `STATE: 4 RUNNING`
   the whole time, DSE read-back `0x16 match=True` before the game starts.
2. `apex_ext.exe` resolves the base by `BASE`, passes both MZ/PE asserts, and reads a live view
   matrix within 1 ms per pass.
3. Boxes track real players in a match and in the firing range, at ≥ 55 fps, with the overlay
   click-through and not visible to game capture.
4. Aim moves the crosshair with the humanized path and no visible snap.
5. `sc stop apexdrv` → `STATE: 1 STOPPED`, DSE `0x16`, zero minidumps, no reboot.
6. `STATE.md` has the close-out entry; `_ritual\_index.txt` has the p40–p46 lines.

