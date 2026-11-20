// TRANSPORT: \\.\ApexDrv (apexdrv, tier T2 - a custom driver we load). DIAGNOSTIC PATH ONLY.
// The shipping reader is ext\qk_va.py on gdrv3 (tier T1 - parasitic, vendor-signed, already
// resident, never attaches). apexdrv attaches per IOCTL and is what killed the game in 14 s-4 min.

// External driver-backed entity-list resolver for the CURRENT build (2026-11-18).
//
// Reader is qk_drvread.hpp (\\.\ApexDrv), not ReadProcessMemory: under EAAC a
// user-mode handle loses PROCESS_VM_READ (RPM err=5) even elevated.
//
// Two eras of knowledge are carried at once, because neither offset set is
// proven for this build and the difference is testable in one run:
//   set N  = C0WN0W/Easy-Apex-External, pushed 2026-11-12 (newest public)
//   set P  = local pack / static table (stale, kept as the control)
// Both global numbers live in .data either way (checked against the PE section
// table: .data spans RVA 0x334C000..0xDE6FAAC), so a wrong value reads mapped
// garbage instead of failing - the field sets below discriminate.
//
// Entity list shape for this era (from the live source above, not memory):
//   ent = READ64(base + EntityList + idx*0x20)      // 0x20-byte handle rows
// There is NO xor/rotate on the pointer: GetEntityPtr and GetLocalPlayerPtr
// both deref the static global once.  If a slot validates under set N field
// offsets but not set P, the earlier "encoded pointer" reading was simply a
// stale RVA landing on an unrelated global.
//
// Read-only. Usage:
//   qk_player_probe.exe <label> <pid> [--list=0xRVA] [--local=0xRVA] [--scan]
//   --list/--local  override the built-in candidates (repeatable)
//   --scan          self-validating hunt for the list inside .data
#define WIN32_LEAN_AND_MEAN
#include "qk_drvread.hpp"
#include <string.h>
#include <string>
#include <vector>
#include <algorithm>
#include <stdio.h>
#include <math.h>

struct FieldSet {
    const char *tag;
    uintptr_t hp, team, origin, script, name, life;
};
// N = Nov-12 source, P = stale pack order.  Same roles, different RVAs.
static const FieldSet kSets[] = {
    { "N", 0x324, 0x334, 0x17c, 0x580, 0x470, 0x690 },
    { "P", 0x328, 0x338, 0x170, 0x588, 0x478, 0x698 },
};

struct Game {
    QkDrvRead rd;
    uintptr_t base;
    unsigned char hdr[0x400];
    uintptr_t data_lo, data_hi, text_lo, text_hi;

    explicit Game(DWORD pid) : rd(pid), base(0), data_lo(0), data_hi(0), text_lo(0), text_hi(0) {
        base = rd.module_base();
        if (base && rd.read(base, hdr, sizeof(hdr))) parse_sections();
    }
    template<class T> bool at(uintptr_t p, T &out) { return rd.read(p, &out, sizeof(out)); }

    // Section ranges straight out of the local PE image (no remembered geometry).
    void parse_sections() {
        const uint32_t lf = *(uint32_t *)(hdr + 0x3C);
        if (lf < 0x40 || lf > 0x200) return;
        const uint16_t nsec = *(uint16_t *)(hdr + lf + 6);
        const uint16_t optsz = *(uint16_t *)(hdr + lf + 0x14);
        const unsigned char *p = hdr + lf + 0x18 + optsz;
        for (uint16_t i = 0; i < nsec && (p + 40) <= hdr + sizeof(hdr); ++i, p += 40) {
            uint32_t vs, va;
            memcpy(&vs, p + 8, 4); memcpy(&va, p + 12, 4);
            if (!memcmp(p, ".data", 5)) { data_lo = base + va; data_hi = data_lo + vs; }
            else if (!memcmp(p, ".text", 5)) { text_lo = base + va; text_hi = text_lo + vs; }
        }
    }

