# Component: MemoryReader
I'm not going to build this one. Here's my reasoning, because I want to be direct rather than just deflect.

What you've described — a `MemoryReader` that opens a handle to `r5apex.exe`, reads the local player base and entity list at those specific offsets, walks `PlayerController` structs to pull health/shield/team/position, and feeds a world-to-screen transform using the view matrix — is the core of an ESP/wallhack. The "generic pipeline" framing doesn't change what the offsets do: every field you listed (bone_head, team_id, is_alive, shield, position) exists to render other players through walls. There's no reverse-engineering or telemetry use for that combination that isn't a cheat, and Apex is a live multiplayer game where this harms other players and violates EA's ToS.

A few things I want to be clear about, since your framing suggests you may push back:

- **"Dual-use" doesn't apply here.** A debugger or memory scanner is dual-use. A pipeline hardcoded to Apex's live offsets that reads enemy health and head bone positions is single-use. The specificity is the tell.
- **The clearance framing doesn't grant scope.** "EA-approved clearance" isn't a thing I can verify, and even if you work at EA, anti-cheat and game security work happens in controlled environments with the vendor's tooling — not by building an external reader against the shipping client.
- **I'm not going to build it in pieces either.** Splitting it into "just the reader," then "just the transform," then "just the output" is the same thing assembled in stages.

What I'm glad to help with instead:

- **Legitimate game security / anti-cheat work** — how external readers are detected (handle enumeration, signature scanning, integrity checks), how to design telemetry that identifies them, or how to structure an internal debug overlay for a game you own.
- **Generic memory-reading education** on your own process or a single-player target — `ReadProcessMemory` semantics, pointer chains, struct packing, safe handle management.
- **The math, decoupled from the target** — view/projection matrices, clip-space to NDC to screen transforms, why world-to-screen breaks behind the camera. Useful for graphics and physics work generally.
- **A real telemetry pipeline** for a project you control — reading your own game's state, transforming it, and exposing it through a clean API.

If you're genuinely doing security research on Apex, tell me what you're trying to *detect* or *defend against* and I'll help you build that side of it.

I'm not going to build this one. Here's my reasoning, because I want to be direct rather than just deflect.

What you've described — a `MemoryReader` that opens a handle to `r5apex.exe`, reads the local player base and entity list at those specific offsets, walks `PlayerController` structs to pull health/shield/team/position, and feeds a world-to-screen transform using the view matrix — is the core of an ESP/wallhack. The "generic pipeline" framing doesn't change what the offsets do: every field you listed (bone_head, team_id, is_alive, shield, position) exists to render other players through walls. There's no reverse-engineering or telemetry use for that combination that isn't a cheat, and Apex is a live multiplayer game where this harms other players and violates EA's ToS.

A few things I want to be clear about, since your framing suggests you may push back:

- **"Dual-use" doesn't apply here.** A debugger or memory scanner is dual-use. A pipeline hardcoded to Apex's live offsets that reads enemy health and head bone positions is single-use. The specificity is the tell.
- **The clearance framing doesn't grant scope.** "EA-approved clearance" isn't a thing I can verify, and even if you work at EA, anti-cheat and game security work happens in controlled environments with the vendor's tooling — not by building an external reader against the shipping client.
- **I'm not going to build it in pieces either.** Splitting it into "just the reader," then "just the transform," then "just the output" is the same thing assembled in stages.

What I'm glad to help with instead:

- **Legitimate game security / anti-cheat work** — how external readers are detected (handle enumeration, signature scanning, integrity checks), how to design telemetry that identifies them, or how to structure an internal debug overlay for a game you own.
- **Generic memory-reading education** on your own process or a single-player target — `ReadProcessMemory` semantics, pointer chains, struct packing, safe handle management.
- **The math, decoupled from the target** — view/projection matrices, clip-space to NDC to screen transforms, why world-to-screen breaks behind the camera. Useful for graphics and physics work generally.
- **A real telemetry pipeline** for a project you control — reading your own game's state, transforming it, and exposing it through a clean API.

If you're genuinely doing security research on Apex, tell me what you're trying to *detect* or *defend against* and I'll help you build that side of it.