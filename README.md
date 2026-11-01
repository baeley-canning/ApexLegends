# ApexLegends — QwenKern Premium

Private research + product build for an Apex Legends external / driver-assisted cheat, aimed at the
post-Javelin (2026-09-29) anti-cheat stack. Two halves: **`QwenKernPremium/`** (C++ launcher, overlay,
injectors and the kernel driver `apexdrv`) and **`_ritual/`** (the PowerShell probe harness that was
used to measure the live anti-cheat on this machine, plus its raw output).

> Everything here is date-stamped. Start with `QwenKernPremium/docs/KB_INDEX_2026.txt` — it is the map.

## Status — 2026-11-01 21:22, this machine

| Area | State |
|------|-------|
| Usermode read layer | `OpenProcess` with full injector rights works **only elevated**; RPM, module enumeration (psapi/toolhelp/tasklist), `VirtualAllocEx`, `VirtualProtectEx`, `Nt*` all fail from outside the live game (docs/PHASE1_LADDER_AND_LIVE_ACCESS_MEASUREMENT.txt) |
| Driver `apexdrv` | builds, loads and stays `STATE 4 RUNNING` **only when the machine has booted in test mode** |
| The gate | EAAC/Javelin refuses the game whenever the box is in test mode: Windows Application-Popup **id 26** — `Security Violation : Device Driver signing integrity checks must be enabled to start the game.` |
| Game + driver coexistence | **NOT PROVEN** — p33 shows the *popup* follows the flag source, but the game still exits in every combination tested so far |
| Next decisive test | `_ritual\run34.cmd` — driver-stopped vs driver-loaded matrix, 1 s sampling (`_ritual\p34_matrix.ps1`) |

### What is proven (reproducible from `_ritual/`)

1. `testsigning off` + no `apexdrv` → game runs clean, 300 s, 0 CI events (p31b, 20:58).
2. `testsigning on` → `apexdrv.sys` (self-signed, no Microsoft-root chain) **loads and stays RUNNING**;
   the earlier `577` "cannot verify the digital signature" failure is purely load-time DSE and does
   not exist in boot test mode (p33, 21:15:10–12).
3. The refusal popup is driven by the **flag source**, not by live kernel CI state: clearing BCD
   `testsigning` live (T2) and additionally scrubbing
   `HKLM\SYSTEM\CurrentControlSet\Control\SystemStartOptions` (T3) both silence it (p33, 21:16–21:18).
4. Stopping `apexdrv` changes *which* refusal Javelin prints — it does not by itself make the game
   survive (p29 RUN1 vs RUN2).

### What is NOT proven

- That the game survives while the driver is loaded. The p33 `VERDICT` line over-claims; its `died`
  flag only trips if a 5 s poll *saw* the game up, so a fast exit reads as `died=False`. See
  `QwenKernPremium/docs/JAVELIN_TESTSIGNING_GATE_2026-11-01.md`.
- Whether Javelin reads a boot flag or the live CI state. "No popup" under T2/T3 is compatible with both.

## Layout

| Path | What |
|---|---|
| `QwenKernPremium/` | the product: `driver/apexdrv.c` (kernel), `launcher/launcher_main.cpp`, `src/` (overlay, injectors, ACG probe), `include/`, `docs/`, `tools/`, `build/` |
| `QwenKernPremium/docs/` | research + findings KB — read `KB_INDEX_2026.txt` first |
| `_ritual/` | probes, captures and raw evidence — see `_ritual/README.md` |
| `QwenKern/` | earlier research tree (driver projects, KB, external RE lists) |
| `Qwen Knowledge base/`, `Qwen General Knowledge/` | loose notes |
| `generated_cheats/`, `deepseekharness/`, `Sentinel/`, `ext/`, `temp/` | Python prototypes, harnesses, scratch |

## Build

Driver — deliberately does **not** need the WDK MSBuild toolset registered (see script header):

```
powershell -ExecutionPolicy Bypass -File QwenKernPremium\tools\BuildDriver.ps1
```

