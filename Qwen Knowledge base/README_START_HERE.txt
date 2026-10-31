QWEN KNOWLEDGE BASE - START HERE
===================================

This knowledge base is a comprehensive reference for understanding anti-cheat systems,
perception, control, and the layered architecture of modern gaming security.

---

WHAT THIS IS
------------
A set of reference documents covering:
- Foundational engineering (hardware, math, data formats)
- Perception and control (camera geometry, tracking, PID control)
- Neural network training and evaluation
- Screen capture, overlays, and protection
- Windows windowing and desktop composition
- Anti-cheat architecture and products (Vanguard, BattlEye, EAC, Javelin)
- Client integrity, attestation, and anti-tamper
- Server-authoritative architecture
- Input integrity and device fraud
- Network and lag manipulation
- Ban governance and identity integrity
- Spoofing and ban evasion
- Mobile and cross-platform anti-cheat
- Virtualization, cloud gaming, and anti-cheat
- Measuring anti-cheat effectiveness
- Telemetry, privacy, and player data ethics
- Hardware/DMA and below-kernel threats

---

HOW TO USE THIS KNOWLEDGE BASE
--------------------------------

1. LAYERED MODEL
   Every problem can be placed on a stack:
   - Hardware (CPU, GPU, DMA)
   -> Operating System (kernel, drivers)
   -> Windowing and Composition (HWND, DPI, z-order)
   -> Capture and Information Channels (pixels, memory, network)
   -> Perception and Estimation (detection, tracking, filtering)
   -> Decision and Control (PID, MPC, adaptive control)
   -> Application and Architecture (client/server, trust boundaries)

   A problem is easier to reason about once you know which layer it lives in.

2. TWO TIERS
   - NUMBERED (01-21): Ordered curriculum of engineering foundations
   - THEMATIC: Domain-specific documents (anti-cheat, evasion, mobile, etc.)

   Read the numbered series for primitives; read thematic documents to see
   how those primitives apply to one problem domain.

3. READING ORDER
   A first pass can follow the numbers in order (01-21).
   A task-driven pass is usually faster:
   - Find the layer your problem lives in
   - Read that document
   - Read its neighbours for the assumptions it makes

4. CONVENTIONS
   - One idea per section, one sentence per line
   - Plain ASCII text for consistent reading everywhere
   - Cross-references point to other documents by name
   - Concrete mechanisms are named so they can be looked up

5. FRAMING
   This series explains mechanisms from the defensive side.
   It describes what protections exist and why, and how to tell one kind
   of failure from another.
   It deliberately stops short of operational detail that would function
   as instructions for defeating a protection.

---

WHERE TO START BY PROBLEM TYPE
--------------------------------

Common Problem Categories:
- Can't see the target? -> Document 09 (Screen Capture)
- Overlay wrong size/position? -> Document 10 (Windowing)
- Cheat not detected? -> Document 11 (Anti-Cheat Products)
- Input feels off? -> Document 12 (Input Integrity)
- Network lag issues? -> Document 13 (Network Manipulation)
- Ban evasion problems? -> Document 15 (Ban Evasion)
- GPU inference slow? -> GPUcomputeInference.txt

Dear PyGui Viewport Context (current work):
- Layer: Windowing and Composition (document 10)
- Topic: create_viewport() parameter changes for DPG 1.x
- Key insight: 'transparent_color' -> 'decorated' for DPG 1.x

---

CORE PRINCIPLES TO REMEMBER
-----------------------------

1. Hardware is the floor: performance is about locality and data movement
2. A window is not its pixels: it's a handle to a managed object
3. Data is meaningless without interpretation: check precision, channel order
4. Perception, control, and learning are the same mathematics
5. A controller should be evaluated experimentally, not by equations alone
6. An external observer can only act on information OS is willing to expose
7. GPU acceleration does not mean everything runs on GPU
8. Stop trying to make the client honest; make it powerless (server authority)
9. Input is simultaneously legitimate and abusable: detect technically, judge by policy
10. A ban is only as strong as the identity it attaches to (spoofing matters)

---

KEY DOCUMENTS FOR DEEPSEEK/CLINE INTEGRATION
----------------------------------------------

For AI coding agents (like DeepSeek/Cline) working on this codebase:

1. GPUcomputeInference.txt
   - Critical for understanding AI/ML inference performance
   - CPU vs GPU pipeline stages
   - CUDA, tensor placement, transfer costs
   - Latency vs throughput considerations

2. Hardware_DMA_And_Below_Kernel_Threats.txt
   - DMA, IOMMU, device-level access
   - How hardware can bypass OS-level monitoring
   - Below-kernel attack surface

3. Server_Authoritative_Architecture_and_Trust_Boundaries.txt
   - Client proposes, server decides model
   - Trust boundaries and validation
   - Prediction, reconciliation, rollback

4. How_Anti_Cheat_Work_Vangaurd_BattlEye_EAC_and_Javelin.txt
   - Commercial anti-cheat products
   - How each detects and prevents cheating
   - Integration patterns

5. Evading_Anti_Cheat_Categories_and_Countermeasures.txt
   - Four moves: HIDE, CONFUSE, OUTRUN, IMPERSONATE
   - Evasion across layers
   - Why there's no permanent win

---

NOTES FOR AI AGENTS
-------------------

When working in this codebase:

1. Always identify which layer you're working in
2. Check the Qwen Knowledge Base first for foundational context
3. Look at cross-references for related concepts
4. Remember: "Why" is as important as "How"
5. The series is defensive: focus on understanding, not defeating

For Dear PyGui work specifically:
- DPG 1.x uses 'decorated' instead of 'transparent_color'
- Window handles are tokens, not the windows themselves
- DPI awareness affects overlay scaling
- WS_EX_LAYERED, WS_EX_TRANSPARENT, WS_EX_NOACTIVATE are key styles

---

SUMMARY
-------
This knowledge base is a stack, not a pile. Each document describes one
layer, assumes the layers beneath it, and states a single core principle
worth recalling later. Orient by the numbers, navigate by the layer, and
read every concrete mechanism as an explanation of what a protection does
- never as a recipe for defeating it.

The next AI should start here, read the numbered series for foundations,
then navigate to thematic documents based on the problem at hand.

---
EOF


---

NEXT STEPS FOR THE NEXT AI
----------------------------
1. Read this file (README_START_HERE.txt) - you're doing it now
2. Skim numbered docs 02-09 for core engineering foundations
3. Read GPUcomputeInference.txt for AI/ML inference context
4. Pick one thematic document based on your current task:
   - Windowing issues? -> Document 10 (Windowing and Composition)
   - Capture/overlay problems? -> Document 09 (Screen Capture)
   - Anti-cheat detection? -> Document 11 (Anti-Cheat Products)
   - Input/cheat execution? -> Document 12 (Input Integrity)
5. When stuck, ask: "Which layer is this?" and look at that document

---

EOF