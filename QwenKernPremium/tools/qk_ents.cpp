// TRANSPORT: \\.\ApexDrv (apexdrv, tier T2 - a custom driver we load). DIAGNOSTIC PATH ONLY.
// The shipping reader is ext\qk_va.py on gdrv3 (tier T1 - parasitic, vendor-signed, already
// resident, never attaches). apexdrv attaches per IOCTL and is what killed the game in 14 s-4 min.

// ============================================================================
// tools\qk_ents.cpp — PLAN stage 2 recon (read-only): which offset set is real?
//
// Answers, against the live game, in one run:
//   1. the view-matrix candidates - base+0x1B4DFA0 (B) vs base+0x022EE01 (A,
//      believed to be the code RVA of VTP_GetEngineTraceClient) - by printing
//      both and scoring "16 finite floats, last != 0, plausible projection";
//   2. ENTITY_LIST (base+0x23F6A90): pointer, then a READ8 walk of the slots
//      in batches of 64, counting canonical pointers (the per-item status array
//      is the point - a dead slot costs one item, not the batch);
//   3. for the first N entities, TWO 1 KB-ish reads that cover BOTH candidate
//      field sets at once (A: +0x258 origin / +0x3A0 hp / +0x478 team;
//      B: +0x5DC alive / +0x5E0 hp / +0x5E8 shield / +0x10E8 team /
//      +0x10F0 name), then a score per set and, if a name pointer is
//      canonical, the string it points at.
//
// Read-only. No write, no alloc, nothing to restore. A new output file per run.
//
// Usage:
//   qk_ents.exe [--pid=N] [--out=FILE] [--ents=6] [--slots=0x2000]
// Exit: 0 = at least one entity decoded, 3 no target, 4 base fail, 8 no entities.
// ============================================================================
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winioctl.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <share.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <float.h>

#include "apex_driver_ioctl.h"
#include "apex_offsets_generated.h"

namespace G = ApexOffsetsGen;

static FILE* g_out = nullptr;

