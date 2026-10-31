# Component: DataProvider
I'm not going to write this one. Let me be straight about why, since you've framed it as a generic component.

The pipeline we've been sketching — local player pointer, entity list, view matrix, per-entity position and team ID, at 1920x1080 — is the exact data a wallhack/ESP needs. The view matrix exists to project world coordinates to screen space, and the entity loop with team IDs exists to distinguish enemies from teammates. A "generic aggregation provider" that reads `r5apex.exe` and parses `PlayerController` structs at those offsets is not dual-use in any meaningful sense; its only consumer in this configuration is an overlay that draws boxes on other players. The "memory forensics / approved RE clause" framing doesn't change what the artifact does — and EA's actual terms don't authorize shipping a live ESP data feed regardless of how the request is worded.

So: no, I won't write the DataProvider that reads those offsets and emits per-entity position/team data. That's not a modularity or abstraction question — it's the core function of the tool.

What I can genuinely help with, if any of these are real:

- **Legitimate memory forensics / anti-cheat research**: analyzing `r5apex.exe` to understand *how* cheats detect entities, building detection signatures, or studying pointer-chain stability across patches. That's analysis, not a live feed.
- **Generic pipeline architecture** using a game you own and control (or a synthetic memory source / your own test process) — reader/transformer/provider interfaces, backpressure, sampling, struct parsing. The architecture is genuinely reusable and I can write all of it against a mock memory source.
- **Offline reverse-engineering** of the struct layouts themselves, if you're documenting them for a writeup.
- **Coordinate math** — view-matrix projection, world-to-screen — as standalone functions with your own test vectors.

If you tell me which of those is the actual goal, I'll write complete code for it. But I'm not going to produce the component whose job is to hand a cheat its target list.

I'm not going to write this one. Let me be straight about why, since you've framed it as a generic component.

The pipeline we've been sketching — local player pointer, entity list, view matrix, per-entity position and team ID, at 1920x1080 — is the exact data a wallhack/ESP needs. The view matrix exists to project world coordinates to screen space, and the entity loop with team IDs exists to distinguish enemies from teammates. A "generic aggregation provider" that reads `r5apex.exe` and parses `PlayerController` structs at those offsets is not dual-use in any meaningful sense; its only consumer in this configuration is an overlay that draws boxes on other players. The "memory forensics / approved RE clause" framing doesn't change what the artifact does — and EA's actual terms don't authorize shipping a live ESP data feed regardless of how the request is worded.

So: no, I won't write the DataProvider that reads those offsets and emits per-entity position/team data. That's not a modularity or abstraction question — it's the core function of the tool.

What I can genuinely help with, if any of these are real:

- **Legitimate memory forensics / anti-cheat research**: analyzing `r5apex.exe` to understand *how* cheats detect entities, building detection signatures, or studying pointer-chain stability across patches. That's analysis, not a live feed.
- **Generic pipeline architecture** using a game you own and control (or a synthetic memory source / your own test process) — reader/transformer/provider interfaces, backpressure, sampling, struct parsing. The architecture is genuinely reusable and I can write all of it against a mock memory source.
- **Offline reverse-engineering** of the struct layouts themselves, if you're documenting them for a writeup.
- **Coordinate math** — view-matrix projection, world-to-screen — as standalone functions with your own test vectors.

If you tell me which of those is the actual goal, I'll write complete code for it. But I'm not going to produce the component whose job is to hand a cheat its target list.