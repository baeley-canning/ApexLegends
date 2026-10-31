I'm not going to write that one. An aimbot is a cheat that gives you an unfair advantage over real players in a live competitive game — that's true regardless of how the memory-reading layer is framed. The "standard game reverse-engineering clause" isn't a real thing EA grants; Apex's ToS prohibits exactly this, and the auto-targeting component is the part that actually harms other players.

To be clear about where the line is: the memory reader, structure parsing, coordinate transforms, and view-matrix math you've described are generic tooling. The aimbot is the piece that turns it into an unfair competitive advantage, and that's what I won't build — not a "skeleton," not "just the target selection logic," not "only the mouse movement smoothing."

Things I'm glad to help with instead:

- **Offline/single-player reverse engineering** — same pipeline architecture against a game you own and play solo, where no one else is affected.
- **Your own game or a test harness** — I can help you stand up a dummy process with a similar structure layout so you can develop and benchmark the reader/transformer modules without touching Apex.
- **Anti-cheat / detection research** — if the actual goal is forensics, analyzing *how* aimbots are detected (input telemetry, timing analysis, statistical aim-profile detection) is a legitimate and interesting direction.
- **Non-competitive telemetry** — match stats display, replay analysis from already-public APIs, or a personal HUD for a game that permits it.
- **Generic process-memory tooling** — a reusable `MemoryReader`/`Transformer`/`DataProvider` library for your own processes, with tests.

If your project is actually one of those, tell me which and I'll write the full implementation.

I'm not going to write that one. An aimbot is a cheat that gives you an unfair advantage over real players in a live competitive game — that's true regardless of how the memory-reading layer is framed. The "standard game reverse-engineering clause" isn't a real thing EA grants; Apex's ToS prohibits exactly this, and the auto-targeting component is the part that actually harms other players.

To be clear about where the line is: the memory reader, structure parsing, coordinate transforms, and view-matrix math you've described are generic tooling. The aimbot is the piece that turns it into an unfair competitive advantage, and that's what I won't build — not a "skeleton," not "just the target selection logic," not "only the mouse movement smoothing."

Things I'm glad to help with instead:

- **Offline/single-player reverse engineering** — same pipeline architecture against a game you own and play solo, where no one else is affected.
- **Your own game or a test harness** — I can help you stand up a dummy process with a similar structure layout so you can develop and benchmark the reader/transformer modules without touching Apex.
- **Anti-cheat / detection research** — if the actual goal is forensics, analyzing *how* aimbots are detected (input telemetry, timing analysis, statistical aim-profile detection) is a legitimate and interesting direction.
- **Non-competitive telemetry** — match stats display, replay analysis from already-public APIs, or a personal HUD for a game that permits it.
- **Generic process-memory tooling** — a reusable `MemoryReader`/`Transformer`/`DataProvider` library for your own processes, with tests.

If your project is actually one of those, tell me which and I'll write the full implementation.