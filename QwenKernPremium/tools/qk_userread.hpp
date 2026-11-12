#pragma once
// Plain external memory reader, not a new driver.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winternl.h>
#include <stdint.h>

class QkUserRead {
public:
    explicit QkUserRead(DWORD pid);
    ~QkUserRead();
    bool valid() const { return handle_ != nullptr; }
    bool read(uintptr_t address, void *dst, SIZE_T size) const;
    uintptr_t module_base() const;
private:
    HANDLE handle_;
    PPEB peb_;
};