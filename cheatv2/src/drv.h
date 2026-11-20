#pragma once
#include <windows.h>
#include <cstdint>
#include <cstdio>

namespace gdrv {
    enum class Mode { None, Copy, Map };       // tells ReadPhys/WritePhys which internal path to use internally
    
    bool Open(const char* device, DWORD ioctlCopyBase);   // takes argv values directly
    void Close();                                         // cleanup handle reset globals 

    HANDLE GetDeviceHandle() noexcept;              // live handle for probe table / direct Ioctl use
    bool Ok()      noexcept;                          // true while handle valid 
    Mode GetMode()  noexcept;                         // tells you whether ReadPhys uses Copy or Map mode internally

    bool ReadPhys(uint64_t pa, void* dst, size_t len);
    bool WritePhys(uint64_t pa, const void* src, size_t len);
}

