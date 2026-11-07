// ============================================================================
// tools\qk_hunt.cpp — PLAN stage 2, step 2: find the MOVED offsets (read-only).
//
// qk_ents proved the static table is stale for the 2026-10-24 build: every read
// succeeds (pages are mapped) but the values are garbage - base+0x23F6A90 holds
// 0x5E2C1480475A9C4 (not a pointer) and neither matrix candidate holds a matrix.
// So instead of trusting an offset, search a window around it:
//
//   1. MATRIX: read --win bytes around each anchor, slide by 4, score every
//      16-float window with a STRICT test (finite, |v| <= 1e5, >= 8 non-zero,
//      affine w-row or a perspective term).  Print the best few, with offsets.
//   2. ENTITY LIST: read --list-win bytes around the anchor, collect every
//      8-aligned canonical user pointer, walk 4 slots at each (READ8 batch),
//      and keep the pointer whose slots are themselves canonical AND mapped.
//
// Read-only. Nothing to restore. One output file per run.
//
// Usage: qk_hunt.exe [--pid=N] [--out=FILE] [--win=0x8000] [--list-win=0x2000]
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

static unsigned Rd32(const unsigned char* p) {
    return (unsigned)p[0] | ((unsigned)p[1] << 8) | ((unsigned)p[2] << 16) | ((unsigned)p[3] << 24);
}
static float Rf32(const unsigned char* p) { const unsigned u = Rd32(p); float f; memcpy(&f, &u, 4); return f; }
static ULONGLONG Rd64(const unsigned char* p) {
    return (ULONGLONG)Rd32(p) | ((ULONGLONG)Rd32(p + 4) << 32);
}
static bool IsUserVa(ULONGLONG v) {
    return v >= 0x10000ull && v <= 0x7FFFFFFFFFFFull && (v & 7ull) == 0ull;
}

// ---------------------------------------------------------------------------
// driver client
// ---------------------------------------------------------------------------
static LONG Read(HANDLE dev, DWORD pid, ULONG64 addr, ULONG size, void* dst) {
    static APEXDRV_READBUF_REQUEST req;
    memset(&req, 0, sizeof(req));
    req.ProcessId = pid; req.Size = size; req.Address = addr;
    DWORD ret = 0;
    if (!DeviceIoControl(dev, IOCTL_APEXDRV_READBUF, &req, (DWORD)sizeof(req),
                         &req, (DWORD)sizeof(req), &ret, nullptr)) return -1;
    if (req.Status == 0 && dst && size) memcpy(dst, req.Data, size);
    return req.Status;
}

