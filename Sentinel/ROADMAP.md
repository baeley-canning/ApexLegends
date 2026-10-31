# Sentinel — Roadmap: Anti-Cheat & Windows Kernel Security Engineering

**Goal:** convert low-level Windows / reverse-engineering skill into paid,
*defensive* security work. This file is the accountability artifact — every phase
has a deliverable and a way to prove it is done.

---

## 1. Target roles
- Anti-Cheat Engineer (Riot Vanguard, BattlEye, EAC/Epic, Activision Ricochet, Tencent ACE, Irdeto/Denuvo)
- Game Security / Gameplay Integrity Engineer (EA SPEAR, Ubisoft, Bungie, Epic, miHoYo, Krafton)
- Windows Kernel Engineer — Detection / EDR (CrowdStrike, SentinelOne, Microsoft Defender, Elastic, Ent Security, Dream Security, Sophos, Trellix)
- Security Researcher — Anti-Cheat / Malware RE (vendors above + consultancies)

## 2. Market evidence (verified from live postings)
Riot Games, "Senior Anti-Cheat Engineer" (LA, REQ-0010290) — **required:**
C/C++ and x86/x64 assembly; Windows process internals (thread/process lifecycle,
virtual memory, handles/objects, security contexts, PE format, DLL loading and the
Windows loader); hands-on RE of packed/protected/obfuscated binaries; practical
kernel + driver model with demonstrated *production-grade kernel-mode driver*
development and debugging. **Desired:** familiarity with modern cheat techniques
and anti-cheat evasions; hypervisors, DKOM, EPT manipulation, vulnerable drivers,
hardware-assisted cheats; runtime integrity verification, behavioral detection,
client attestation.

EA Security (SPEAR), "Senior Reverse Engineer – Anti-Cheat": reverse-engineer
obfuscated user-mode cheats across PC, mobile and console.

The EDR market wants the *same* skills under a different label: "design and ship the
kernel- and user-mode components that observe process, file, registry, network and
identity activity" (Ent Security); "kernel drivers that power threat detection"
(Dream Security, DataArt).

**Takeaway:** one skill set, two markets. Games when they hire; EDR always.

## 3. Skill stack (tiered against the real JD)
**MUST HAVE**
- C++17/20 and C; MSVC + WinDbg fluency; ability to read x86/x64 assembly
- User-mode internals: PE format, PEB/TEB, the loader, VADs, handles, tokens
- Kernel: IRPs, IOCTLs, WDM/KMDF, notification callbacks, minifilters
- Reverse engineering: IDA/Ghidra/x64dbg, static + dynamic, unpacking, obfuscation
- Detection engineering: turning a technique into a signature-less, low-FP detector

**STRONG DIFFERENTIATOR**
- Hypervisors: VT-x/AMD-V, EPT/NPT, VBS/HVCI, EPT-based monitoring
- DMA threat awareness (IOMMU) and vulnerable-driver (BYOVD) detection
- Behavioral / telemetry detection, server-side anti-cheat, client attestation
- Obfuscation and binary hardening (the "obfuscation tooling" surface in the JD)

**NICE TO HAVE**
- Mobile (Android/iOS integrity) and console security; Rust/C# tooling; Python automation

## 4. Resource canon
Books: *Windows Internals 7e Pt1+Pt2* (Russinovich/Ionescu) · *Windows Kernel
Programming 2e* (Yosifovich) · *Practical Reverse Engineering* (Dang) ·
*Practical Malware Analysis* (Sikorski) · *Rootkits & Bootkits* (Matrosov) ·
*The IDA Pro Book* (Eagle)
Courses (free): OpenSecurityTraining2 — Arch1001 (x86-64 asm), Arch1002 (asm to C),
"Advanced x86: Virtualization with Intel VT-x"; Microsoft Learn driver-dev path
Tooling: WinDbg, x64dbg, IDA Free/Ghidra, PE-bear, CFF Explorer, System Informer,
Object Explorer, WinObj, Procmon, Hyperplatform (tandasat), hvpp

## 5. Phase plan
**Phase 0 — Foundations (wks 1–6).** Read asm and C fluently; know PE + process internals cold.
*Build:* a PEB/LDR module walker in C++ using **no** loader APIs.
*Prove:* dump a live process's real module list from the PEB and diff it against a tool.