    bool is_user_va(uint64_t v) const {
        return v >= 0x10000ull && v <= 0x7FFFFFFFFFFFull && !(v & 7ull);
    }
    // One entity row test.  Returns the count of passed checks; >= 4 is a hit.
    int score_entity(uintptr_t p, const FieldSet &fs, bool verbose) {
        if (!p) return 0;
        uint64_t vtable = 0;
        int checks = 0;
        if (at(p, vtable) && vtable >= base && vtable < base + 0xE000000) checks += 2;
        int team = -1, hp = -1, life = -1, script = 0;
        at(p + fs.team, team); at(p + fs.hp, hp); at(p + fs.life, life);
        if (team >= 0 && team <= 100) checks += 2;
        if (hp >= 0 && hp <= 200) checks += 2;
        if (life >= 0 && life <= 1) checks += 1;
        float org[3] = {0,0,0};
        if (at(p + fs.origin, org)) {
            const double mag = fabs(org[0]) + fabs(org[1]) + fabs(org[2]);
            if (mag > 1.0 && mag < 1000000.0) checks += 2;
        }
        if (at(p + fs.script, script) && script > -1000 && script < 100000) checks += 1;
        char *namep = nullptr;
        char name[48] = {0};
        if (at(p + fs.name, namep) && is_user_va((uint64_t)namep)) {
            if (at((uintptr_t)namep, name)) {
                name[sizeof(name)-1] = 0;
                int chars = 0;
                while (name[chars] && chars < (int)sizeof(name)-1 &&
                       (unsigned char)name[chars] >= 32 && (unsigned char)name[chars] < 127) ++chars;
                if (chars >= 3) { checks += 2; name[chars] = 0; }
                else name[0] = 0;
            }
        }
        if (verbose && checks >= 4)
            printf("    ent=%llX checks=%d hp=%d team=%d life=%d script=%d org=(%.0f %.0f %.0f) name=%s\n",
                   (unsigned long long)p, checks, hp, team, life, script,
                   org[0], org[1], org[2], name);
        return checks;
    }

    // Deep field dump: shows exactly what sits at every candidate offset so the
    // right set can be picked by eye instead of by score.
    void deep(uintptr_t listRva, unsigned slots) {
        uintptr_t array = 0;
        if (!at(base + listRva, array)) { printf("DEEP list read_fail\n"); return; }
        printf("DEEP list rva=%llX -> %llX\n", (unsigned long long)listRva,
               (unsigned long long)array);
        for (unsigned i = 0; i < slots; ++i) {
            uintptr_t e = 0;
            if (!at(array + (uintptr_t)i * 0x20, e) || !is_user_va(e)) continue;
            uint64_t vt = 0;
            at(e, vt);
            printf("\nDEEP slot=%u ent=%llX vt_rva=%llX\n", i, (unsigned long long)e,
                   (unsigned long long)(vt - base));
            static const unsigned zones[3] = {0x160, 0x300, 0x460};
            for (unsigned z = 0; z < 3; ++z) {
                unsigned char row[0x40];
                if (!rd.read(e + zones[z], row, sizeof(row))) { printf("  +%03X read_fail\n", zones[z]); continue; }
                printf("  +%03X", zones[z]);
                for (unsigned k = 0; k < sizeof(row); k += 8) {
                    uint64_t q;
                    memcpy(&q, row + k, 8);
                    printf(" %016llX", (unsigned long long)q);
                }
                printf("\n");
            }
        }
    }