static LONG Read8(HANDLE dev, DWORD pid, const ULONG64* addrs, ULONG count,
                  ULONG64* values, LONG* status) {
    static APEXDRV_READ8_REQUEST req;
    memset(&req, 0, sizeof(req));
    if (count == 0 || count > APEXDRV_MAX_BATCH) return -1;
    req.ProcessId = pid; req.Count = count;
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
// matrix scoring: strict enough that garbage cannot pass
// ---------------------------------------------------------------------------
static int ScoreMatrix(const float* m) {
    for (int i = 0; i < 16; ++i) {
        if (_finite(m[i]) == 0) return 0;
        const float a = (m[i] < 0.0f) ? -m[i] : m[i];
        if (a > 1.0e5f) return 0;                 // 1e23 was the qk_ents garbage
    }
    static const int k3x3[9] = { 0, 1, 2, 4, 5, 6, 8, 9, 10 };
    // row- AND column-major view-projections both end with +-1 here
    const float a15 = (m[15] < 0.0f) ? -m[15] : m[15];
    if (a15 < 0.99f || a15 > 1.01f) return 0;
    int small = 0;
    for (int i = 0; i < 9; ++i) {
        const float v = m[k3x3[i]];
        const float a = (v < 0.0f) ? -v : v;
        if (a <= 2.0f) ++small;
    }
    if (small < 6) return 0;
    static const int kT[6] = { 12, 13, 14, 3, 7, 11 };
    int big = 0;
    for (int i = 0; i < 6; ++i) {
        const float v = m[kT[i]];
        const float a = (v < 0.0f) ? -v : v;
        if (a > 100.0f && a < 1.0e5f) ++big;
    }
    if (big == 0) return 0;
    int s = 30 + small * 2 + (big > 1 ? 5 : 0);
    return (s > 100) ? 100 : s;
}

static void PrintMat(const float* m, const char* tag, ULONG64 at) {
    Say("%s at 0x%llX", tag, (unsigned long long)at);
    for (int r = 0; r < 4; ++r)
        Say("   [%d] %11.4f %11.4f %11.4f %11.4f", r, m[r * 4], m[r * 4 + 1],
            m[r * 4 + 2], m[r * 4 + 3]);
}

// ---------------------------------------------------------------------------
// scan a window for matrix windows; returns the best score (0 = none)
// ---------------------------------------------------------------------------
struct Hit { ULONG64 at; int score; };
static Hit g_best[3];

static void RememberHit(ULONG64 at, int score) {
    for (int i = 0; i < 3; ++i) {
        if (score > g_best[i].score) {
            for (int k = 2; k > i; --k) g_best[k] = g_best[k - 1];
            g_best[i].at = at;
            g_best[i].score = score;
            return;
        }
    }
}

static int ScanMatrix(HANDLE dev, DWORD pid, ULONG64 anchorVa, ULONG64 win) {
    static unsigned char buf[0x10000];
    const ULONG64 start = anchorVa - (win / 2);
    unsigned got = 0;
    for (ULONG64 off = 0; off < win; off += 0x1000) {
        const ULONG n = (ULONG)((win - off > 0x1000) ? 0x1000 : (win - off));
        const LONG st = Read(dev, pid, start + off, n, buf + off);
        if (st != 0) { Say("  window read +0x%llX status=0x%08X (skipped)", off, (unsigned)st); continue; }
        got += n;
    }
    if (got < 64) return 0;
    for (int i = 0; i < 3; ++i) { g_best[i].at = 0; g_best[i].score = 0; }

    int best = 0;
    for (ULONG64 off = 0; off + 64 <= win; off += 4) {
        float m[16];
        for (int k = 0; k < 16; ++k) m[k] = Rf32(buf + off + (ULONG64)k * 4);
        const int s = ScoreMatrix(m);
        if (s > 0) { RememberHit(start + off, s); if (s > best) best = s; }
    }
    Say("  window 0x%llX..0x%llX (%u B) best=%d", (unsigned long long)start,
        (unsigned long long)(start + win), got, best);
    return best;
}

// ---------------------------------------------------------------------------
// find a pointer array near the anchor: canonical slots whose slot0 is mapped
// ---------------------------------------------------------------------------
static ULONGLONG ScanList(HANDLE dev, DWORD pid, ULONG64 anchorVa, ULONG64 win) {
    static unsigned char buf[0x4000];
    const ULONG64 start = anchorVa - (win / 2);
    if (win > sizeof(buf)) win = sizeof(buf);
    unsigned gotBytes = 0;
    for (ULONG64 off = 0; off < win; off += 0x1000) {
        // READBUF accepts 1..0x1000 per call; a larger Size is a header violation
        // and the whole IRP fails (measured: a 0x2000 read returned 87).
        const ULONG n = (ULONG)((win - off > 0x1000) ? 0x1000 : (win - off));
        if (Read(dev, pid, start + off, n, buf + off) != 0) {
            Say("  list chunk +0x%llX unreadable", off);
            continue;
        }
        gotBytes += n;
    }
    if (gotBytes < 64) {
        Say("  list window unreadable");
        return 0;
    }
    int canonical = 0, candidates = 0;
    ULONGLONG winner = 0;
    for (ULONG64 off = 0; off + 8 <= win; off += 8) {
        const ULONGLONG v = Rd64(buf + off);
        if (!IsUserVa(v)) continue;
        ++canonical;
        if (candidates >= 8) continue;

        ULONG64 addrs[4] = { v, v + 8, v + 16, v + 24 };
        ULONG64 vals[4] = { 0, 0, 0, 0 };
        LONG    sts[4]  = { 0, 0, 0, 0 };
        Read8(dev, pid, addrs, 4, vals, sts);
        int slots = 0;
        for (int k = 0; k < 4; ++k) if (sts[k] == 0 && IsUserVa(vals[k])) ++slots;
        ++candidates;
        Say("  ptr@+0x%llX = 0x%llX  slots=%d/4  slot0=0x%llX st0=0x%08X",
            (unsigned long long)off, (unsigned long long)v, slots,
            (unsigned long long)vals[0], (unsigned)sts[0]);
        if (slots >= 2 && sts[0] == 0 && IsUserVa(vals[0])) {
            unsigned char peek[16];
            memset(peek, 0, sizeof(peek));
            if (Read(dev, pid, vals[0], 16, peek) == 0 && winner == 0) {
                winner = v;
                Say("    ^ CANDIDATE list: slot0 readable, first qwords %llX %llX",
                    (unsigned long long)Rd64(peek), (unsigned long long)Rd64(peek + 8));
            }
        }
    }
    Say("  canonical qwords in window: %d (%d probed)", canonical, candidates);
    return winner;
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main(int argc, char** argv) {
    DWORD pidArg = 0;
    int rc = 0;
    bool imageMode = false;
    ULONG64 win = 0x8000, listWin = 0x2000;
    const char* outPath = "qk_hunt_latest.txt";
    for (int i = 1; i < argc; ++i) {
        if (strncmp(argv[i], "--pid=", 6) == 0)           pidArg = (DWORD)strtoul(argv[i] + 6, nullptr, 0);
        else if (strcmp(argv[i], "--image") == 0)           imageMode = true;
        else if (strncmp(argv[i], "--out=", 6) == 0)      outPath = argv[i] + 6;
        else if (strncmp(argv[i], "--win=", 6) == 0)      win = (ULONG64)strtoull(argv[i] + 6, nullptr, 0);
        else if (strncmp(argv[i], "--list-win=", 11) == 0) listWin = (ULONG64)strtoull(argv[i] + 11, nullptr, 0);
    }
    if (win < 0x1000) win = 0x1000;
    if (win > 0x10000) win = 0x10000;
    if (listWin < 0x1000) listWin = 0x1000;
    if (listWin > 0x4000) listWin = 0x4000;

    g_out = _fsopen(outPath, "wb", _SH_DENYNO);
    Say("===== qk_hunt v1 (PLAN stage 2: find the MOVED offsets, read-only) =====");
    Say("out=%s win=0x%llX listWin=0x%llX", outPath,
        (unsigned long long)win, (unsigned long long)listWin);

    HANDLE dev = CreateFileW(APEXDRV_WIN32_NAME, GENERIC_READ | GENERIC_WRITE, 0,
                             nullptr, OPEN_EXISTING, 0, nullptr);
    if (dev == INVALID_HANDLE_VALUE) {
        Say("driver OPEN err=%lu", GetLastError());
        Say("VERDICT: PARTIAL - no driver");
        if (g_out) fclose(g_out);
        return 2;
    }
    const DWORD pid = pidArg ? pidArg : FindGamePid();
    if (pid == 0) {
        Say("no r5apex process and no --pid");
        Say("VERDICT: PARTIAL - target absent");
        CloseHandle(dev);
        if (g_out) fclose(g_out);
        return 3;
    }
    {
        APEXDRV_BASE_REQUEST b;
        memset(&b, 0, sizeof(b));
        b.ProcessId = pid;
        DWORD ret = 0;
        if (!DeviceIoControl(dev, IOCTL_APEXDRV_BASE, &b, (DWORD)sizeof(b), &b,
                             (DWORD)sizeof(b), &ret, nullptr) || b.Status != 0 || b.Base == 0) {
            Say("BASE failed status=0x%08X", (unsigned)b.Status);
            Say("VERDICT: FAIL - BASE");
            CloseHandle(dev);
            if (g_out) fclose(g_out);
            return 4;
        }
        const ULONG64 base = b.Base;
        Say("target pid=%lu base=0x%llX (source=%lu)", (unsigned long)pid,
            (unsigned long long)base, b.Reserved2);

        // ---- 0. optional: scan the WHOLE image for a matrix ----------------
        if (imageMode) {
            unsigned char hdr[0x100];
            ULONG sizeOfImage = 0;
            if (Read(dev, pid, base + 0x3C, 4, hdr) == 0) {
                const ULONG lf = Rd32(hdr);
                if (lf >= 0x40 && lf < 0x1000 &&
                    Read(dev, pid, base + lf, (ULONG)sizeof(hdr), hdr) == 0) {
                    sizeOfImage = Rd32(hdr + 0x50);
                }
            }
            Say("--- image scan: SizeOfImage=0x%X (%.1f MB), strict matrix test ---",
                sizeOfImage, sizeOfImage / 1048576.0);
            static unsigned char img[0x1000 + 64];
            memset(img, 0, sizeof(img));
            for (int i = 0; i < 3; ++i) { g_best[i].at = 0; g_best[i].score = 0; }
            ULONG64 off = 0;
            unsigned okChunks = 0, badChunks = 0;
            while (sizeOfImage && off < sizeOfImage) {
                const ULONG n = (sizeOfImage - off > 0x1000) ? 0x1000
                                                             : (ULONG)(sizeOfImage - off);
                memmove(img, img + 0x1000, 64);          // keep the tail for straddles
                if (Read(dev, pid, base + off, n, img + 64) != 0) {
                    ++badChunks;
                    off += 0x1000;
                    continue;
                }
                ++okChunks;
                const ULONG oStart = (off == 0) ? 64 : 0;
                for (ULONG o = oStart; o + 64 <= n + 64; o += 4) {
                    float m[16];
                    for (int k = 0; k < 16; ++k) m[k] = Rf32(img + o + (ULONG)k * 4);
                    const int s = ScoreMatrix(m);
                    if (s > 0) RememberHit(base + off - 64 + o, s);
                }
                if ((off & 0x1FFFFFF) == 0)
                    Say("  .. 0x%llX (ok=%u bad=%u best=%d)", (unsigned long long)off,
                        okChunks, badChunks, g_best[0].score);
                off += 0x1000;
            }
            Say("image scan done: ok=%u bad=%u chunks", okChunks, badChunks);
            for (int i = 0; i < 3; ++i) {
                if (g_best[i].at == 0) continue;
                Say("  IMG hit #%d RVA 0x%llX score=%d", i + 1,
                    (unsigned long long)(g_best[i].at - base), g_best[i].score);
                float m[16];
                if (Read(dev, pid, g_best[i].at, (ULONG)sizeof(m), m) == 0)
                    PrintMat(m, "  window", g_best[i].at);
            }
            if (g_best[0].at == 0) {
                Say("RESULT: image-scan no-matrix (%u chunks ok)", okChunks);
                Say("VERDICT: FAIL - no matrix-shaped window anywhere in the image; the "
                    "matrix is a pointer target, not a static - go to a dump/RE next");
                rc = 10;
            } else {
                Say("RESULT: image-scan best RVA 0x%llX score=%d",
                    (unsigned long long)(g_best[0].at - base), g_best[0].score);
                Say("VERDICT: PASS - recon: a matrix-shaped window exists in the image at "
                    "RVA 0x%llX; verify it by projecting a known world point before promoting",
                    (unsigned long long)(g_best[0].at - base));
            }
            CloseHandle(dev);
            if (g_out) fclose(g_out);
            return rc;
        }

        // ---- 1. matrix hunt ---------------------------------------------
        Say("--- matrix hunt: strict (finite, |v|<=1e5, >=8 nonz, w-row) ---");
        const ULONG64 anchors[2] = { base + G::VIEW_MATRIX, base + G::VIEW_MATRIX_A_BAD };
        const char*    names[2]  = { "B +0x1B4DFA0 (h320_va)", "A +0x022EE01 (memory.h)" };
        int bestScoreGlobal = 0;
        ULONG64 bestAt = 0;
        for (int a = 0; a < 2; ++a) {
            Say("anchor %s", names[a]);
            const int best = ScanMatrix(dev, pid, anchors[a], win);
            for (int i = 0; i < 3; ++i) {
                if (g_best[i].at == 0) continue;
                const long long d = (long long)g_best[i].at - (long long)anchors[a];
                Say("  hit #%d at base%+lld (0x%llX) score=%d -> RVA 0x%llX", i + 1, d,
                    (unsigned long long)g_best[i].at, g_best[i].score,
                    (unsigned long long)(g_best[i].at - base));
            }
            if (best > 0 && g_best[0].at != 0) {
                float m[16];
                if (Read(dev, pid, g_best[0].at, (ULONG)sizeof(m), m) == 0)
                    PrintMat(m, "  best window", g_best[0].at);
            }
            if (best > bestScoreGlobal) { bestScoreGlobal = best; bestAt = g_best[0].at; }
        }

        // ---- 2. entity-list hunt -----------------------------------------
        Say("--- entity-list hunt: canonical pointers near base+0x%X ---", G::ENTITY_LIST);
        const ULONGLONG cand = ScanList(dev, pid, base + G::ENTITY_LIST, listWin);
        if (cand) {
            ULONG64 one = 0; LONG st = 0;
            Read8(dev, pid, &cand, 1, &one, &st);
            Say("list candidate 0x%llX (RVA 0x%llX) slot0=0x%llX st=0x%08X",
                (unsigned long long)cand, (unsigned long long)(cand - base),
                (unsigned long long)one, (unsigned)st);
        }

        // ---- verdict ------------------------------------------------------
        const bool gotMatrix = (bestScoreGlobal >= 25);
        if (gotMatrix && cand) {
            Say("RESULT: matrix=0x%llX(score %d) list=0x%llX", (unsigned long long)bestAt,
                bestScoreGlobal, (unsigned long long)cand);
            Say("VERDICT: PASS - recon: BOTH a matrix window and a list candidate were found "
                "near the documented anchors; promote them and re-run qk_ents on the new RVAs");
        } else if (gotMatrix || cand) {
            Say("RESULT: matrix=0x%llX(score %d) list=0x%llX", (unsigned long long)bestAt,
                bestScoreGlobal, (unsigned long long)cand);
            Say("VERDICT: PARTIAL - one of the two anchors still needs a wider window or a "
                "different search shape (%s)", gotMatrix ? "matrix found, list not" : "list found, matrix not");
            rc = 9;
        } else {
            Say("RESULT: none matrix_best=%d", bestScoreGlobal);
            Say("VERDICT: FAIL - neither anchor has a plausible neighbour in +/-0x%llX bytes; "
                "the next move is a full .data dump, not a wider window", (unsigned long long)(win / 2));
            rc = 10;
        }
    }
    CloseHandle(dev);
    if (g_out) fclose(g_out);
    return rc;
}


