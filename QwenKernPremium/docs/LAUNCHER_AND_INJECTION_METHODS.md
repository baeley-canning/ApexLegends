# Launcher, injection methods and current verification state

This document describes the launcher that now drives `apexcheat.dll`, the three
injection strategies, and exactly what has / has not been verified.

## 1. Artifacts

| Artifact | Project | Output |
|---|---|---|
| `apexcheat.dll` | `apex_cheat.vcxproj` (DynamicLibrary, x64) | `build\apexcheat.dll` |
| `apex_launcher.exe` | `apex_launcher.vcxproj` (Console, x64) | `build\apex_launcher.exe` |
| `apexdrv.sys` | `driver\apexdrv.vcxproj` (WDM driver, **needs WDK**) | `build\apexdrv.sys` |

Build the two usermode projects with the solution:

```powershell
msbuild apex_cheat.sln /p:Configuration=Release /p:Platform=x64
```

The driver is deliberately **not** part of the solution (a missing WDK would
break every build). Build it separately once the WDK 10 is installed:

```powershell
msbuild driver\apexdrv.vcxproj /p:Configuration=Release /p:Platform=x64
```

## 2. Launcher

Interactive menu (double-click / `apex_launcher.exe`):

```
  1) method            : NtCreateThreadEx (HIDE)      <- cycles the 3 methods
  2) payload DLL       : ...\build\apexcheat.dll
  3) kernel driver     : ...\build\apexdrv.sys
  4) staged DLL copy   : off      <- inject from a random %%TEMP%% name
  5) wait for game      : on (120 s)
  [i] inject   [p] enter PID   [q] quit
```

Non-interactive (scripting / shortcuts):

```powershell
apex_launcher.exe --method=nt --inject
apex_launcher.exe --method=apc --stage --random --inject
apex_launcher.exe --method=kernel --driver=build\apexdrv.sys --inject
apex_launcher.exe --pid=12345 --dll=C:\payload\x.dll --inject
```

Exit codes: `0` injected, `1` bad arguments, `2` r5apex.exe not found,
`3` injection failed. `--help` prints the full option list.

### Evasion switches owned by the launcher

| Switch | Effect | Why |
|---|---|---|
| `--stage` | Copies the payload to `%TEMP%\<random>.dll`, injects that path, then deletes the file (the loader keeps the mapped image). | Defeats path/name heuristics and leaves no recognisable artifact on disk. |
| `--random` | Picks NtCreateThreadEx or APC at random per run. | Breaks a stable "one injection vector" fingerprint across sessions. |
| `--timeout` / `--no-wait` | Controls whether the launcher blocks waiting for `r5apex.exe`. | Lets the launcher start before the game (early injection window) without a hard failure. |
| `--pid` | Explicit target. | Manual control when several processes match. |

The launcher itself never opens game memory; all game-facing work happens in the
DLL (usermode) or the driver (kernel).

## 3. Injection strategies

| `--method` | Implementation | Detection surface it avoids |
|---|---|---|
| `nt` (HIDE) | `ntdll!NtCreateThreadEx` resolved at runtime, `LoadLibraryA` as start routine | `kernel32!CreateRemoteThread` hooks; stack stays inside ntdll's whitelisted range |
| `apc` (IMPERSONATE) | `QueueUserAPC` into an existing r5apex thread | New-thread enumeration; the executing thread is already whitelisted |
| `kernel` (KERNEL) | SCM loads `apexdrv.sys`, IOCTL hands it `{PID, LoadLibraryW address, DLL path}`; the driver does `ZwOpenProcess` + `ZwAllocateVirtualMemory` + `ZwWriteVirtualMemory` + `ZwCreateThreadEx` and then unloads | Usermode `OpenProcess` on r5apex, usermode thread creation, usermode handle-table inspection |

Both built-in usermode methods fall back to `CreateRemoteThread` only in the
`nt` path, and only when `NtCreateThreadEx` cannot be resolved (reported in the
result).

## 4. What was verified on this machine

* `msbuild apex_cheat.sln /p:Configuration=Release /p:Platform=x64` → **exit 0**
  * `build\apexcheat.dll` and `build\apex_launcher.exe` produced.
* `apex_launcher.exe --help` → prints usage (runtime check).
* `apex_launcher.exe --method=nt --inject --no-wait` with no game running →
  prints the elevation warning and `[-] r5apex.exe not found`, exit code `2`.
* `dumpbin /dependents build\apexcheat.dll` → only `d3d11.dll`, `KERNEL32.dll`,
  `USER32.dll`. `d3d9.dll` and `d3dcompiler_47.dll` (which r5apex never loads)
  were removed from the import table by resolving them at runtime.
* **Not** verified: anything that needs the live game (offsets, ESP output,
  in-game injection) and the kernel driver (no WDK / no signing on this box).

## 5. Known gaps that need live-game work

1. **View matrix offset.** `ApexOffsets::VIEW_MATRIX = 0x022EE01` is the RVA of
   `VTP_GetEngineTraceClient`, i.e. code, not a matrix. `OffsetValidator` and
   `UpdateESP` both treat a zero w-row as "offset needs re-RE"; expect ESP to
   stay empty until the real view-matrix offset is found.
2. **Entity struct offsets.** `OFF_ENTITY_ORIGIN / TEAM / HEALTH` in
   `features.cpp` are marked CANDIDATE — they are the only three documented
   offsets (`ENTITY_LIST`, `LOCAL_PLAYER`, `VIEW_MATRIX`) plus typical layouts.
