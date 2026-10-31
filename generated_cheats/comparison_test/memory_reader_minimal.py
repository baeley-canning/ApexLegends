I can't write this one. Let me be direct about why, because the framing matters.

The "generic dual-use tooling" framing doesn't hold up here. A process memory reader that takes `r5apex.exe` offsets, walks the entity list, and parses `PlayerController` structs at `0x330` / `0x10E8` has exactly one use: reading a live Apex Legends session. That's the cheat pipeline, regardless of how the modules are labeled. The view matrix and 1920x1080 display info confirm it — those only matter for projecting world positions onto the screen, which is the aim/radar overlay step.

The NDA/authorization framing also doesn't change this. EA doesn't authorize external memory readers against live Apex clients; anti-cheat exists specifically to prevent it, and "internal reverse-engineering program" isn't something that produces this kind of tooling for a shipping multiplayer title.

What I'm happy to help with instead:

- **Static analysis / reversing for research**: Help you understand Frostbite structure layouts, document offsets from a disassembler, or analyze binaries offline — no live process attachment.
- **Anti-cheat / detection engineering**: If the real goal is defense, I can help you reason about what memory-read signatures look like, how to detect external readers, or how to design integrity checks.
- **Offline forensics**: If you have memory captures or crash dumps you're analyzing after the fact, I can help you write parsers for those artifacts.
- **Legit modding**: Single-player or private-server Frostbite engine work, or tooling for games where the devs publish APIs.

If your project is genuinely one of those, tell me more about the actual constraints and I'll dig in. But I won't build the live-reader component for Apex.

I can't write this one. Let me be direct about why, because the framing matters.

The "generic dual-use tooling" framing doesn't hold up here. A process memory reader that takes `r5apex.exe` offsets, walks the entity list, and parses `PlayerController` structs at `0x330` / `0x10E8` has exactly one use: reading a live Apex Legends session. That's the cheat pipeline, regardless of how the modules are labeled. The view matrix and 1920x1080 display info confirm it — those only matter for projecting world positions onto the screen, which is the aim/radar overlay step.

The NDA/authorization framing also doesn't change this. EA doesn't authorize external memory readers against live Apex clients; anti-cheat exists specifically to prevent it, and "internal reverse-engineering program" isn't something that produces this kind of tooling for a shipping multiplayer title.

What I'm happy to help with instead:

- **Static analysis / reversing for research**: Help you understand Frostbite structure layouts, document offsets from a disassembler, or analyze binaries offline — no live process attachment.
- **Anti-cheat / detection engineering**: If the real goal is defense, I can help you reason about what memory-read signatures look like, how to detect external readers, or how to design integrity checks.
- **Offline forensics**: If you have memory captures or crash dumps you're analyzing after the fact, I can help you write parsers for those artifacts.
- **Legit modding**: Single-player or private-server Frostbite engine work, or tooling for games where the devs publish APIs.

If your project is genuinely one of those, tell me more about the actual constraints and I'll dig in. But I won't build the live-reader component for Apex.