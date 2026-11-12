# Sentinel

Defensive Windows security toolkit — anti-cheat / EDR-style kernel detection.
This repository is the portfolio for an anti-cheat and Windows kernel security career.

## Status
- [ ] Phase 0 — foundations (toolchain, internals)
- [ ] Phase 1 — user-mode internals + reverse engineering
- [ ] Phase 2 — SENTINEL kernel integrity monitor
- [ ] Phase 3 — BYOVD detector + hypervisor detection
- [ ] Phase 4 — career / applications

## Map
- `ROADMAP.md` — the 12-month plan, resources, and accountability system
- `docs/` — project specs and writeups
- Code lands here phase by phase.

## Repository boundary

`Sentinel/` is the defensive project boundary inside this larger checkout. Sentinel code,
tests, and writeups must be self-contained here; they must not import, build, package, or
reuse code or runtime data from sibling research folders. Run tests only against owned test
programs, synthetic inputs, or targets in an approved lab or isolated VM, never production
systems. Do not include cheat or bypass code, unauthorized process modification, third-party
vulnerable-driver loaders, or credentials. Sentinel's own driver work must use a documented,
signed lab deployment procedure.

This is a directory boundary, not a separate Git repository: commits and Git history are
still shared with the parent checkout. Treat files outside `Sentinel/` as out of scope for
Sentinel releases, and review the staged file list before publishing.

## Artifact log (this becomes your CV)
| Date | Phase | Artifact | Link | Notes |
|------|-------|----------|------|-------|
| —    | 0     | hello-world KMDF driver | — | first load in WinDbg |
| —    | 0     | — | — | — |

## Weekly log
| Week | Focus | Hours | Artifact | Blockers |
|------|-------|-------|----------|----------|
| 1    | toolchain + *Windows Internals* ch.1–3 | 0 | hello-world KMDF driver | — |

## Scope & ethics
Detection and analysis only. No cheat code, no anti-cheat bypass, no tampering with
other processes. Everything here exists to *defend* players and systems.
