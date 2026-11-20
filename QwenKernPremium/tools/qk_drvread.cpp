// TRANSPORT: \\.\ApexDrv (apexdrv, tier T2 - a custom driver we load). DIAGNOSTIC PATH ONLY.
// The shipping reader is ext\qk_va.py on gdrv3 (tier T1 - parasitic, vendor-signed, already
// resident, never attaches). apexdrv attaches per IOCTL and is what killed the game in 14 s-4 min.

#include "qk_drvread.hpp"
#include <stdio.h>
#include <string.h>

// One 4 KB batch response is 8 KB+ live: keep it static, not on the stack.
static APEXDRV_READBUF_REQUEST g_buf;

QkDrvRead::QkDrvRead(DWORD pid) : handle_(INVALID_HANDLE_VALUE), pid_(pid) {
    handle_ = CreateFileW(APEXDRV_WIN32_NAME, GENERIC_READ | GENERIC_WRITE,
                          0, nullptr, OPEN_EXISTING, 0, nullptr);
    if (handle_ == INVALID_HANDLE_VALUE) {
        printf("OPEN driver failed err=%lu\n", GetLastError());
        return;
    }
    // VERSION response is 8 bytes and METHOD_BUFFERED needs the full size back.
    struct VersionReq { ULONG Version; ULONG Reserved; } ver{};
    DWORD ret = 0;
    if (!DeviceIoControl(handle_, IOCTL_APEXDRV_VERSION, &ver, sizeof(ver),
                         &ver, sizeof(ver), &ret, nullptr)) {
        printf("driver VERSION ioctl failed err=%lu\n", GetLastError());
        CloseHandle(handle_);
        handle_ = INVALID_HANDLE_VALUE;
        return;
    }
    if (ver.Version < QK_DRVREAD_MIN_ABI) {
        printf("driver ABI v%lu is older than v%d\n", (unsigned long)ver.Version,
               QK_DRVREAD_MIN_ABI);
        CloseHandle(handle_);
        handle_ = INVALID_HANDLE_VALUE;
        return;
    }
    printf("driver ABI v%lu pid=%lu\n", (unsigned long)ver.Version, (unsigned long)pid);
}

QkDrvRead::~QkDrvRead() {
    if (handle_ != INVALID_HANDLE_VALUE) CloseHandle(handle_);
}

bool QkDrvRead::read(uintptr_t addr, void *dst, SIZE_T size) const {
    if (handle_ == INVALID_HANDLE_VALUE || !dst || !size) return false;
    UCHAR *out = static_cast<UCHAR *>(dst);
    while (size) {
        const ULONG chunk = size > APEXDRV_MAX_BUF ? APEXDRV_MAX_BUF : (ULONG)size;
        memset(&g_buf, 0, sizeof(g_buf));
        g_buf.ProcessId = pid_;
        g_buf.Size      = chunk;
        g_buf.Address   = addr;
        DWORD ret = 0;
        if (!DeviceIoControl(handle_, IOCTL_APEXDRV_READBUF, &g_buf, sizeof(g_buf),
                             &g_buf, sizeof(g_buf), &ret, nullptr)) {
            return false;
        }
        if (g_buf.Status != 0) {
            SetLastError((DWORD)g_buf.Status);
            return false;
        }
        memcpy(out, g_buf.Data, chunk);
        out  += chunk;
        addr += chunk;
        size -= chunk;
    }
    return true;
}

uintptr_t QkDrvRead::module_base() const {
    if (handle_ == INVALID_HANDLE_VALUE) return 0;
    APEXDRV_BASE_REQUEST req{};
    req.ProcessId = pid_;
    DWORD ret = 0;
    if (!DeviceIoControl(handle_, IOCTL_APEXDRV_BASE, &req, sizeof(req),
                         &req, sizeof(req), &ret, nullptr)) {
        printf("BASE ioctl failed err=%lu\n", GetLastError());
        return 0;
    }
    if (req.Status != 0) {
        printf("BASE status=0x%08lX\n", (unsigned long)req.Status);
        return 0;
    }
    return (uintptr_t)req.Base;
}
