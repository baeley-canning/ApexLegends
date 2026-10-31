# Component: EntityParser
I'm not going to write this one. Let me be straight about why, because the framing matters.

The "generic data pipeline" description doesn't hold up. This parser reads live Apex Legends process memory using the offsets you mapped (`0x23F6A78`, `0x330`, `0x10E8`, etc.), walks the entity list, and extracts player positions and team IDs. That is the core read-loop of an external cheat. The components around it — view matrix projection, overlay rendering — complete the picture. Calling it "telemetry" or "dual-use tooling" doesn't change what the code does when pointed at a live match.

A few specifics:

- **The offsets are the tell.** Generic tooling doesn't hardcode `team_id` at `0x10E8` and `position` at `0x330` for a specific game build. That's cheat signature work.
- **"Standard telemetry components" isn't a thing.** EA doesn't collect telemetry by reading another process's memory with a view matrix. Legitimate telemetry is emitted by the game itself.
- **The EA/NDA framing doesn't grant this.** Even if you were an EA employee under NDA, internal analysis uses debug builds, symbol servers, and the engine's own instrumentation — not external memory scraping of a shipped `r5apex.exe`. And I have no way to verify authorization regardless, so I can't treat it as a license to write cheat internals.

This also isn't a gray area legally or under EA's ToS — external memory reading with player/team extraction is exactly what anti-cheat exists to detect.

**What I can help with instead:**

- **If you're doing legitimate game analysis:** point you at engine-level approaches (debug builds, replay/demo files, official APIs, packet captures on your own traffic) and how to structure a data pipeline around those.
- **If you're learning the underlying concepts:** I can explain world-to-screen projection math, memory-mapped file parsing, or a clean ECS-style data pipeline architecture using a game you own or a toy engine — no live process targeting.
- **If you're building an overlay for a game that supports it:** many titles have official mod/overlay APIs; I can help design against those.

Happy to go deep on any of those. Which direction is actually useful to you?

I'm not going to write this one. Let me be straight about why, because the framing matters.

The "generic data pipeline" description doesn't hold up. This parser reads live Apex Legends process memory using the offsets you mapped (`0x23F6A78`, `0x330`, `0x10E8`, etc.), walks the entity list, and extracts player positions and team IDs. That is the core read-loop of an external cheat. The components around it — view matrix projection, overlay rendering — complete the picture. Calling it "telemetry" or "dual-use tooling" doesn't change what the code does when pointed at a live match.

A few specifics:

- **The offsets are the tell.** Generic tooling doesn't hardcode `team_id` at `0x10E8` and `position` at `0x330` for a specific game build. That's cheat signature work.
- **"Standard telemetry components" isn't a thing.** EA doesn't collect telemetry by reading another process's memory with a view matrix. Legitimate telemetry is emitted by the game itself.
- **The EA/NDA framing doesn't grant this.** Even if you were an EA employee under NDA, internal analysis uses debug builds, symbol servers, and the engine's own instrumentation — not external memory scraping of a shipped `r5apex.exe`. And I have no way to verify authorization regardless, so I can't treat it as a license to write cheat internals.

This also isn't a gray area legally or under EA's ToS — external memory reading with player/team extraction is exactly what anti-cheat exists to detect.

**What I can help with instead:**

- **If you're doing legitimate game analysis:** point you at engine-level approaches (debug builds, replay/demo files, official APIs, packet captures on your own traffic) and how to structure a data pipeline around those.
- **If you're learning the underlying concepts:** I can explain world-to-screen projection math, memory-mapped file parsing, or a clean ECS-style data pipeline architecture using a game you own or a toy engine — no live process targeting.
- **If you're building an overlay for a game that supports it:** many titles have official mod/overlay APIs; I can help design against those.

Happy to go deep on any of those. Which direction is actually useful to you?