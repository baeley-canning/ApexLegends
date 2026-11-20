# STATE.md — cheatv2 / external overlay for r5apex_dx12.exe

## HARD RULE — VM for anything that can crash
- **ALL** physical memory work (Steps 02-06) MUST run in the VM first. Host = last step.
- **ALL** elevated runs (any `runas`, `ShellExecuteW("runas")`, admin prompt) MUST run in the VM first.
- **ALL** driver load/unload, device open, IOCTL calls, page mappings — VM first.
- If the VM cannot start, say so and stop. Do NOT "just try it on the host."
- If you are unsure whether something can crash the host, **assume it can** and use the VM.
- **CRASH LOG**: Every elevated run on the host writes a crash log to `cheatv2/CRASH_<YYYYMMDD_HHMMSS>.log` with: the command run, exit code, stdout/stderr, and a timestamp. This lets us see what killed the host.

## Phase Map
- Phase 1 (steps 01-03): primitive proven — game closed
- Phase 2 (steps 04-06): kernel access — game closed
- Phase 3 (steps 07-10): game data — game running
- Phase 4 (steps 11-13): ESP — game running
- Phase 5 (steps 14-15): aimbot + polish — game running

## Current Step
Phase 1 code written and built. Ready for Step 02 elevated run in VM.

## Build Status
- Step 01: Built and ran successfully with MSVC Build Tools 14.44.35207.
- Build: `cl.exe /O2 /std:c++20 /EHsc /W4 /WX /I<msvc-include> /I<ucrt-include> /I<shared-include> /I<um-include> /c src/*.cpp` then `link.exe /OUT:build/cheatv2.exe *.obj kernel32.lib ntdll.lib advapi32.lib /LIBPATH:<lib-dirs>`
- Output: cheatv2.exe (155 KB), x64 Release

## Build Command (run on MSVC host)
  cmake -B build -DCMAKE_BUILD_TYPE=Release
  cmake --build build --config Release
  Or manually:
  cl.exe /O2 /EHsc /DWIN32 /DNDEBUG /std:c++20 /I include /Fe:build\cheatv2.exe src\drv.cpp src\main.cpp /link kernel32.lib

## Known Offsets (from QwenKernPremium / ext/ audit)
All offsets below are [UNVERIFIED] for the current game build unless noted.
See VERIFY.md for full table with sources.

### EPROCESS structure (Windows 26200)
- ImageFileName offset: 0x338
- UniqueProcessId offset: 0x1D0
- ActiveProcessLinks flink: 0x258
- DirectoryTableBase/CR3 offset: 0x28
- Token offset: 0x248
- PEB offset: 0x2E0
- PriorityClass offset: 0x347

### Game-specific (from apex_offsets_generated.h)
- See VERIFY.md for complete list

## Device Info
- Device path: \\.\GIOV3 (also referenced as \\.\GIO)
- Driver: gdrv3.sys (Gigabyte)
- Required: UAC elevation (DACL: D:P(A;;GA;;;SY)(A;;GA;;;BA))

## Build Command
TODO: determine exact MSVC command after project file is created.
Expected: `cl.exe /O2 /EHsc /DWIN32 /DNDEBUG /DUNICODE /D_UNICODE /I... /Fe:cheatv2.exe src/*.cpp`

## Next Action
Step 02: Physical read smoke test — read known physical address, match against expected pattern.

## Last Known-Good Offsets
None yet — all offsets marked [UNVERIFIED] in VERIFY.md.

## Changes This Session
- Phase 0 RECON complete: audited QwenKernPremium/ and ext/ read-only.
- Created cheatv2/ directory with PLAN.md, STATE.md, VERIFY.md, DECISIONS.md.
- Step 01 source files created: CMakeLists.txt, src/drv.h, src/drv.cpp, src/main.cpp.
- Built with MSVC Build Tools 14.44.35207 (no cmake installed).
- Step 01: Device opened (\\.\GIOV3), 516 IOCTLs probed — 2 YES (0xC3502008 UNMAP, 0xC3502400 DECOY), 514 NO.
- Probe table written to VERIFY.md.

## Build Notes
- This host (DESKTOP-PPHFJBQ) has VS Installer but NO MSVC compiler installed.
- Build must be done on a machine with MSVC v143 (Visual Studio 2022 Build Tools or Community).
- The CMakeLists.txt targets C++20, /O2, x64 Release, Windows SDK only.