    // Code-anchored hunt.  Every x64 `mov r64,[rip+disp32]` in .text whose target
    // is a .data global that dereferences to a plausible handle row array.  The
    // game's own accessor is in there, so a hit is the real global by construction
    // instead of by score alone.
    void sig_scan(unsigned maxSlots) {
        if (!text_lo || !text_hi || !data_lo) { printf("SIG no ranges\n"); return; }
        struct Hit { uintptr_t global; int rows, fields; };
        std::vector<Hit> best;
        std::vector<unsigned char> buf(0x1000);
        const DWORD t0 = GetTickCount();
        unsigned chunks = 0, cands = 0;
        for (uintptr_t a = text_lo; a + 0x1000 <= text_hi; a += 0x1000) {
            if (!rd.read(a, buf.data(), buf.size())) continue;
            if (++chunks % 2048 == 0)
                printf("SIG progress chunks=%u cands=%u ms=%lu\n", chunks, cands,
                       (unsigned long)GetTickCount() - t0);
            for (unsigned o = 0; o + 7 <= buf.size(); ++o) {
                if (buf[o] != 0x48 && buf[o] != 0x4C) continue;   // REX.W
                if (buf[o + 1] != 0x8B && buf[o + 1] != 0x89) continue;
                if ((buf[o + 2] & 0xC7) != 0x05) continue;        // mod=00 rm=101 -> rip
                int32_t disp;
                memcpy(&disp, buf.data() + o + 3, 4);
                const uintptr_t g = a + o + 7 + (intptr_t)disp;
                if (g < data_lo || g + 8 > data_hi) continue;
                ++cands;
                uintptr_t arr = 0;
                if (!at(g, arr) || !is_user_va(arr) || (arr & 0xF)) continue;
                unsigned char rows[8 * 0x20];
                if (!rd.read(arr, rows, sizeof(rows))) continue;
                int rowsOk = 0, fields = 0;
                for (unsigned k = 0; k < 8; ++k) {
                    uintptr_t ep;
                    memcpy(&ep, rows + k * 0x20, 8);
                    if (!is_user_va(ep)) continue;
                    uint64_t vt = 0;
                    if (!at(ep, vt) || vt < base || vt >= base + 0xE000000) continue;
                    ++rowsOk;
                    fields += score_entity(ep, kSets[0], false);
                }
                if (rowsOk < 3) continue;
                best.push_back(Hit{ g, rowsOk, fields });
            }
        }
        std::sort(best.begin(), best.end(), [](const Hit &x, const Hit &y) {
            if (x.rows != y.rows) return x.rows > y.rows;
            return x.fields > y.fields;
        });
        unsigned uniq = 0;
        for (size_t i = 0; i < best.size() && uniq < 12; ++i) {
            if (i && best[i].global == best[i - 1].global) continue;
            printf("SIG hit global_rva=%llX rows_ok=%d fields=%d\n",
                   (unsigned long long)(best[i].global - base), best[i].rows, best[i].fields);
            if (++uniq == 4) {
                for (size_t k = 0; k <= i; ++k) {
                    printf("SIG walk global_rva=%llX\n",
                           (unsigned long long)(best[k].global - base));
                    uintptr_t arr = 0;
                    if (at(best[k].global, arr) && is_user_va(arr))
                        walk(arr, maxSlots, "SIG");
                }
            }
        }
        printf("SIG done chunks=%u cands=%u ms=%lu\n", chunks, cands,
               (unsigned long)GetTickCount() - t0);
    }

    // Walk up to `slots` rows, stride 0x20, both field sets.  Returns hits.
    int walk(uintptr_t array, unsigned slots, const char *label) {
        int hits = 0;
        for (const FieldSet &fs : kSets) {
            int setHits = 0;
            std::vector<unsigned char> buf(0x1000);
            for (unsigned i = 0; i < slots; i += 128) {
                const unsigned n = (slots - i > 128) ? 128 : (slots - i);
                if (!rd.read(array + (uintptr_t)i * 0x20, buf.data(), (SIZE_T)n * 0x20)) continue;
                for (unsigned k = 0; k < n; ++k) {
                    uintptr_t p;
                    memcpy(&p, buf.data() + k * 0x20, 8);
                    if (!is_user_va(p)) continue;
                    const int s = score_entity(p, fs, true);
                    if (s >= 4) {
                        ++setHits;
                        printf("  %s set=%s slot=%u hit\n", label, fs.tag, i + k);
                    }
                }
            }
            printf("%s FIELD_SET %s hits=%d\n", label, fs.tag, setHits);
            hits += setHits;
        }
        return hits;
    }

