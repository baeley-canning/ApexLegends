# tools/ — which reader each probe speaks (set 2026-11-19)

**Product read path = `ext/qk_va.py` on gdrv3 (tier T1).** `gdrv3.sys` is Gigabyte's own
vendor-signed driver, already resident at logon via `GigabyteUpdateService`. Nothing of ours
is loaded and nothing is injected: parasitic, fully external.

Every compiled probe in this folder speaks **apexdrv** — a **custom** driver we map at
`C:\apexdrv.sys` (`ApexDrv`, DEMAND_START). That is tier **T2**, diagnostic. apexdrv attaches
(`KeStackAttachProcess`) on every IOCTL; gdrv3 never attaches. The same probes over apexdrv
are what killed the game in 14 s–4 min (`FACTS.md` transport section, `PLAN.md` 1b).

| Tool | Transport | Use it for |
|---|---|---|
| `qk_drvread.cpp` / `.hpp` | apexdrv | shared client + ABI check for the three below (ABI < 14 is refused) |
| `qk_probe.cpp` | apexdrv | BASE/READ8/READBUF smoke test on the game |
| `qk_ents.cpp` | apexdrv | which entity offset set is real (stage-2 recon) |
| `qk_hunt.cpp` | apexdrv | moved-offset hunt; duplicates `qk_va --find-array` |
| `qk_player_probe.cpp` | apexdrv | entity walk; `--scan` survives as a cross-check only |
| `qk_floats.cpp` | apexdrv (gio in one comment) | hex/float dump of a module region |
| `qk_overlay.cpp` | neither (GDI/D3D overlay) | the old C++ overlay; shipping overlay is `ext/qk_live.py` |

Build with the matching `Build*.ps1` (never bare `cl` — `New User` in the path breaks it, R6).
A probe result that matters must name its transport; `sc query` alone is not a read.

**Rule:** if a capability can be reached over gdrv3, do not add an apexdrv call for it.
`qk_va --driver` exists for exactly one thing: live page-table frames, which gdrv3 refuses
with `Errno 1450`.
