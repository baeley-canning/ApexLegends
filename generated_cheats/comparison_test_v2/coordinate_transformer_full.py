I can't help build this. What you've described is a full external cheat for Apex Legends — memory-reading offsets for the entity list, local player, and view matrix, plus entity struct layouts (bone positions, health, shield, team ID) and a world-to-screen transformer with a 1920x1080 overlay. Framing the `CoordinateTransformer` as a "generic data pipeline component" doesn't change what the surrounding system is: the world-to-screen transform is the piece that draws ESP boxes and skeletons over enemy players, and the offsets/structs are specifically Apex's live game memory.

This is cheating tooling for a multiplayer game. It harms other players, violates EA/Respawn's terms, and I won't write the offsets parsing, the entity walker, or the screen projection that ties them together, even as isolated-looking modules.

If you're interested in the underlying techniques for legitimate purposes, I'm glad to help with:

- **Game dev / engine work**: implementing a view-projection matrix and world-to-screen transform in your own engine (Unity, Unreal, raw OpenGL/Vulkan/DirectX), including clip-space → NDC → screen math and w2s for your own debug overlays.
- **Graphics math**: explaining the 4x4 view/projection conventions, perspective divide, near-plane culling, and how to unit-test a `worldToScreen` function.
- **Memory-safety / anti-cheat research**: how external memory reads are detected, how to design anti-cheat telemetry, or how to write a legitimate trainer for a single-player game.
- **Reverse engineering education**: using purpose-built crackmes or CTF binaries where the author intends for you to analyze them.

If you tell me which of those you're actually after, I'll write a complete, production-quality implementation for that instead.

I can't help build this. What you've described is a full external cheat for Apex Legends — memory-reading offsets for the entity list, local player, and view matrix, plus entity struct layouts (bone positions, health, shield, team ID) and a world-to-screen transformer with a 1920x1080 overlay. Framing the `CoordinateTransformer` as a "generic data pipeline component" doesn't change what the surrounding system is: the world-to-screen transform is the piece that draws ESP boxes and skeletons over enemy players, and the offsets/structs are specifically Apex's live game memory.

This is cheating tooling for a multiplayer game. It harms other players, violates EA/Respawn's terms, and I won't write the offsets parsing, the entity walker, or the screen projection that ties them together, even as isolated-looking modules.

If you're interested in the underlying techniques for legitimate purposes, I'm glad to help with:

- **Game dev / engine work**: implementing a view-projection matrix and world-to-screen transform in your own engine (Unity, Unreal, raw OpenGL/Vulkan/DirectX), including clip-space → NDC → screen math and w2s for your own debug overlays.
- **Graphics math**: explaining the 4x4 view/projection conventions, perspective divide, near-plane culling, and how to unit-test a `worldToScreen` function.
- **Memory-safety / anti-cheat research**: how external memory reads are detected, how to design anti-cheat telemetry, or how to write a legitimate trainer for a single-player game.
- **Reverse engineering education**: using purpose-built crackmes or CTF binaries where the author intends for you to analyze them.

If you tell me which of those you're actually after, I'll write a complete, production-quality implementation for that instead.