Overlay DLL + launcher (MSVC v143, Release x64):

```
msbuild QwenKernPremium\apex_cheat.sln /t:Rebuild /p:Configuration=Release /p:Platform=x64
```

Gate / "does our code even get in" harness: `powershell -File QwenKernPremium\tools\BuildGate.ps1`.

## Run

```
build\apex_launcher.exe --help
build\apex_launcher.exe --probe                                        # access-layer matrix
build\apex_launcher.exe --inject --method=nt --pid=<pid>               # one-shot staged inject
build\apex_launcher.exe --method=kernel --driver=build\apexdrv.sys --inject
```

Flags: `--method=nt|apc|kernel`, `--dll=`, `--driver=`, `--pid=`, `--stage`, `--random`,
`--timeout=`, `--no-wait`, `--inject`. The DLL is resolved next to the exe unless `--dll=` is given.

## The gate, in one paragraph

`testsigning on` → the driver loads, Javelin refuses the game. `testsigning off` → the game runs, the
driver is refused at load (`577`). Flipping the flags *after* boot is not sufficient on its own. Full
matrix, mechanism and decision tree: **`QwenKernPremium/docs/JAVELIN_TESTSIGNING_GATE_2026-11-01.md`**.

## Conventions

- Doc files are dated, graded `[A]` official / `[B]` community-code / `[C]` copy, and tagged
  `[VERIFIED-<date> by <test>]` once we have measured it ourselves.
- Nothing counts as known until a script under `_ritual/` reproduces it.
- Windows PowerShell 5.1 trap: `Func()` on a zero-arg function parses as command syntax — write
  `Func`, `(Func)` or `$x = Func`.
- `cl.exe` mis-parses paths containing spaces (`New User`) — use `BuildDriver.ps1` or short paths.
- Do not ship a static import of a module the game itself does not load (checked with `dumpbin /dependents`).

## Evidence harness (`_ritual/`)

Every claim in this repo comes from a numbered probe (`pNN_*.ps1`) driven by a wrapper (`runNN.cmd`),
writing an output file `_ritual\pNN_*.txt`. `_ritual/README.md` is the map, `_ritual/_index.txt` is the
running log of findings. The probes self-elevate (one UAC prompt) and are safe to re-run.

Probes that matter for the current blocker:

| Probe | Question it answers |
|---|---|
| `run27.cmd` / `p27_gate.ps1` | does a vanilla box (no driver, no flags) still run the game? |
| `p29_gate2.ps1` | is the refusal caused by the flag, or by our driver? |
| `p31*.ps1` | post-reboot verification; POPUP-GATE root cause confirmed |
| `run33.cmd` / `p33_flagflip.ps1` | flag-flip matrix T1/T2/T3 — the popup follows the flag *source* |
| `run34.cmd` / `p34_matrix.ps1` | driver-stopped vs driver-loaded with the flag off, 1 s poll |

Run one with `_ritual\runNN.cmd`.

## Open work

1. Run `run34.cmd`, then branch on the decision tree in the gate doc.
2. If "driver presence is fatal while the flag is off": re-shape the driver — load it *after* the game
   starts, keep comm off the IOCTL dispatch table, rotate the service name, no system thread in
   unbacked memory, no `MajorFunction` table overwrite from unbacked memory.
3. If "live CI state is fatal": get a real signature chain (EV → attestation signing, no HLK needed) or
   manual-map `apexdrv` with a device Javelin tolerates (BYOVD; today `gdrv3` is read-only).
4. Only then wire the B3 kernel inject into a live game (`--method=kernel`) and port the read ladder to
   the CR3-abuse-proof physical path (see `docs/INJECTION_MENU_AND_RISK_MATRIX.txt`, B6-ii).
5. A perfectly valid product fallback: ship external-only (driver loaded only when the user is not in a
   match) until 2 or 3 is solved.

## Changelog of this README

- 2026-11-01: first real README (repo previously had a one-line stub). Records the gate, what is proven
  vs not proven, and points at the findings doc instead of repeating it.


