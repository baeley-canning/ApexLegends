// External normal privileged VA read proof for CURRENT build.
// No new driver, no arbitrary scanning, no writes. Entity record offsets come
// from the local dm32 dump (not remembered global-corpus patch-day values).
#define WIN32_LEAN_AND_MEAN
#include "qk_userread.hpp"
#include <vector>
#include <string>
#include <stdio.h>
#include <math.h>

struct EntityInfo { uintptr_t ptr; float origin[3]; int health, shield, team;
                    char name[64]; bool valid; };

struct Game {
    QkUserRead rd;
    uintptr_t base;
    explicit Game(DWORD pid) : rd(pid) { base = rd.module_base(); }

    // These two tables are EXPERIMENTAL per repo docs/ref/DELTA_MATRIX.md, not
    // shipping truths: they are per-name probe candidates, no arbitrary global
    // 'uniform correction'. Data extraction and field decisions are independent.
    static constexpr uintptr_t local_candidates[] = {0x26AF8A8, 0x24D1B80};
    static constexpr uintptr_t list_candidates[] = {0x6B51458, 0x6B53478};
    static constexpr uintptr_t health_values[] = {0x330, 0x328};
    static constexpr uintptr_t team_values[] = {0x340, 0x338};
    static constexpr uintptr_t origin_values[] = {0x170};
    static constexpr uintptr_t shield_values[] = {0x18c, 0x1a0};

    template<class T> bool at(uintptr_t p, T& out) { return rd.read(p, &out, sizeof(out)); }

    bool player(uintptr_t p, EntityInfo &out) {
        if (!p) return false;
        int team = -1, health = -1, shield = -1;
        at(p+team_values[0], team); at(p+team_values[1], health);
        if (team < 0 || team > 100 || health < 0 || health > 200) return false;
        at(p+origin_values[0], out.origin);
        if (fabs((double)out.origin[0]) + fabs((double)out.origin[1]) +
            fabs((double)out.origin[2]) > 1000000.0) return false;
        // m_iSignifierName has no separate offset guess: this is a bounded field
        // candidate from a pointer-bearing row, checked by accepted string rules.
        char *namep = nullptr; out.name[0] = 0;
        if (at(p+0x478, namep) && namep) {
            char b[64]{};
            if (rd.read((uintptr_t)namep, b, sizeof(b)-1)) {
                b[sizeof(b)-1]=0;
                int chars=0;
                while (b[chars] && chars < (int)sizeof(b)-1 &&
                       b[chars] >= 32 && b[chars] < 127) ++chars;
                if (chars >= 3 && chars < (int)sizeof(b)) memcpy(out.name,b,chars+1);
            }
        }
        out.ptr=p; out.health=health; out.team=team;
        out.shield=shield; out.valid=true;
        return true;
    }
};

int wmain(int argc, wchar_t **argv) {
    if (argc < 3) return 2;
    Game g(wcstoul(argv[2],nullptr,10));
    printf("reader_valid=%d base=%llX\n", g.rd.valid(), (unsigned long long)g.base);
    fflush(stdout);
    if (!g.rd.valid() || !g.base) return 3;
    for (uintptr_t rva : g.local_candidates) {
        uintptr_t p=0;
        if (!g.at(g.base+rva,p) || !p) continue;
        EntityInfo player{};
        if (g.player(p,player)) {
            printf("LOCAL offset=%llX ptr=%llX hp=%d team=%d origin=(%.1f %.1f %.1f) name=%s\n",
                (unsigned long long)rva,(unsigned long long)p,player.health,player.team,
                player.origin[0],player.origin[1],player.origin[2],player.name);
        } else printf("LOCAL_CANDIDATE offset=%llX ptr=%llX rejected health/team/origin\n",
                      (unsigned long long)rva,(unsigned long long)p);
    }
    for (uintptr_t rva : g.list_candidates) {
        uintptr_t array=0;
        if (!g.at(g.base+rva,array) || !array) continue;
        printf("ENTITY_ARRAY rva=%llX -> %llX\n",(unsigned long long)rva,
                 (unsigned long long)array);
        for (int i=0; i<100; ++i) {
            uintptr_t p=0;
            if (!g.at(array+(uintptr_t)i*8,p) || !p) continue;
            EntityInfo player{};
            if (g.player(p,player)) {
                printf("SLOT %d id=%llX name=%s hp=%d team=%d origin=(%.1f %.1f %.1f)\n",
                    i,(unsigned long long)p,player.name,player.health,player.team,
                    player.origin[0],player.origin[1],player.origin[2]);
            }
        }
    }
    return 0;
}