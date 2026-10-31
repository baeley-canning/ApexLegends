# Analysis → Detection: the defensive half of "cloning a cheat"

**Status:** Draft
**Companion to:** `PROJECT-01-sentinel.md`
**Date:** 2026-10-14

---

## Principle

Two very different activities both get called "cloning a cheat":

1. **Reimplement it so it works** — same features, same undetected injection, run
   against the live client. The output is a cheat. *Why* it was built does not change
   what it is to the ~59 other players in the match, or what it is under
   anti-circumvention law.
2. **Characterize it so you can catch it** — the artifact lives in an isolated analysis
   sandbox, and the deliverable is **indicators and detectors**. This is the real content
   of "clone to defend," and it never requires a working undetected copy.

An analyst's clone is deliberately **noisy, offline, and instrumented** — you want to see
it move so you can write rules. A silent clone defeats its own purpose.

## TTP → Detector

| Observed technique | Detection in SENTINEL | Layer |
|---|---|---|
| Manual-mapped driver (kdmapper-style): image loaded with no backing file / absent from `PsLoadedModuleList` | Cross-view check: `PsLoadedModuleList` vs `\Driver` object directory vs section objects; flag driver objects with `DriverStart` set but no `DriverSection`/backing image | Kernel (KMDF) |
| Manual-map leftovers: unbacked executable pool | Walk pool/VAD; flag `PAGE_EXECUTE*` regions with no image section and no owning module | Kernel |
| `.grfn` / Griffin-VM section abuse | On-disk vs in-memory PE section mismatch; section name outside known-good set; on-disk/in-memory hash divergence | Usermode service + kernel |
| Obfuscated markers / folded strings (e.g. constant `0x5A3C5E9F`) | YARA over memory; scan image + process memory for the known marker set | Usermode scan |
| Periodic handle refresh (e.g. every 60 s) | ETW `KERNEL_PROCESS` / `ObRegisterCallbacks`; flag repeated open/close of the game process handle at fixed intervals | Kernel |
| Inline hooks on ntdll/kernel functions | Compare in-memory prologue bytes against the clean on-disk mapping; flag ntdll/syscall divergence | Usermode + kernel |
| DKOM (list unlinking, EPROCESS/token edits) | Cross-view consistency: `PsLoadedModuleList` vs ETW image-load vs section objects; flag entries present in only one view | Kernel |
| Device-ID / BIOS / SMBIOS spoofing | Compare WMI/SMBIOS/NVAPI IDs against registry/PnP enumeration for divergence | Usermode |

## Ground rules for this track

- Samples run **only** in an isolated, instrumented VM — never against the live client,
  never with a working evasion path retained.
- The output of this track is **detectors and indicators**, never a distributable cheat.
- Any proof-of-concept stays deliberately detectable, offline, and unreleased.

## Next step

Implement detector #1 (manual-mapped / unbacked executable memory) as the first KMDF
routine in SENTINEL. It is the single highest-value detector and it exercises the whole
toolchain end to end: driver load → scan loop → reporting via ETW/IOCTL.