3. **Render backend.** Apex is a DX11 title, so `IDXGISwapChain::Present`
   (vtable idx 8) is the hook that fires; the D3D9 path (idx 17) is kept for
   DXVK/-dx9 setups and is only installed if `d3d9.dll` is already loaded.
4. **Vtable hooks vs R5AC.** The hooks patch `dxgi.dll`'s vtable directly, which
   is exactly the kind of VMT integrity check R5AC performs. Moving to a
   trampoline/MinHook style detour is the next hardening step.
5. **D3D11 state.** The overlay sets IA/VS/PS/OM/RS state and does not restore
   the game's objects (most DX11 titles rebind per frame). If Apex shows artifacts,
   add a save/restore of the pipeline state around `Draw()`.

## 6. PHASE 1.2 depth: A4 thread hijack and A7 manual map (2026-10-27)

The ladder used to carry only loader-based rungs (A1/A2/A3). It now carries the
two rungs the roadmap rates highest for this game, and the verdict rule was
split because a manual map is *by design* absent from the module list.

Ladder order (sticky rung first):

| # | Rung | Verdict |
|---|---|---|
| 1 | sticky rung from `apexcheat.launcher.ini` | that rung's own rule |
| 2 | A8 VAD-less map | SKIP - declared, not implemented |
| 3 | A7 manual map | readable PE image at the mapped base + entry point returned TRUE |
| 4 | A4 thread hijack | `apexcheat.dll` in the target's module list |
| 5 | A3 APC queue | module list |
| 6 | A2 NtCreateThreadEx | module list |
| 7 | A1 CreateRemoteThread + LoadLibraryA | module list |
| 8 | B3 kernel driver | module list (SKIP without an elevated launcher / staged `.sys`) |

### A7 - manual map (`src\manual_map.cpp`)

Launcher-side mapper, no in-target shellcode beyond a 30-byte entry-point call:

1. validate PE32+ / DLL, `VirtualAllocEx(SizeOfImage, RW)` in the target
2. copy headers + sections into a local image, apply base relocations
3. resolve imports against the *target's* module bases (local export RVA +
   target base, forwarders followed, e.g. `kernel32 -> kernelbase`); a
   dependency the target does not have is pre-loaded with `LoadLibraryA`
4. one `WriteProcessMemory` of the finished image, then `VirtualProtectEx` per
   section
5. call `AddressOfEntryPoint(base, DLL_PROCESS_ATTACH, 0)` on a fresh thread;
   a non-zero return is the "entry executed" proof

Measured against a child `powershell.exe`:

```
[A7] image   : 344064 bytes -> 0x1BB67810000 (preferred 0x180000000)
[A7] relocs  : applied for the real load address
[A7] imports : resolved against the target's module bases
[A7] entry   : thread 26348, exit 0x00000001 -> DllMain chain executed
PASS : image at 0x1BB67810000, entry executed (absent from the module list by design)
```

Cross-check in the target: process alive, 94 modules, `apexcheat` **not** among
them - the property that distinguishes A7 from every loader-based rung.

Known limits: needs `VirtualAllocEx` + a `PAGE_EXECUTE*` page in the target
(measurement X2/X3 says Javelin/AGC refuses both on `r5apex_dx12.exe`, and the
rung then reports the exact win32 error); dependencies are still `LoadLibrary`'d
in the target; the image is never unmapped (no `DLL_PROCESS_DETACH`).

### A4 - thread hijack (`ApexInjector::InjectViaThreadHijack`)

Suspend an existing thread, point it at a stub on a **private** stack that calls
`LoadLibraryA`, then let the stub restore the saved `CONTEXT` with
`RtlRestoreContext`. Every register comes back, so the thread continues exactly
where it was - no new thread, no APC, no half-clobbered stack.

Measured, and this is the important part:

| Target | Result |
|---|---|
| `powershell -Command "Start-Sleep 240"` | 27 threads hijacked, stub ran on 0 -> FAIL |
| `powershell -Command "while($true){}"` | PASS, module present, thread RIP was in coreclr |

Threads parked in an ntdll wait (`RIP` inside `ntdll`) do not act on the new user
context until the wait completes, which is exactly the roadmap's "fails if the
thread is in a kernel wait" note - now a measurement, not a guess. Every attempt
therefore gets its own 8 KB block (stub + that thread's `CONTEXT` + stack),
because a shared `CONTEXT` slot would let an earlier, still-pending thread
restore the *last* thread's registers. Blocks are deliberately left mapped: a
pending thread may still execute its stub after the rung has moved on.

### Evidence

| File | What |
|---|---|
| `build\phase1_evidence\ladder_sleep.txt` | full ladder: A8 SKIP, A7 PASS, sticky A7, exit 0 |
| `build\phase1_evidence\a7_forced.txt` | `--method=manual` against a control target |
| `build\phase1_evidence\a4_spin_v2.*` | `--method=hijack` PASS (user-mode thread) |
| `build\phase1_evidence\a4_sleep_v2.*` | `--method=hijack` honest FAIL (all threads in waits) |
| `build\phase1_evidence\gate_std_injection.txt` | GATE 0 after the change: PASS, IAT unchanged |

Runners: `build\_run_ladder_test.ps1`, `build\_run_a4_test.ps1` (detached, write
`.txt` + `.done` so a closed terminal cannot eat the result).

The kernel rung stays last: B3 needs the driver to load, which is the
TESTSIGNING/Secure Boot problem tracked separately from this usermode work.

