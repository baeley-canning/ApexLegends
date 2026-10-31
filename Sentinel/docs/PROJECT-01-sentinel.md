# Project 01 — SENTINEL: Kernel-Mode Process Integrity Monitor

**Phase:** 2 (weeks 19–34) · **Language:** C/C++ · **Target:** Windows 10/11 x64
**Why this project:** it is the closest single artifact to the anti-cheat/EDR job
descriptions — "developing, debugging and maintaining production-grade kernel-mode
drivers" plus "turn emerging threats into detections." It is purely defensive.

## What it does
A KMDF driver + user-mode service that watches for the categories of tampering that
anti-cheat and EDR both care about, and reports them to a signed log.

Detectors (build in this order):
1. **Manual-mapped / unbacked kernel drivers** — compare `PsLoadedModuleList` and the
   driver-object list against executable kernel pool; flag executable regions with no
   loaded-module backing.
2. **Unbacked executable user memory** — walk VADs for a target process (via process
   notify + PEB scan); flag RX/RWX regions not backed by an image file.
3. **Inline hooks / patched system code** — prologue- or hash-check a watchlist of
   `ntoskrnl` / `win32k` functions.
4. **Callback / DKOM tampering hints** — detect suspicious modification of
   loaded-module lists and anomalous handle-table usage.

## Architecture
- `kernel/integrity.sys` — KMDF driver: process/image callbacks, detection, report ring buffer
- `service/sentinel.exe` — user-mode service: loads the driver, collects telemetry, writes JSON/SQLite
- `cli/sentinelctl.exe` — configure, query, live-monitor
- `tests/` — benign harness that *simulates* each tamper in a scratch process and asserts detection

## Interfaces
- Driver ↔ service: one IOCTL plus an inverted call feeding a METHOD_NEITHER ring buffer
- Ruleset is data (JSON), not code, so detections update without re-signing the driver

## Milestones
| M | Week | Deliverable |
|---|------|-------------|
| M1 | 20 | Driver loads, logs, and unloads cleanly; IOCTL round-trip verified |
| M2 | 24 | Detector 1 (manual-mapped drivers) + automated test passes |
| M3 | 28 | Detectors 2 and 3 + tests pass |
| M4 | 31 | Service + CLI + JSON telemetry + external ruleset |
| M5 | 34 | Hardening, docs, blog post, test-signed release |

## Proof-of-done
- `build.ps1 -Test` runs green
- Reproducible: a scripted "attack" is detected in CI on every push
- Public writeup: "Detecting manually-mapped drivers from inside the kernel"
- Signed release artifact with a README architecture diagram

## Safety & legitimacy (keep this note in the repo README)
Runs only on your own VM. No target-process injection, no hiding from other security
software, no bypassing of protections. **Detection only.** Reviewers care about this —
state it explicitly.

## Skills it proves (maps straight to the JD)
Kernel driver development and debugging · Windows internals (virtual memory, VADs,
loader, callbacks) · detection engineering · RE-informed threat knowledge ·
testable security software
