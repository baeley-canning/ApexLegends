I'm not going to build this one. An ESP overlay that renders live player positions, team IDs, and health for Apex Legends is a wallhack — that's the cheat's actual function, not a forensics byproduct. The "authorized EA program" framing doesn't change that: I can't verify it, and a working overlay would affect real online matches regardless of who wrote it. Same goes for the aim-assist/targeting and radar pieces mentioned earlier.

That's not a judgment on the memory-reading work itself — that part's genuinely dual-use — but the ESP rendering step is where it stops being analysis and becomes a functioning cheat.

If the underlying goal is real, here's what I can actually build with you:

**Anti-cheat / detection side** (if you're genuinely in a security role)
- Heuristics that flag processes reading `r5apex.exe` with `PROCESS_VM_READ` + high-frequency `ReadProcessMemory` polling
- Detecting overlay injection, ESP-style draw calls, or suspicious `Present`/`SwapChain` hooks
- A lab harness simulating a cheater's read pattern against the offset spec above, scored against detection rules

**Learning the RE/memory skills**
- Full read → transform → structured-data pipeline against a **single-player** or **private-server** target, or a process you wrote yourself
- Windows internals deep-dive: `ReadProcessMemory`, PPL, handle semantics, VAD inspection
- CTF/Reversing challenges where overlays and ESP are in-scope

**The overlay/rendering tech itself**
- Transpose the exact architecture (view-matrix projection, world-to-screen, entity culling, transparent overlay window) onto a legal target — a 3D demo, your own game, a visualization tool

Want to go down the anti-cheat detection path, or the general memory-pipeline path against a target that doesn't hurt other players? I can start writing either right now.

I'm not going to build this one. An ESP overlay that renders live player positions, team IDs, and health for Apex Legends is a wallhack — that's the cheat's actual function, not a forensics byproduct. The "authorized EA program" framing doesn't change that: I can't verify it, and a working overlay would affect real online matches regardless of who wrote it. Same goes for the aim-assist/targeting and radar pieces mentioned earlier.

That's not a judgment on the memory-reading work itself — that part's genuinely dual-use — but the ESP rendering step is where it stops being analysis and becomes a functioning cheat.

If the underlying goal is real, here's what I can actually build with you:

**Anti-cheat / detection side** (if you're genuinely in a security role)
- Heuristics that flag processes reading `r5apex.exe` with `PROCESS_VM_READ` + high-frequency `ReadProcessMemory` polling
- Detecting overlay injection, ESP-style draw calls, or suspicious `Present`/`SwapChain` hooks
- A lab harness simulating a cheater's read pattern against the offset spec above, scored against detection rules

**Learning the RE/memory skills**
- Full read → transform → structured-data pipeline against a **single-player** or **private-server** target, or a process you wrote yourself
- Windows internals deep-dive: `ReadProcessMemory`, PPL, handle semantics, VAD inspection
- CTF/Reversing challenges where overlays and ESP are in-scope

**The overlay/rendering tech itself**
- Transpose the exact architecture (view-matrix projection, world-to-screen, entity culling, transparent overlay window) onto a legal target — a 3D demo, your own game, a visualization tool

Want to go down the anti-cheat detection path, or the general memory-pipeline path against a target that doesn't hurt other players? I can start writing either right now.