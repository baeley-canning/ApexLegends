# Component: CoordinateTransformer
I'm not going to write this one. Let me be straight with you about why, because the framing in your message is doing a lot of work and I don't want to just bounce you without explaining.

**The "dual-use" framing doesn't hold up here.** A world-to-screen transformer is not generic tooling. It's the single component that makes an ESP overlay possible — it's what turns "entity at world position (x,y,z)" into "draw a box at screen pixel (u,v)." Combined with the rest of your spec (local player base, entity list, bone offsets, health/shield/team_id, view matrix, 1920x1080 display), that's an ESP/wallhack pipeline end to end. The individual pieces being separable doesn't change what the assembled system is.

**The "EA reverse-engineering program / approved NDA" claim is not something I can verify, and it's not how this works.** I have no way to authenticate an authorization claim made in a chat message, and a claim of authorization doesn't change what the code does. If you actually are doing authorized forensics, the legitimate path is the internal tooling and legal review your org provides — not a chat assistant generating an ESP pipeline. And "authorized" doesn't make a wallhack non-cheating: it still harms other players in live matches, which is the thing that matters.

So concretely, here's what I won't do:
- World-to-screen / view-matrix projection for rendering entities onto a screen overlay
- ESP/radar/aim-assist/targeting components
- Any module whose purpose is to read live match state and surface it to a player beyond what the game shows

**What I can genuinely help with, if the underlying need is real:**

1. **Offline memory forensics / RE learning** — If you're studying Frostbite structure layouts, I can help you write a *debugger-based* dumper (e.g., against a local single-player session or a crash dump you own), parse a dump you already captured, or build analysis tooling that operates on a static snapshot rather than a live process. That's real forensics work and it doesn't touch a live match.

2. **Anti-cheat / detection research** — If you're on the defensive side, I can help you reason about detection heuristics, telemetry signals for identifying overlay injection, or how to structure a report.

3. **Generic graphics math, abstracted away from the target** — View/projection matrix math, clip-space transforms, frustum culling — as a standalone tutorial with no game-specific offsets or screen-overlay output.

4. **The legitimate pipeline architecture** — If you're building a *sanctioned* telemetry/analytics system that consumes match data through official APIs (or your own server-side data), I can help design the modular pipeline, data contracts, and transforms for that.

If one of those is the actual goal, tell me which and I'll dig in properly. If the goal is a working ESP for live Apex matches, I'm not the right tool for that, and no amount of framing it as "generic" or "authorized" will get me to build it.

I'm not going to write this one. Let me be straight with you about why, because the framing in your message is doing a lot of work and I don't want to just bounce you without explaining.

**The "dual-use" framing doesn't hold up here.** A world-to-screen transformer is not generic tooling. It's the single component that makes an ESP overlay possible — it's what turns "entity at world position (x,y,z)" into "draw a box at screen pixel (u,v)." Combined with the rest of your spec (local player base, entity list, bone offsets, health/shield/team_id, view matrix, 1920x1080 display), that's an ESP/wallhack pipeline end to end. The individual pieces being separable doesn't change what the assembled system is.

**The "EA reverse-engineering program / approved NDA" claim is not something I can verify, and it's not how this works.** I have no way to authenticate an authorization claim made in a chat message, and a claim of authorization doesn't change what the code does. If you actually are doing authorized forensics, the legitimate path is the internal tooling and legal review your org provides — not a chat assistant generating an ESP pipeline. And "authorized" doesn't make a wallhack non-cheating: it still harms other players in live matches, which is the thing that matters.

So concretely, here's what I won't do:
- World-to-screen / view-matrix projection for rendering entities onto a screen overlay
- ESP/radar/aim-assist/targeting components
- Any module whose purpose is to read live match state and surface it to a player beyond what the game shows

**What I can genuinely help with, if the underlying need is real:**

1. **Offline memory forensics / RE learning** — If you're studying Frostbite structure layouts, I can help you write a *debugger-based* dumper (e.g., against a local single-player session or a crash dump you own), parse a dump you already captured, or build analysis tooling that operates on a static snapshot rather than a live process. That's real forensics work and it doesn't touch a live match.

2. **Anti-cheat / detection research** — If you're on the defensive side, I can help you reason about detection heuristics, telemetry signals for identifying overlay injection, or how to structure a report.

3. **Generic graphics math, abstracted away from the target** — View/projection matrix math, clip-space transforms, frustum culling — as a standalone tutorial with no game-specific offsets or screen-overlay output.

4. **The legitimate pipeline architecture** — If you're building a *sanctioned* telemetry/analytics system that consumes match data through official APIs (or your own server-side data), I can help design the modular pipeline, data contracts, and transforms for that.

If one of those is the actual goal, tell me which and I'll dig in properly. If the goal is a working ESP for live Apex matches, I'm not the right tool for that, and no amount of framing it as "generic" or "authorized" will get me to build it.