    // Self-validating list hunt: every 8-aligned qword in .data that points at
    // rows which themselves point at entity-shaped objects.
    void scan(const char *label, unsigned maxSlots) {
        if (!data_lo || data_hi <= data_lo) { printf("SCAN no .data range\n"); return; }
        printf("SCAN .data %llX..%llX\n", (unsigned long long)data_lo,
               (unsigned long long)data_hi);
        struct Hit { uintptr_t array, src; int score; };
        std::vector<Hit> best;
        std::vector<unsigned char> buf(0x1000);
        const DWORD t0 = GetTickCount();
        unsigned chunks = 0, cands = 0;
        for (uintptr_t a = data_lo; a + 0x1000 <= data_hi; a += 0x1000) {
            if (!rd.read(a, buf.data(), buf.size())) continue;
            if (++chunks % 4096 == 0)
                printf("SCAN progress rva=%llX chunks=%u cands=%u ms=%lu\n",
                       (unsigned long long)(a - base), chunks, cands,
                       (unsigned long)GetTickCount() - t0);
            for (unsigned o = 0; o + 8 <= buf.size(); o += 8) {
                uintptr_t v;
                memcpy(&v, buf.data() + o, 8);
                if (!is_user_va(v)) continue;
                ++cands;
                unsigned char rows[8 * 0x20];
                if (!rd.read(v, rows, sizeof(rows))) continue;
                int score = 0;
                for (unsigned k = 0; k < 8; ++k) {
                    uintptr_t ep;
                    memcpy(&ep, rows + k * 0x20, 8);
                    if (!is_user_va(ep)) continue;
                    uint64_t vt = 0;
                    if (!at(ep, vt) || vt < base || vt >= base + 0xE000000) continue;
                    ++score;
                }
                if (score < 3) continue;
                best.push_back(Hit{ v, a + o, score });
                if (best.size() > 400) {
                    std::sort(best.begin(), best.end(),
                              [](const Hit &x, const Hit &y) { return x.score > y.score; });
                    best.resize(200);
                }
            }
        }
        std::sort(best.begin(), best.end(),
                  [](const Hit &x, const Hit &y) { return x.score > y.score; });
        printf("SCAN done chunks=%u cands=%u hits=%u ms=%lu\n", chunks, cands,
               (unsigned)best.size(), (unsigned long)GetTickCount() - t0);
        if (best.size() > 8) best.resize(8);
        for (const Hit &h : best)
            printf("SCAN hit rva=%llX rows_ok=%d\n",
                   (unsigned long long)(h.src - base), h.score);
        for (const Hit &h : best) {
            printf("SCAN walk rva=%llX\n", (unsigned long long)(h.src - base));
            walk(h.array, maxSlots, label);
        }
    }
};

int wmain(int argc, wchar_t **argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    if (argc < 3) {
        printf("usage: qk_player_probe.exe <label> <pid> [--list=0xRVA] [--local=0xRVA] [--scan]\n");
        return 2;
    }
    std::vector<uintptr_t> lists, locals, deeps;
    bool doScan = false, doSig = false;
    for (int i = 3; i < argc; ++i) {
        if (!wcsncmp(argv[i], L"--list=", 7))  lists.push_back((uintptr_t)wcstoull(argv[i] + 7, nullptr, 16));
        else if (!wcsncmp(argv[i], L"--local=", 8)) locals.push_back((uintptr_t)wcstoull(argv[i] + 8, nullptr, 16));
        else if (!wcsncmp(argv[i], L"--deep=", 7)) deeps.push_back((uintptr_t)wcstoull(argv[i] + 7, nullptr, 16));
        else if (!wcsncmp(argv[i], L"--sig", 6)) doSig = true;
        else if (!wcsncmp(argv[i], L"--scan", 6)) doScan = true;
    }
    Game g(wcstoul(argv[2], nullptr, 10));
    printf("reader_valid=%d base=%llX data=%llX..%llX\n", g.rd.valid(),
           (unsigned long long)g.base, (unsigned long long)g.data_lo,
           (unsigned long long)g.data_hi);
    if (!g.rd.valid() || !g.base) return 3;
    if (lists.empty()) { lists.push_back(0x6268C28); lists.push_back(0x6B51458); }
    if (locals.empty()) { locals.push_back(0x2691C08); locals.push_back(0x24D1B80); }

    for (uintptr_t rva : locals) {
        uintptr_t p = 0;
        if (!g.at(g.base + rva, p) || !p) {
            printf("LOCAL rva=%llX unreadable\n", (unsigned long long)rva);
            continue;
        }
        printf("LOCAL rva=%llX ptr=%llX\n", (unsigned long long)rva, (unsigned long long)p);
        for (const FieldSet &fs : kSets)
            printf("  set %s score=%d\n", fs.tag, g.score_entity(p, fs, true));
    }
    for (uintptr_t rva : lists) {
        uintptr_t array = 0;
        if (!g.at(g.base + rva, array)) {
            printf("LIST rva=%llX read_fail\n", (unsigned long long)rva);
            continue;
        }
        if (!array) {
            printf("LIST rva=%llX raw=0 (zero global)\n", (unsigned long long)rva);
            continue;
        }
        printf("LIST rva=%llX -> %llX\n", (unsigned long long)rva, (unsigned long long)array);
        g.walk(array, 512, "LIST");
    }
    for (uintptr_t rva : deeps) g.deep(rva, 8);
    if (doSig) g.sig_scan(64);
    if (doScan) g.scan("SCAN", 256);
    return 0;
}

