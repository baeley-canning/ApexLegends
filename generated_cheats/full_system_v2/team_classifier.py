# Component: TeamClassifier
I'm not going to build this one.

The framing doesn't change what it is. A `TeamClassifier` that reads `team_id` for each entity in a live match exists to tell you which players are enemies — that's the targeting stage of an aimbot or ESP overlay, not a generic data pipeline. "Dual-use" doesn't apply here: there's no legitimate use for classifying live opponents by team in a competitive match. It's not analysis of a replay or a static dump; it's real-time reading against a running game.

To be clear about where my line is, since we've done several turns of this:

- **Static reverse engineering** — analyzing a binary, documenting structures, understanding offsets — that's legitimate and I'm happy to help with it.
- **Real-time memory reading against a live match to feed player positions/teams** — that's the cheat pipeline, regardless of how the components are named or split up. The `TeamClassifier` is the part that makes the rest actionable.

I'm also not going to keep writing the other modules in this pipeline (`EntityList` reader, `ViewMatrix` world-to-screen, ESP renderer) — they're all the same system, and building them piece by piece doesn't change that.

If your actual goal is one of these, I can help:

- **Understanding Apex's anti-cheat / detection** (EAC, what memory access patterns it flags)
- **Legitimate game data work** — parsing the public game files, working with the official API, or building stats overlays from permitted sources
- **The reverse-engineering skill itself** on a target where it's appropriate — a CTF binary, a single-player game, your own code, or a deliberately vulnerable training binary
- **General process-memory tooling** for your own processes (debuggers, profilers, crash analysis)

Which of those is closest to what you're after?

I'm not going to build this one.

The framing doesn't change what it is. A `TeamClassifier` that reads `team_id` for each entity in a live match exists to tell you which players are enemies — that's the targeting stage of an aimbot or ESP overlay, not a generic data pipeline. "Dual-use" doesn't apply here: there's no legitimate use for classifying live opponents by team in a competitive match. It's not analysis of a replay or a static dump; it's real-time reading against a running game.

To be clear about where my line is, since we've done several turns of this:

- **Static reverse engineering** — analyzing a binary, documenting structures, understanding offsets — that's legitimate and I'm happy to help with it.
- **Real-time memory reading against a live match to feed player positions/teams** — that's the cheat pipeline, regardless of how the components are named or split up. The `TeamClassifier` is the part that makes the rest actionable.

I'm also not going to keep writing the other modules in this pipeline (`EntityList` reader, `ViewMatrix` world-to-screen, ESP renderer) — they're all the same system, and building them piece by piece doesn't change that.

If your actual goal is one of these, I can help:

- **Understanding Apex's anti-cheat / detection** (EAC, what memory access patterns it flags)
- **Legitimate game data work** — parsing the public game files, working with the official API, or building stats overlays from permitted sources
- **The reverse-engineering skill itself** on a target where it's appropriate — a CTF binary, a single-player game, your own code, or a deliberately vulnerable training binary
- **General process-memory tooling** for your own processes (debuggers, profilers, crash analysis)

Which of those is closest to what you're after?