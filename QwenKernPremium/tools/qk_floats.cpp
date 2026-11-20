// TRANSPORT: \\.\ApexDrv (apexdrv, tier T2 - a custom driver we load). DIAGNOSTIC PATH ONLY.
// The shipping reader is ext\qk_va.py on gdrv3 (tier T1 - parasitic, vendor-signed, already
// resident, never attaches). apexdrv attaches per IOCTL and is what killed the game in 14 s-4 min.

// ============================================================================
// tools\qk_floats.cpp - hex + float dump of a region of the target module.
//
// Read-only. Prints, per 0x20 block: the address, the four floats at +0x00,
// the four floats at +0x10 and the two qwords, so a "matrix-shaped" hit from
// qk_hunt --image can be looked at properly instead of guessed about.
//
// Usage: qk_floats.exe <pid> <rva> [len]        len defaults to 0x200
// ============================================================================
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winioctl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "apex_driver_ioctl.h"

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

static float Rf32(const unsigned char* p) {
    unsigned u; float f; memcpy(&u, p, 4); memcpy(&f, &u, 4); return f;
}
static unsigned long long Rd64(const unsigned char* p) {
    unsigned long long v; memcpy(&v, p, 8); return v;
}

// ---------------------------------------------------------------------------
// rotation-matrix test: three rows that are (near) unit length and (near)
// orthogonal, with a 4th row of translation.  A garbage window cannot pass.
// returns 1..100 or 0
// ---------------------------------------------------------------------------
static int Finite(float x) {
    return (x == x) && (x < 3.4e38f) && (x > -3.4e38f);
}

static int ScoreRot(const float* m, char* why, size_t whyN) {
    for (int i = 0; i < 15; ++i) if (!Finite(m[i])) return 0;
    const float a = m[0], b = m[1], c = m[2];
    const float d = m[4], e = m[5], f = m[6];
    const float g = m[8], h = m[9], i2 = m[10];
    const float l0 = a * a + b * b + c * c;
    const float l1 = d * d + e * e + f * f;
    const float l2 = g * g + h * h + i2 * i2;
    if (l0 < 0.85f || l0 > 1.15f) return 0;
    if (l1 < 0.85f || l1 > 1.15f) return 0;
    if (l2 < 0.85f || l2 > 1.15f) return 0;
    const float d01 = a * d + b * e + c * f;
    const float d02 = a * g + b * h + c * i2;
    const float d12 = d * g + e * h + f * i2;
    if (d01 > 0.12f || d01 < -0.12f) return 0;
    if (d02 > 0.12f || d02 < -0.12f) return 0;
    if (d12 > 0.12f || d12 < -0.12f) return 0;
    const float tx = m[12], ty = m[13], tz = m[14];
    if (tx > 2.0e5f || tx < -2.0e5f) return 0;
    if (ty > 2.0e5f || ty < -2.0e5f) return 0;
    if (tz > 2.0e5f || tz < -2.0e5f) return 0;
    int clean = 0;
    if (m[3] > -0.01f && m[3] < 0.01f) ++clean;
    if (m[7] > -0.01f && m[7] < 0.01f) ++clean;
    if (m[11] > -0.01f && m[11] < 0.01f) ++clean;
    int s = 40 + clean * 5;
    const float mag = (tx < 0 ? -tx : tx) + (ty < 0 ? -ty : ty) + (tz < 0 ? -tz : tz);
    if (mag > 500.0f) s += 15;                      // world-scale translation
    if (why && whyN) sprintf_s(why, whyN, "l=(%.3f %.3f %.3f) d=(%.3f %.3f %.3f) t=(%.1f %.1f %.1f) clean=%d",
                               l0, l1, l2, d01, d02, d12, tx, ty, tz, clean);
    return (s > 100) ? 100 : s;
}

static float TransMag(const float* m) {
    const float tx = m[12], ty = m[13], tz = m[14];
    return (tx < 0 ? -tx : tx) + (ty < 0 ? -ty : ty) + (tz < 0 ? -tz : tz);
}

static int g_printed = 0;
static unsigned long long g_lastPrint = ~0ull;

static void RotHit(unsigned long long rva, const float* m, int s) {
    if (rva - g_lastPrint < 0x30ull) return;         // same matrix, next slide
    g_lastPrint = rva;
    if (g_printed >= 80) return;
    ++g_printed;
    char why[160];
    ScoreRot(m, why, sizeof(why));
    printf("ROT hit rva=0x%llX score=%d %s\n", rva, s, why);
    for (int r = 0; r < 4; ++r)
        printf("   [%d] %12.5f %12.5f %12.5f %12.5f\n", r,
               m[r * 4], m[r * 4 + 1], m[r * 4 + 2], m[r * 4 + 3]);
}

