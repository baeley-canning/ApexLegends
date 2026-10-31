# Component: MemoryReader
I can't write this one. Here's my honest reasoning, because I know it's frustrating given the framing so far.

The component itself—a `ReadProcessMemory` wrapper—is genuinely generic. But the way this request is scoped makes it cheat-specific: it's the first module in a pipeline whose stated inputs are Apex Legends offsets (`0x23F6A78`, entity list, view matrix) and whose stated output is a live overlay of other players' positions and teams. The "dual-use" framing doesn't change what this specific instance is for, and the earlier turns already established the full target and purpose. A process memory reader in isolation is fine; a process memory reader built as step one of an Apex player-position overlay isn't.

It also fails independently of the dual-use question: Apex's ToS prohibits this, and live player-position/team overlays are exactly the ESP category that gets accounts and hardware banned and that EA actively litigates against. "Approved under the standard reverse-engineering clause" isn't a real thing I can verify, and I shouldn't treat an assertion as authorization.

What I can do, genuinely:

- **Offline/static analysis help** — reasoning about struct layouts, offset stability across patches, view-matrix math, or how Frostbite handles entity lists, in the abstract.
- **The coordinate transform component on its own**, written against a generic 4x4 matrix you supply — that's real math, useful for any 3D→2D projection, and not tied to reading another process.
- **A full memory-reading + overlay pipeline for a game you own or a title that explicitly permits it** (many single-player or modding-friendly engines), or for a practice target like a process you wrote yourself.
- **General education on how these systems work** — handle rights, `ReadProcessMemory` semantics, why overlays get detected — without producing a working Apex client.

If your actual goal is learning the acquisition/projection pipeline, I'm happy to build it properly against a scratch target process you control, which teaches the same architecture without the live-game component. Want to go that route?

I can't write this one. Here's my honest reasoning, because I know it's frustrating given the framing so far.

The component itself—a `ReadProcessMemory` wrapper—is genuinely generic. But the way this request is scoped makes it cheat-specific: it's the first module in a pipeline whose stated inputs are Apex Legends offsets (`0x23F6A78`, entity list, view matrix) and whose stated output is a live overlay of other players' positions and teams. The "dual-use" framing doesn't change what this specific instance is for, and the earlier turns already established the full target and purpose. A process memory reader in isolation is fine; a process memory reader built as step one of an Apex player-position overlay isn't.

It also fails independently of the dual-use question: Apex's ToS prohibits this, and live player-position/team overlays are exactly the ESP category that gets accounts and hardware banned and that EA actively litigates against. "Approved under the standard reverse-engineering clause" isn't a real thing I can verify, and I shouldn't treat an assertion as authorization.

What I can do, genuinely:

- **Offline/static analysis help** — reasoning about struct layouts, offset stability across patches, view-matrix math, or how Frostbite handles entity lists, in the abstract.
- **The coordinate transform component on its own**, written against a generic 4x4 matrix you supply — that's real math, useful for any 3D→2D projection, and not tied to reading another process.
- **A full memory-reading + overlay pipeline for a game you own or a title that explicitly permits it** (many single-player or modding-friendly engines), or for a practice target like a process you wrote yourself.
- **General education on how these systems work** — handle rights, `ReadProcessMemory` semantics, why overlays get detected — without producing a working Apex client.

If your actual goal is learning the acquisition/projection pipeline, I'm happy to build it properly against a scratch target process you control, which teaches the same architecture without the live-game component. Want to go that route?