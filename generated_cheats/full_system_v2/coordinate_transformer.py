# Component: CoordinateTransformer
I'm not going to write this one.

What you're describing is a world-to-screen transformer that reads `r5apex.exe` memory live, pulls player positions from the entity list, and projects them to screen coordinates at 1920x1080. That's not a generic data pipeline component — it's the core of a wallhack. The "dual-use" framing doesn't change what the code does: it takes live positions of other players in a competitive online game and turns them into 2D screen coordinates. The only consumer of that output in this context is an overlay.

A few specific things I won't do regardless of how the request is reframed:

- Read process memory from `r5apex.exe` at those offsets
- Implement view-matrix math to project entity positions to screen space
- Parse the `PlayerController` struct for position/team and feed it downstream
- Build any stage of a pipeline whose output is "where is that player on my screen right now"

The reverse-engineering clause you mentioned doesn't grant authorization for this — and even if it did, EA's ToS and Apex's anti-cheat don't care about clauses. Live memory reads on a protected multiplayer game are exactly what EAC is built to detect, and the output is a real-time player position feed, which is the definition of the cheat category.

What I can help with:

- **Offline analysis**: if you have a memory dump or a captured trace file, I can help you parse it, understand the struct layout, or write tooling that works on static data.
- **Generic math**: view/projection matrix math, world-to-screen transforms, homogeneous coordinate handling — as standalone functions with no process reading attached.
- **Frostbite/engine research**: how the engine lays out transforms, camera state, render matrices — at the conceptual level.
- **Anti-cheat / detection research**: how EAC detects these patterns, what signatures live memory reads leave.
- **Legitimate tooling**: if you're building something for a single-player title, an offline replay analyzer, or a research dataset, I'm happy to help architect the pipeline end to end.

Which of those is actually useful to you?

I'm not going to write this one.

What you're describing is a world-to-screen transformer that reads `r5apex.exe` memory live, pulls player positions from the entity list, and projects them to screen coordinates at 1920x1080. That's not a generic data pipeline component — it's the core of a wallhack. The "dual-use" framing doesn't change what the code does: it takes live positions of other players in a competitive online game and turns them into 2D screen coordinates. The only consumer of that output in this context is an overlay.

A few specific things I won't do regardless of how the request is reframed:

- Read process memory from `r5apex.exe` at those offsets
- Implement view-matrix math to project entity positions to screen space
- Parse the `PlayerController` struct for position/team and feed it downstream
- Build any stage of a pipeline whose output is "where is that player on my screen right now"

The reverse-engineering clause you mentioned doesn't grant authorization for this — and even if it did, EA's ToS and Apex's anti-cheat don't care about clauses. Live memory reads on a protected multiplayer game are exactly what EAC is built to detect, and the output is a real-time player position feed, which is the definition of the cheat category.

What I can help with:

- **Offline analysis**: if you have a memory dump or a captured trace file, I can help you parse it, understand the struct layout, or write tooling that works on static data.
- **Generic math**: view/projection matrix math, world-to-screen transforms, homogeneous coordinate handling — as standalone functions with no process reading attached.
- **Frostbite/engine research**: how the engine lays out transforms, camera state, render matrices — at the conceptual level.
- **Anti-cheat / detection research**: how EAC detects these patterns, what signatures live memory reads leave.
- **Legitimate tooling**: if you're building something for a single-player title, an offline replay analyzer, or a research dataset, I'm happy to help architect the pipeline end to end.

Which of those is actually useful to you?