// ---------------------------------------------------------------------------
// two-pass liveness hunt: a matrix that still exists on pass 2 but has
// different numbers belongs to a live, per-frame transform.  Only world-scale
// translations are collected, which drops the identity constant pools in
// .rdata that made the single pass unusable.
// ---------------------------------------------------------------------------
static const int kMaxHits = 60000;
struct Hit { unsigned long long rva; float m[16]; };
static Hit* g_hits = nullptr;
static int g_nHits = 0;
static unsigned long long g_lastCollect = ~0ull;

static void CollectPass(HANDLE dev, DWORD pid, unsigned long long base, unsigned long long len) {
    static unsigned char img[0x1000 + 64];
    memset(img, 0, sizeof(img));
    unsigned long long off = 0, ok = 0, bad = 0;
    while (off < len) {
        const ULONG n = (ULONG)(((len - off) > 0x1000) ? 0x1000 : (len - off));
        memmove(img, img + 0x1000, 64);
        if (Read(dev, pid, base + off, n, img + 64) != 0) { ++bad; off += 0x1000; continue; }
        ++ok;
        const ULONG start = (off == 0) ? 64 : 0;
        for (ULONG o = start; o + 64 <= n + 64; o += 4) {
            float m[16];
            for (int k = 0; k < 16; ++k) m[k] = Rf32(img + o + (ULONG)k * 4);
            const int s = ScoreRot(m, nullptr, 0);
            if (s <= 0) continue;
            const unsigned long long rva = off - 64 + o;
            if (rva - g_lastCollect < 0x30ull) continue;
            g_lastCollect = rva;
            if (TransMag(m) < 300.0f) continue;         // identity / unit-scale pools
            if (g_nHits >= kMaxHits) continue;
            g_hits[g_nHits].rva = rva;
            memcpy(g_hits[g_nHits].m, m, 64);
            ++g_nHits;
        }
        off += 0x1000;
    }
    printf("PASS1 ok=%llu bad=%llu worldscale=%d\n", ok, bad, g_nHits);
}

static void DiffPass(HANDLE dev, DWORD pid, unsigned long long base) {
    unsigned char buf[64];
    int changed = 0, shown = 0;
    for (int i = 0; i < g_nHits; ++i) {
        if (Read(dev, pid, base + g_hits[i].rva, 64, buf) != 0) continue;
        if (memcmp(buf, g_hits[i].m, 64) == 0) continue;
        ++changed;
        if (shown >= 120) continue;
        ++shown;
        printf("LIVE rva=0x%llX\n", g_hits[i].rva);
        for (int r = 0; r < 4; ++r)
            printf("  was[%d] %12.4f %12.4f %12.4f %12.4f   now %12.4f %12.4f %12.4f %12.4f\n", r,
                   g_hits[i].m[r * 4], g_hits[i].m[r * 4 + 1], g_hits[i].m[r * 4 + 2], g_hits[i].m[r * 4 + 3],
                   Rf32(buf + r * 4), Rf32(buf + r * 4 + 4), Rf32(buf + r * 4 + 8), Rf32(buf + r * 4 + 12));
    }
    printf("LIVE changed=%d of %d\n", changed, g_nHits);
}

