#pragma once
// Driver-backed external reader.  Same surface as qk_userread.hpp, but every
// access goes through \\.\ApexDrv instead of ReadProcessMemory.
//
// Why this exists: on the live game under EAAC, OpenProcess(QUERY_INFORMATION |
// VM_READ) succeeds even elevated while ReadProcessMemory fails with err=5 -
// EAAC's Ob callbacks strip the VM rights from the returned handle.  The driver
// opens with its own handle inside the kernel, so RPM-based tools go blind the
// moment the anti-cheat arms.  Measured 18/11 21:43 on pid 22108.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winioctl.h>       // CTL_CODE / METHOD_BUFFERED / FILE_ANY_ACCESS
#include <stdint.h>
#include "apex_driver_ioctl.h"

// Refuse anything older than the v14 read quartet (READ8/READBUF/WRITE/BASE).
#define QK_DRVREAD_MIN_ABI 14

class QkDrvRead {
public:
    explicit QkDrvRead(DWORD pid);
    ~QkDrvRead();
    bool valid() const { return handle_ != INVALID_HANDLE_VALUE; }
    bool read(uintptr_t address, void *dst, SIZE_T size) const;
    uintptr_t module_base() const;
private:
    HANDLE handle_;
    DWORD  pid_;
};