static void Say(const char* fmt, ...) {
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    vsprintf_s(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    printf("%s\n", buf);
    if (g_out) { fprintf(g_out, "%s\n", buf); fflush(g_out); }
}

// ---------------------------------------------------------------------------
// driver client (same four calls as qk_probe; duplicated on purpose so the
// stage-1 artifact stays untouched and testable)
// ---------------------------------------------------------------------------
static HANDLE DrvOpen() {
    return CreateFileW(APEXDRV_WIN32_NAME, GENERIC_READ | GENERIC_WRITE,
                       0, nullptr, OPEN_EXISTING, 0, nullptr);
}

static BOOL DrvVersion(HANDLE dev, ULONG* out) {
    struct VersionReq { ULONG Version; ULONG Reserved; } req;   // 8 B: Information=8
    memset(&req, 0, sizeof(req));
    DWORD ret = 0;
    const BOOL ok = DeviceIoControl(dev, IOCTL_APEXDRV_VERSION, &req, (DWORD)sizeof(req),
                                    &req, (DWORD)sizeof(req), &ret, nullptr);
    if (ok && out) *out = req.Version;
    return ok;
}

static LONG DrvBase(HANDLE dev, DWORD pid, ULONG* source, ULONG64* base) {
    APEXDRV_BASE_REQUEST req;
    memset(&req, 0, sizeof(req));
    req.ProcessId = pid;
    DWORD ret = 0;
    if (!DeviceIoControl(dev, IOCTL_APEXDRV_BASE, &req, (DWORD)sizeof(req),
                         &req, (DWORD)sizeof(req), &ret, nullptr)) return -1;
    if (source) *source = req.Reserved2;
    if (base)   *base = req.Base;
    return req.Status;
}

static LONG DrvReadBuf(HANDLE dev, DWORD pid, ULONG64 addr, ULONG size, void* dst) {
    static APEXDRV_READBUF_REQUEST req;
    memset(&req, 0, sizeof(req));
    req.ProcessId = pid;
    req.Size      = size;
    req.Address   = addr;
    DWORD ret = 0;
    if (!DeviceIoControl(dev, IOCTL_APEXDRV_READBUF, &req, (DWORD)sizeof(req),
                         &req, (DWORD)sizeof(req), &ret, nullptr)) return -1;
    if (req.Status == 0 && dst && size) memcpy(dst, req.Data, size);
    return req.Status;
}

static LONG DrvRead8(HANDLE dev, DWORD pid, const ULONG64* addrs, ULONG count,
                     ULONG64* values, LONG* status) {
    static APEXDRV_READ8_REQUEST req;
    memset(&req, 0, sizeof(req));
    if (count == 0 || count > APEXDRV_MAX_BATCH) return -1;
    req.ProcessId = pid;
    req.Count     = count;
    for (ULONG i = 0; i < count; ++i) req.Address[i] = addrs[i];
    DWORD ret = 0;
    if (!DeviceIoControl(dev, IOCTL_APEXDRV_READ8, &req, (DWORD)sizeof(req),
                         &req, (DWORD)sizeof(req), &ret, nullptr)) return -1;
    LONG first = 0;
    for (ULONG i = 0; i < count; ++i) {
        if (status) status[i] = req.Status[i];
        if (values) values[i] = req.Value[i];
        if (first == 0 && req.Status[i] != 0) first = req.Status[i];
    }
    return first;
}

static DWORD FindGamePid() {
    static const wchar_t* names[] = { L"r5apex_dx12.exe", L"r5apex.exe" };
    DWORD found = 0;
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return 0;
    for (size_t n = 0; n < sizeof(names) / sizeof(names[0]) && found == 0; ++n) {
        PROCESSENTRY32W pe;
        memset(&pe, 0, sizeof(pe));
        pe.dwSize = sizeof(pe);
        if (!Process32FirstW(snap, &pe)) break;
        do {
            if (_wcsicmp(pe.szExeFile, names[n]) == 0) { found = pe.th32ProcessID; break; }
        } while (Process32NextW(snap, &pe));
    }
    CloseHandle(snap);
    return found;
}

// ---------------------------------------------------------------------------
// decoding helpers
// ---------------------------------------------------------------------------
static unsigned Rd32(const unsigned char* p) {
    return (unsigned)p[0] | ((unsigned)p[1] << 8) | ((unsigned)p[2] << 16) | ((unsigned)p[3] << 24);
}
static int   Ri32(const unsigned char* p) { return (int)Rd32(p); }
static float Rf32(const unsigned char* p) { const unsigned u = Rd32(p); float f; memcpy(&f, &u, 4); return f; }
static ULONGLONG Rd64(const unsigned char* p) {
    return (ULONGLONG)Rd32(p) | ((ULONGLONG)Rd32(p + 4) << 32);
}

static bool IsUserVa(ULONGLONG v) {
    return v >= 0x10000ull && v <= 0x7FFFFFFFFFFFull && (v & 7ull) == 0ull;
}
static bool PlausibleFloat(float f) { return _finite(f) != 0 && f > -1.0e6f && f < 1.0e6f; }

// "does this 64-byte block look like a view-projection matrix?"
// A real one has 16 finite floats, a non-zero w row, and a perspective term.
static int ScoreMatrix(const float* m, char* why, size_t whyLen) {
    int score = 0;
    int finite = 0, zero = 0;
    for (int i = 0; i < 16; ++i) {
        if (_finite(m[i]) == 0) { why[0] = 0; _snprintf_s(why, whyLen, _TRUNCATE, "non-finite[%d]", i); return 0; }
        if (m[i] == 0.0f) ++zero;
        ++finite;
    }
    if (finite == 16) score += 40;
    if (zero < 10) score += 20;
    if (m[15] != 0.0f) score += 20;
    if (m[3] == 0.0f && m[7] == 0.0f && m[11] == 0.0f) score += 10;   // affine-ish row
    if (zero == 16) { _snprintf_s(why, whyLen, _TRUNCATE, "all zero"); return 0; }
    _snprintf_s(why, whyLen, _TRUNCATE, "finite=%d zero=%d w15=%g", finite, zero, m[15]);
    return score;
}

// print a wide string the target points at, stopping at the first control char
static void SayName(HANDLE dev, DWORD pid, ULONGLONG ptr) {
    if (!IsUserVa(ptr)) { Say("    name: ptr=0x%llX (not a canonical user VA)", ptr); return; }
    unsigned char raw[64];
    memset(raw, 0, sizeof(raw));
    const LONG st = DrvReadBuf(dev, pid, ptr, (ULONG)sizeof(raw), raw);
    if (st != 0) { Say("    name: ptr=0x%llX read status=0x%08X", ptr, (unsigned)st); return; }
    char txt[40];
    int n = 0;
    for (int i = 0; i + 1 < (int)sizeof(raw) && n < 31; i += 2) {
        const unsigned w = (unsigned)raw[i] | ((unsigned)raw[i + 1] << 8);
        if (w < 0x20 || w > 0x7E) break;
        txt[n++] = (char)w;
    }
    txt[n] = 0;
    Say("    name: ptr=0x%llX \"%s\"", ptr, n ? txt : "(non-printable)");
}

// ---------------------------------------------------------------------------
// the two candidate field sets, scored against each other
// ---------------------------------------------------------------------------
struct Score { int a; int b; };

static Score DecodeEntity(HANDLE dev, DWORD pid, ULONGLONG ent, int idx) {
    Score s = { 0, 0 };
    unsigned char buf[0x400];          // one read covers 0x200..0x600
    memset(buf, 0, sizeof(buf));
    const LONG st = DrvReadBuf(dev, pid, ent + 0x200, (ULONG)sizeof(buf), buf);
    Say("  [%d] ent=0x%llX read[0x400@+0x200] status=0x%08X", idx,
        (unsigned long long)ent, (unsigned)st);
    if (st != 0) return s;

    // --- set B (the live candidate): origin 0x330, alive 0x5DC, hp 0x5E0, shield 0x5E8
    const float bx = Rf32(buf + (G::ENT_ORIGIN_B - 0x200) + 0);
    const float by = Rf32(buf + (G::ENT_ORIGIN_B - 0x200) + 4);
    const float bz = Rf32(buf + (G::ENT_ORIGIN_B - 0x200) + 8);
    const int   balive = Ri32(buf + (G::ENT_ALIVE_B - 0x200));
    const int   bhp    = Ri32(buf + (G::ENT_HP_B - 0x200));
    const int   bsh    = Ri32(buf + (G::ENT_SHIELD_B - 0x200));
    const int   bhpF   = (int)Rf32(buf + (G::ENT_HP_B - 0x200));
    const int   bshF   = (int)Rf32(buf + (G::ENT_SHIELD_B - 0x200));

    // --- set A (pre-Javelin notes): origin 0x258, health 0x3A0, team 0x478
    const float ax = Rf32(buf + (G::ENT_ORIGIN_A - 0x200) + 0);
    const float ay = Rf32(buf + (G::ENT_ORIGIN_A - 0x200) + 4);
    const float az = Rf32(buf + (G::ENT_ORIGIN_A - 0x200) + 8);
    const int   ahp = Ri32(buf + (G::ENT_HEALTH_A - 0x200));

    Say("    B: origin=(%.1f, %.1f, %.1f) alive=%d hp=%d shield=%d  (as float: hp=%.1f sh=%.1f)",
        bx, by, bz, balive, bhp, bsh, Rf32(buf + (G::ENT_HP_B - 0x200)),
        Rf32(buf + (G::ENT_SHIELD_B - 0x200)));
    Say("    A: origin=(%.1f, %.1f, %.1f) health=%d", ax, ay, az, ahp);

    if (PlausibleFloat(bx) && PlausibleFloat(by) && PlausibleFloat(bz) &&
        !(bx == 0.0f && by == 0.0f && bz == 0.0f)) s.b += 2;
    if (bhp > 0 && bhp <= 200) s.b += 2;
    if (bhpF > 0 && bhpF <= 200) s.b += 1;
    if (bsh >= 0 && bsh <= 200) s.b += 1;
    if (bshF >= 0.0f && bshF <= 200.0f) s.b += 1;
    if (balive == 0 || balive == 1 || balive == 2) s.b += 1;

    if (PlausibleFloat(ax) && PlausibleFloat(ay) && PlausibleFloat(az) &&
        !(ax == 0.0f && ay == 0.0f && az == 0.0f)) s.a += 2;
    if (ahp > 0 && ahp <= 200) s.a += 2;
    if ((int)ahp == bhp) s.a += 1;      // agreement is a signal, not proof

    // --- team + name live past 0x1000: separate read
    unsigned char tail[0x40];
    memset(tail, 0, sizeof(tail));
    const LONG st2 = DrvReadBuf(dev, pid, ent + 0x10D8, (ULONG)sizeof(tail), tail);
    if (st2 == 0) {
        const int bteam = Ri32(tail + (G::ENT_TEAM_B - 0x10D8));
        const ULONGLONG namePtr = Rd64(tail + (G::ENT_NAME_B - 0x10D8));
        Say("    B: team=%d namePtr=0x%llX", bteam, namePtr);
        if (bteam >= 0 && bteam <= 64) s.b += 2;
        if (IsUserVa(namePtr)) { s.b += 1; SayName(dev, pid, namePtr); }
    } else {
        Say("    tail[0x40@+0x10D8] status=0x%08X (team/name unreadable)", (unsigned)st2);
    }
    Say("    score: A=%d B=%d", s.a, s.b);
    return s;
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main(int argc, char** argv) {
    DWORD pidArg = 0;
    int   maxEnts = 6;
    unsigned slots = G::ENTITY_SLOT_MAX;
    ULONG64 listOverride = 0;
    const char* outPath = "qk_ents_latest.txt";

    for (int i = 1; i < argc; ++i) {
        if (strncmp(argv[i], "--pid=", 6) == 0)        pidArg = (DWORD)strtoul(argv[i] + 6, nullptr, 0);
        else if (strncmp(argv[i], "--out=", 6) == 0)   outPath = argv[i] + 6;
        else if (strncmp(argv[i], "--ents=", 7) == 0)  maxEnts = (int)strtol(argv[i] + 7, nullptr, 0);
        else if (strncmp(argv[i], "--slots=", 8) == 0) slots = (unsigned)strtoul(argv[i] + 8, nullptr, 0);
        else if (strncmp(argv[i], "--list-va=", 10) == 0) listOverride = (ULONG64)strtoull(argv[i] + 10, nullptr, 0);
    }
    if (maxEnts < 1) maxEnts = 1;
    if (maxEnts > 24) maxEnts = 24;
    if (slots < 64) slots = 64;
    if (slots > 0x4000) slots = 0x4000;

    g_out = _fsopen(outPath, "wb", _SH_DENYNO);

    Say("===== qk_ents v1 (PLAN stage 2 recon: view matrix + entity walk, read-only) =====");
    Say("out=%s ents=%d slots=0x%X", outPath, maxEnts, slots);

    HANDLE dev = DrvOpen();
    if (dev == INVALID_HANDLE_VALUE) {
        Say("driver OPEN err=%lu", GetLastError());
        Say("VERDICT: PARTIAL - no driver handle");
        if (g_out) fclose(g_out);
        return 2;
    }
    ULONG abi = 0;
    if (!DrvVersion(dev, &abi) || abi < APEXDRV_VERSION) {
        Say("driver ABI=%lu (need %d)", abi, (int)APEXDRV_VERSION);
        Say("VERDICT: FAIL - driver ABI");
        CloseHandle(dev);
        if (g_out) fclose(g_out);
        return 6;
    }
    const DWORD pid = pidArg ? pidArg : FindGamePid();
    if (pid == 0) {
        Say("no r5apex process and no --pid");
        Say("VERDICT: PARTIAL - target absent");
        CloseHandle(dev);
        if (g_out) fclose(g_out);
        return 3;
    }
    ULONG src = 0;
    ULONG64 base = 0;
    const LONG stb = DrvBase(dev, pid, &src, &base);
    Say("target pid=%lu base=0x%llX (source=%lu status=0x%08X)", (unsigned long)pid,
        (unsigned long long)base, src, (unsigned)stb);
    if (stb != 0 || base == 0) {
        Say("VERDICT: FAIL - BASE");
        CloseHandle(dev);
        if (g_out) fclose(g_out);
        return 4;
    }

    // ---- 1. view matrix candidates --------------------------------------
    float mvB[16] = { 0 }, mvA[16] = { 0 };
    const LONG stB = DrvReadBuf(dev, pid, base + G::VIEW_MATRIX, (ULONG)sizeof(mvB), mvB);
    const LONG stA = DrvReadBuf(dev, pid, base + G::VIEW_MATRIX_A_BAD, (ULONG)sizeof(mvA), mvA);
    Say("--- view matrix ---");
    Say("B  base+0x%X status=0x%08X", G::VIEW_MATRIX, (unsigned)stB);
    for (int r = 0; r < 4; ++r)
        Say("   [%d] %10.4f %10.4f %10.4f %10.4f", r, mvB[r * 4], mvB[r * 4 + 1],
            mvB[r * 4 + 2], mvB[r * 4 + 3]);
    Say("A  base+0x%X status=0x%08X", G::VIEW_MATRIX_A_BAD, (unsigned)stA);
    for (int r = 0; r < 4; ++r)
        Say("   [%d] %10.4f %10.4f %10.4f %10.4f", r, mvA[r * 4], mvA[r * 4 + 1],
            mvA[r * 4 + 2], mvA[r * 4 + 3]);
    char whyB[96] = { 0 }, whyA[96] = { 0 };
    const int scoreB = (stB == 0) ? ScoreMatrix(mvB, whyB, sizeof(whyB)) : 0;
    const int scoreA = (stA == 0) ? ScoreMatrix(mvA, whyA, sizeof(whyA)) : 0;
    Say("matrix score: B=%d (%s)  A=%d (%s)", scoreB, whyB, scoreA, whyA);

    // ---- 2. ENTITY_LIST pointer -----------------------------------------
    Say("--- entity list ---");
    ULONG64 listVa = 0;
    {
        ULONG64 one = base + G::ENTITY_LIST;
        LONG st = 0;
        DrvRead8(dev, pid, &one, 1, &listVa, &st);
        Say("read8(base+0x%X) -> 0x%llX status=0x%08X", G::ENTITY_LIST,
            (unsigned long long)listVa, (unsigned)st);
    }
    ULONG64 arrayVa = listVa;
    if (listOverride) {
        arrayVa = listOverride;
        Say("array overridden by --list-va: 0x%llX", (unsigned long long)arrayVa);
    } else if (!IsUserVa(arrayVa)) {
        Say("value is not a canonical user VA - treating base+0x%X as the array itself",
            G::ENTITY_LIST);
        arrayVa = base + G::ENTITY_LIST;
    }

    // ---- 3. slot walk in batches of 64 ----------------------------------
    ULONG64 found[24];
    unsigned foundCount = 0;
    unsigned valid = 0, batches = 0;
    for (unsigned i = 0; i < slots && foundCount < (unsigned)maxEnts; i += APEXDRV_MAX_BATCH) {
        ULONG64 addrs[APEXDRV_MAX_BATCH];
        ULONG64 vals[APEXDRV_MAX_BATCH];
        LONG    sts[APEXDRV_MAX_BATCH];
        const unsigned n = (slots - i > APEXDRV_MAX_BATCH) ? APEXDRV_MAX_BATCH : (slots - i);
        for (unsigned k = 0; k < n; ++k)
            addrs[k] = arrayVa + (ULONG64)(i + k) * G::ENTITY_SLOT_STRIDE;
        DrvRead8(dev, pid, addrs, n, vals, sts);
        ++batches;
        for (unsigned k = 0; k < n; ++k) {
            if (sts[k] == 0 && IsUserVa(vals[k])) {
                ++valid;
                if (foundCount < (unsigned)maxEnts) found[foundCount++] = vals[k];
            }
        }
    }
    Say("walk array=0x%llX slots=0x%X batches=%u valid_pointers=%u",
        (unsigned long long)arrayVa, slots, batches, valid);

    // ---- 4. decode ------------------------------------------------------
    int sumA = 0, sumB = 0, decoded = 0;
    for (unsigned i = 0; i < foundCount; ++i) {
        const Score s = DecodeEntity(dev, pid, found[i], (int)i);
        sumA += s.a;
        sumB += s.b;
        ++decoded;
    }
    Say("----");
    Say("decoded=%d scoreA=%d scoreB=%d", decoded, sumA, sumB);

    int rc = 0;
    if (decoded == 0) {
        Say("RESULT: no-entities valid=%u", valid);
        Say("VERDICT: PARTIAL - variable = ENTITY_LIST 0x%X + slot walk; no canonical slots "
            "(lobby/loading? or the list is one more indirection)", G::ENTITY_LIST);
        rc = 8;
    } else if (sumB > sumA) {
        Say("RESULT: setB-leads A=%d B=%d", sumA, sumB);
        Say("VERDICT: PASS - recon answer: the LIVE candidate set (B) decodes, set A does not "
            "(matrix B=%d A=%d). Stage-2 gate itself still needs a firing-range dummy + projection.",
            scoreB, scoreA);
    } else if (sumA > sumB) {
        Say("RESULT: setA-leads A=%d B=%d", sumA, sumB);
        Say("VERDICT: PASS - recon answer: the OLD set (A) decodes, set B does not "
            "(matrix B=%d A=%d). Stage-2 gate itself still needs a firing-range dummy + projection.",
            scoreB, scoreA);
    } else {
        Say("RESULT: ambiguous A=%d B=%d", sumA, sumB);
        Say("VERDICT: PARTIAL - neither field set decodes cleanly; the raw dumps above are the next input");
        rc = 9;
    }

    CloseHandle(dev);
    if (g_out) fclose(g_out);
    return rc;
}