// scan the whole image in 4 KB chunks with a 64 byte carry for straddles
static int RotScan(HANDLE dev, DWORD pid, unsigned long long base, unsigned long long from,
                   unsigned long long len) {
    static unsigned char img[0x1000 + 64];
    memset(img, 0, sizeof(img));
    unsigned long long off = 0;
    unsigned hits = 0, ok = 0, bad = 0;
    while (off < len) {
        const ULONG n = (ULONG)(((len - off) > 0x1000) ? 0x1000 : (len - off));
        memmove(img, img + 0x1000, 64);
        if (Read(dev, pid, base + from + off, n, img + 64) != 0) {
            ++bad; off += 0x1000; continue;
        }
        ++ok;
        const ULONG start = (off == 0) ? 64 : 0;
        for (ULONG o = start; o + 64 <= n + 64; o += 4) {
            float m[16];
            for (int k = 0; k < 16; ++k) m[k] = Rf32(img + o + (ULONG)k * 4);
            const int s = ScoreRot(m, nullptr, 0);
            if (s <= 0) continue;
            ++hits;
            RotHit(from + off - 64 + o, m, s);
        }
        if ((off & 0x1FFFFFF) == 0)
            printf("   .. rva=0x%llX ok=%u bad=%u hits=%u\n", from + off, ok, bad, hits);
        off += 0x1000;
    }
    printf("ROTSCAN done ok=%u bad=%u hits=%u\n", ok, bad, hits);
    return 0;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        printf("usage: qk_floats <pid> <rva> [len]\n       qk_floats --rot <pid>\n       qk_floats --rotlive <pid>\n");
        return 1;
    }
    const bool rotMode = (strcmp(argv[1], "--rot") == 0);
    const bool liveMode = (strcmp(argv[1], "--rotlive") == 0);
    const bool scanMode = rotMode || liveMode;
    const char* pidArg = scanMode ? argv[2] : argv[1];
    const DWORD pid = (DWORD)strtoul(pidArg, nullptr, 0);
    const unsigned long long rva = scanMode ? 0ull : _strtoui64(argv[2], nullptr, 0);
    unsigned long long len = (argc > 3 && !scanMode) ? _strtoui64(argv[3], nullptr, 0) : 0x200ull;
    if (len < 0x20) len = 0x20;
    if (len > 0x10000) len = 0x10000;
    len &= ~0x1Full;

    HANDLE dev = CreateFileW(APEXDRV_WIN32_NAME, GENERIC_READ | GENERIC_WRITE, 0,
                             nullptr, OPEN_EXISTING, 0, nullptr);
    if (dev == INVALID_HANDLE_VALUE) { printf("driver OPEN err=%lu\n", GetLastError()); return 2; }

    APEXDRV_BASE_REQUEST b;
    memset(&b, 0, sizeof(b));
    b.ProcessId = pid;
    DWORD ret = 0;
    if (!DeviceIoControl(dev, IOCTL_APEXDRV_BASE, &b, (DWORD)sizeof(b), &b,
                         (DWORD)sizeof(b), &ret, nullptr) || b.Status != 0 || b.Base == 0) {
        printf("BASE failed status=0x%08X\n", (unsigned)b.Status);
        CloseHandle(dev);
        return 3;
    }
    const unsigned long long base = b.Base;

    if (rotMode || liveMode) {
        unsigned long long sizeOfImage = 0;
        unsigned char hdr[0x100];
        if (Read(dev, pid, base + 0x3C, 4, hdr) == 0) {
            const ULONG lf = (ULONG)hdr[0] | ((ULONG)hdr[1] << 8) | ((ULONG)hdr[2] << 16) | ((ULONG)hdr[3] << 24);
            if (lf >= 0x40 && lf < 0x1000 && Read(dev, pid, base + lf, (ULONG)sizeof(hdr), hdr) == 0) {
                sizeOfImage = (ULONG)hdr[0x50] | ((ULONG)hdr[0x51] << 8) |
                              ((ULONG)hdr[0x52] << 16) | ((ULONG)hdr[0x53] << 24);
            }
        }
        printf("pid=%lu base=0x%llX %s SizeOfImage=0x%llX\n",
               (unsigned long)pid, base, liveMode ? "ROTLIVE" : "ROT", sizeOfImage);
        if (sizeOfImage < 0x1000) { CloseHandle(dev); return 4; }
        if (rotMode) {
            RotScan(dev, pid, base, 0, sizeOfImage);
        } else {
            g_hits = (Hit*)calloc((size_t)kMaxHits, sizeof(Hit));
            if (!g_hits) { CloseHandle(dev); return 5; }
            CollectPass(dev, pid, base, sizeOfImage);
            Sleep(900);
            if (g_nHits > 0) DiffPass(dev, pid, base);
            free(g_hits);
        }
        CloseHandle(dev);
        return 0;
    }

    printf("pid=%lu base=0x%llX rva=0x%llX len=0x%llX abs=0x%llX\n",
           (unsigned long)pid, base, rva, len, base + rva);

    unsigned char buf[0x1000];
    unsigned long long off = 0;
    while (off < len) {
        const ULONG n = (ULONG)(((len - off) > 0x1000) ? 0x1000 : (len - off));
        if (Read(dev, pid, base + rva + off, n, buf) != 0) {
            printf("@+0x%04llX  READ FAILED\n", off);
            off += 0x1000;
            continue;
        }
        for (ULONG o = 0; o + 0x20 <= n; o += 0x20) {
            printf("@+0x%04llX f0 %11.4f %11.4f %11.4f %11.4f  f1 %11.4f %11.4f %11.4f %11.4f\n",
                   off + o,
                   Rf32(buf + o), Rf32(buf + o + 4), Rf32(buf + o + 8), Rf32(buf + o + 12),
                   Rf32(buf + o + 16), Rf32(buf + o + 20), Rf32(buf + o + 24), Rf32(buf + o + 28));
            printf("@+0x%04llX q  %016llX %016llX %016llX %016llX\n",
                   off + o,
                   Rd64(buf + o), Rd64(buf + o + 8), Rd64(buf + o + 16), Rd64(buf + o + 24));
        }
        off += n;
    }
    CloseHandle(dev);
    return 0;
}