**Phase 1 — User-mode internals + RE (wks 7–18).** Reverse a real binary end-to-end.
*Build:* (a) a user-mode service + driver pair; (b) a technique-analysis tool for published cheat samples (a report — not a working cheat).
*Prove:* three public writeups, at least one on unpacking an obfuscated binary.

**Phase 2 — Kernel drivers (wks 19–34) ← the hiring gate.** Ship a production-quality signed driver.
*Build:* SENTINEL process integrity monitor (see `docs/PROJECT-01-sentinel.md`).
*Prove:* driver loads/unloads cleanly, detects a manual-mapped driver and unbacked exec memory, has automated tests, is signed.

**Phase 3 — Advanced detection (wks 35–52).** Cover the "desired quals": hypervisor/EPT, DKOM, BYOVD.
*Build:* (a) a BYOVD detector; (b) a minimal VT-x hypervisor or EPT-hook detector.
*Prove:* public research post + a conference talk submission.

**Phase 4 — Career (from wk 26, in parallel).** Get hired: publish the portfolio, secure 2 referrals, apply to 20+ roles, run mock interviews.

## 6. Portfolio — what actually gets you hired
| # | Artifact | Phase |
|---|----------|-------|
| P1 | SENTINEL kernel integrity monitor | 2 |
| P2 | Cheat-technique analysis series (5+ posts) | 1 |
| P3 | Unpacking / obfuscation lab (writeup + tool) | 1 |
| P4 | BYOVD vulnerability detector | 3 |
| P5 | VT-x hypervisor / EPT monitor | 3 |

Each gets its own repo with a README, tests, and an accompanying blog post.

## 7. Credentials (optional — portfolio outweighs certs in this field)
- OffSec **OSED** (EXP-301) then **OSEE** (EXP-401): closest fit to the work
- SANS **FOR610 GREM** (RE/malware) and **SEC760** (advanced exploit dev)
- A CS degree helps at big studios; a strong portfolio substitutes at vendors

## 8. Where to apply + compensation
Vendors: Riot, Epic/EAC, BattlEye, EA SPEAR, Activision, Tencent ACE, Irdeto, Valve, Ubisoft, Bungie, Krafton, miHoYo
EDR/infra: CrowdStrike, SentinelOne, Microsoft, Elastic, Palo Alto, Trend, Ent Security, Dream Security, DataArt, Sophos, Trellix
Boards: company sites, LinkedIn, BuiltIn, Indeed; use levels.fyi for comp
Comp (rough, US, senior): anti-cheat / kernel security ~$150k–$260k+ total comp; EDR kernel roles similar; consulting higher. Verify per company on levels.fyi.

## 9. Communities & conferences (this is the "desired qualification")
Communities: OSR (Windows System Software) mailing list, r/ReverseEngineering, r/AskNetsec, Microsoft driver-dev Q&A, Secret Club
Conferences: DEF CON (game/anti-cheat talks), Black Hat, OffensiveCon, REcon, Zer0Con, BlueHat IL, CanSecWest, USENIX WOOT, GDC anti-cheat track
Submitting a talk by Phase 3 is the single strongest hiring signal available to you.

## 10. Accountability system
- **Weekly:** 10–15 focused hours; 1 code commit; 1 written note (blog draft or notebook entry)
- **Biweekly:** 30-minute self-review against this document; log what blocked you
- **Monthly:** ship one phase deliverable; update the status table in `README.md`
- Log *every* artifact in `README.md` — that table becomes your CV

## 11. Your unfair advantage
You already want to understand how cheats work. Riot lists that as a **desired
qualification**. The only thing that changes on this path is the output artifact:
analysis and detection instead of a working cheat. Same study, same skills, opposite
product. Ship the *detector* and the *writeup* — never the cheat.

## 12. Next 7 days
1. Confirm toolchain: VS 2022 + WDK, WinDbg, x64dbg, Ghidra → get a hello-world KMDF driver to load
2. Read *Windows Internals* Pt1 ch. 1–3 so process/thread/memory is solid
3. Review `docs/PROJECT-01-sentinel.md` and adjust scope to your VM setup
4. Write the first entry in the weekly log in `README.md`

