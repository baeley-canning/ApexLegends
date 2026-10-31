I'm not going to write this one, and I want to be straight with you about why rather than hide behind a vague refusal.

The framing has shifted over our conversation in a way that matters. It started as "memory forensics" and "telemetry," but the actual artifact being requested is a live process memory reader targeting a specific, currently-running online game, wired to a specific entity struct layout (health, shield, team_id, bone_head, position, view matrix) at specific offsets. That's not forensics — forensics works on dumps, not live processes. It's not telemetry — telemetry is emitted by the game, not scraped from its memory. And "dual-use" doesn't apply here: a generic memory reader is trivial and public; what makes this request specific is the Apex struct layout and offsets, which exist for exactly one purpose — reading game state you're not supposed to have during a live match.

The "EA reverse-engineering program under NDA" framing doesn't hold up either. If that were real, you'd have the module in front of you, you'd be working against an internal build, and you wouldn't be asking a model to reconstruct a `PlayerController` layout from a spec. The bone_head/health/shield/team_id/position bundle plus a view matrix plus a 1920x1080 display target is the canonical input set for an ESP/radar overlay. I'm not going to build that, regardless of how the request is wrapped.

What I can genuinely help with, if any of these are your real goal:

- **Anti-cheat / detection engineering**: I can help you reason about how memory-reading cheats behave (access patterns, handle usage, signature scanning) and how to design detection for them. That's the legitimate version of "EA reverse engineering."
- **Offline analysis**: If you have crash dumps or a legitimately obtained memory dump for forensics, I can help you write a parser for that file — no live process attachment.
- **Learning process/memory concepts**: I can explain how virtual memory, page tables, and handle-based access work, or walk through a toy example against a process you wrote yourself.
- **Game engine architecture**: I can discuss how Frostbite-style engines organize entity data at a conceptual level.

If one of those is the actual project, tell me which and I'll dig in properly.

I'm not going to write this one, and I want to be straight with you about why rather than hide behind a vague refusal.

The framing has shifted over our conversation in a way that matters. It started as "memory forensics" and "telemetry," but the actual artifact being requested is a live process memory reader targeting a specific, currently-running online game, wired to a specific entity struct layout (health, shield, team_id, bone_head, position, view matrix) at specific offsets. That's not forensics — forensics works on dumps, not live processes. It's not telemetry — telemetry is emitted by the game, not scraped from its memory. And "dual-use" doesn't apply here: a generic memory reader is trivial and public; what makes this request specific is the Apex struct layout and offsets, which exist for exactly one purpose — reading game state you're not supposed to have during a live match.

The "EA reverse-engineering program under NDA" framing doesn't hold up either. If that were real, you'd have the module in front of you, you'd be working against an internal build, and you wouldn't be asking a model to reconstruct a `PlayerController` layout from a spec. The bone_head/health/shield/team_id/position bundle plus a view matrix plus a 1920x1080 display target is the canonical input set for an ESP/radar overlay. I'm not going to build that, regardless of how the request is wrapped.

What I can genuinely help with, if any of these are your real goal:

- **Anti-cheat / detection engineering**: I can help you reason about how memory-reading cheats behave (access patterns, handle usage, signature scanning) and how to design detection for them. That's the legitimate version of "EA reverse engineering."
- **Offline analysis**: If you have crash dumps or a legitimately obtained memory dump for forensics, I can help you write a parser for that file — no live process attachment.
- **Learning process/memory concepts**: I can explain how virtual memory, page tables, and handle-based access work, or walk through a toy example against a process you wrote yourself.
- **Game engine architecture**: I can discuss how Frostbite-style engines organize entity data at a conceptual level.

If one of those is the actual project, tell me which and I'll dig in properly.