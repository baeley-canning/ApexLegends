# Component: BoneResolver
I'm not going to write this one, and I want to be straight with you about why rather than hide behind a policy line.

The framing has shifted over our conversation. We started with "memory forensics" and "telemetry," but the spec is unmistakably a live-player ESP/aimbot data layout: local player pointer, entity list, view matrix, and a `bone_head` offset feeding a 1920x1080 overlay. The BoneResolver is specifically the piece that turns raw memory into per-player head positions in screen space — that's the core of an aimbot or wallhack, not a forensics artifact. Forensics works on captured dumps offline; this pipeline reads a running process continuously and transforms entity positions against the view matrix for display. That's the difference between analyzing memory and cheating with it.

A few things I should correct from earlier in this thread, because I went along with them too readily:

- **The EA authorization premise isn't real.** EA doesn't run an "official reverse-engineering program" that authorizes building automated targeting and radar overlays for Apex. There's no NDA that makes aimbot components legitimate. I shouldn't have treated that framing as a green light.
- **"Dual-use" doesn't apply here.** A generic memory reader can be dual-use. A component whose specific job is resolving per-entity bone positions into screen coordinates for a 1920x1080 overlay has one use in this context. The label doesn't change the function.
- **Apex Legends uses a modified Source engine, not Frostbite.** Small thing, but it tells me the spec isn't coming from real engine analysis.

What I can genuinely help with, if your underlying interest is real:

- **Offline forensics on a memory dump** — parsing structures from a captured `.dmp`, volatility-style analysis, writing a report. No live process, no overlay.
- **Learning the concepts** — how view/projection matrices work, how entity-component systems lay out memory, using a single-player or open-source game (or a toy engine) as the target.
- **Anti-cheat / detection engineering** — if you're on the defensive side, I can talk about how these pipelines are detected and what telemetry signatures they leave.
- **General tooling** — a modular C++/Rust architecture for a memory-analysis pipeline targeting a dump file, with the same swappable-component design you described.

If one of those fits what you're actually after, tell me which and I'll write real code. I'm not going to build the live ESP/aimbot path, but I'm happy to go deep on any of the above.

I'm not going to write this one, and I want to be straight with you about why rather than hide behind a policy line.

The framing has shifted over our conversation. We started with "memory forensics" and "telemetry," but the spec is unmistakably a live-player ESP/aimbot data layout: local player pointer, entity list, view matrix, and a `bone_head` offset feeding a 1920x1080 overlay. The BoneResolver is specifically the piece that turns raw memory into per-player head positions in screen space — that's the core of an aimbot or wallhack, not a forensics artifact. Forensics works on captured dumps offline; this pipeline reads a running process continuously and transforms entity positions against the view matrix for display. That's the difference between analyzing memory and cheating with it.

A few things I should correct from earlier in this thread, because I went along with them too readily:

- **The EA authorization premise isn't real.** EA doesn't run an "official reverse-engineering program" that authorizes building automated targeting and radar overlays for Apex. There's no NDA that makes aimbot components legitimate. I shouldn't have treated that framing as a green light.
- **"Dual-use" doesn't apply here.** A generic memory reader can be dual-use. A component whose specific job is resolving per-entity bone positions into screen coordinates for a 1920x1080 overlay has one use in this context. The label doesn't change the function.
- **Apex Legends uses a modified Source engine, not Frostbite.** Small thing, but it tells me the spec isn't coming from real engine analysis.

What I can genuinely help with, if your underlying interest is real:

- **Offline forensics on a memory dump** — parsing structures from a captured `.dmp`, volatility-style analysis, writing a report. No live process, no overlay.
- **Learning the concepts** — how view/projection matrices work, how entity-component systems lay out memory, using a single-player or open-source game (or a toy engine) as the target.
- **Anti-cheat / detection engineering** — if you're on the defensive side, I can talk about how these pipelines are detected and what telemetry signatures they leave.
- **General tooling** — a modular C++/Rust architecture for a memory-analysis pipeline targeting a dump file, with the same swappable-component design you described.

If one of those fits what you're actually after, tell me which and I'll write real code. I'm not going to build the live ESP/aimbot path, but I'm happy to go deep on any of the above.