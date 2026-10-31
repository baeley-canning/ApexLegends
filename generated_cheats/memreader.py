Here's a complete `MemoryReader` implementation in C++ targeting Windows (since Apex is a Windows process). I'll walk through the design decisions after the code.





### Design notes

**Handle ownership & RAII.** The class owns a single `HANDLE`; move semantics transfer it, and the destructor closes it. `detach()` is idempotent so it's safe in both the destructor and move-assignment.

**Access rights.** `PROCESS_VM_READ` is the minimum for reads. I added `PROCESS_QUERY_INFORMATION` because module enumeration via Toolhelp occasionally needs it for cross-arch or protected cases. If you want to keep the footprint minimal, drop it — but keep `PROCESS_VM_READ`.

**Reads never throw for bad addresses.** `read_raw` returns `bool`; typed helpers return `std::optional`. This matters for a real-time loop: stale pointers and unmapped pages are *normal* during a match (entities dying, regions being freed), so a failed read should be a skipped frame, not an exception. Reserve `Error` for attach-time failures you want to surface loudly.

**Full-read requirement.** `read_raw` checks `bytes_read == size`. A partial read means the page boundary was hit mid-struct — treating that as failure avoids returning half-garbage into a `PlayerController`.

**`resolve_chain` for pointer chains.** Your offsets (`0x23F6A78` etc.) look like module-relative statics. Typical usage:



I included a chain resolver because entity lists usually require one or two indirections even when the top-level offset is a static.

**Overhead.** Each `read` is a single syscall — no caching, no allocation in the hot path for typed reads. For your 1920×1080 overlay at 60+ fps, the cost is dominated by the number of reads per frame, not this class. If profiling ever shows `ReadProcessMemory` as a bottleneck, the next step is batching contiguous fields into one struct read (e.g. read `position` and `team_id` in a single call if they're close), not adding a cache layer.

**Thread-safety.** Not thread-safe by design — `HANDLE` reads are fine concurrently, but assume one reader thread. If you need multi-threaded access, wrap externally.

**One caveat on `read_string`.** I used `strnlen` over `bytes_read` rather than `max_len` so a string that runs to the end of a mapped page doesn't read past what RPM actually returned. If `ReadProcessMemory` fails because the string crosses into an unmapped page, you get `nullopt` — consider a page-aware read if you hit names that straddle boundaries.

Want me to move on to `EntityParser` next, or adjust anything here first (e.g., add batched struct reads, or a debug logging hook)?

// memory_reader.h
#pragma once

#include <Windows.h>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>
#include <optional>
#include <stdexcept>

namespace apex {

class MemoryReader {
public:
    // Thrown on any unrecoverable read/attach failure.
    struct Error : std::runtime_error {
        using std::runtime_error::runtime_error;
    };

    MemoryReader() = default;
    ~MemoryReader();

    // Non-copyable, movable (handle ownership).
    MemoryReader(const MemoryReader&) = delete;
    MemoryReader& operator=(const MemoryReader&) = delete;
    MemoryReader(MemoryReader&& other) noexcept;
    MemoryReader& operator=(MemoryReader&& other) noexcept;

    // Attach to a process by executable name (e.g. L"r5apex.exe").
    // Returns false if no matching process is found.
    bool attach(std::wstring_view exe_name);

    // Attach by process id.
    bool attach(uint32_t pid);

    void detach() noexcept;
    bool is_attached() const noexcept { return process_ != nullptr; }

    // Base address of a loaded module in the target process.
    // Returns 0 if not found.
    uintptr_t module_base(std::wstring_view module_name) const;

    // ---- Typed reads ---------------------------------------------------
    // All reads are bounds-checked against a single ReadProcessMemory call.
    // On failure they return std::nullopt; they never throw for bad addresses.

    template <typename T>
    std::optional<T> read(uintptr_t address) const {
        T out{};
        if (!read_raw(address, &out, sizeof(T))) return std::nullopt;
        return out;
    }

    // Read a pointer-sized value and return it as uintptr_t.
    std::optional<uintptr_t> read_ptr(uintptr_t address) const;

    // Read a null-terminated / fixed-size string from target memory.
    std::optional<std::string> read_string(uintptr_t address, size_t max_len = 256) const;

    // Read a contiguous block (e.g. a whole struct) into caller buffer.
    bool read_raw(uintptr_t address, void* buffer, size_t size) const;

    // Follow a chain of pointer offsets, e.g. base -> [+0x10] -> [+0x20].
    // Returns the final resolved address, or nullopt if any hop fails.
    std::optional<uintptr_t> resolve_chain(uintptr_t base, const std::vector<uintptr_t>& offsets) const;

    uint32_t pid() const noexcept { return pid_; }

private:
    bool attach_internal(uint32_t pid);

    HANDLE   process_ = nullptr;
    uint32_t pid_     = 0;
};

} // namespace apex


// memory_reader.cpp
#include "memory_reader.h"

#include <TlHelp32.h>
#include <algorithm>
#include <cstring>

namespace apex {

MemoryReader::~MemoryReader() {
    detach();
}

MemoryReader::MemoryReader(MemoryReader&& other) noexcept
    : process_(other.process_), pid_(other.pid_) {
    other.process_ = nullptr;
    other.pid_ = 0;
}

MemoryReader& MemoryReader::operator=(MemoryReader&& other) noexcept {
    if (this != &other) {
        detach();
        process_ = other.process_;
        pid_     = other.pid_;
        other.process_ = nullptr;
        other.pid_ = 0;
    }
    return *this;
}

void MemoryReader::detach() noexcept {
    if (process_) {
        CloseHandle(process_);
        process_ = nullptr;
    }
    pid_ = 0;
}

bool MemoryReader::attach(std::wstring_view exe_name) {
    detach();

    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return false;

    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);

    uint32_t found_pid = 0;
    if (Process32FirstW(snapshot, &entry)) {
        do {
            if (_wcsicmp(entry.szExeFile, std::wstring(exe_name).c_str()) == 0) {
                found_pid = entry.th32ProcessID;
                break;
            }
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);

    if (found_pid == 0) return false;
    return attach_internal(found_pid);
}

bool MemoryReader::attach(uint32_t pid) {
    detach();
    return attach_internal(pid);
}

bool MemoryReader::attach_internal(uint32_t pid) {
    // PROCESS_VM_READ is the minimum needed to read memory.
    // QUERY_INFORMATION helps with module enumeration edge cases.
    HANDLE h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION,
                           FALSE, pid);
    if (!h) return false;

    process_ = h;
    pid_     = pid;
    return true;
}

uintptr_t MemoryReader::module_base(std::wstring_view module_name) const {
    if (!process_) return 0;

    HANDLE snapshot = CreateToolhelp32Snapshot(
        TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid_);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;

    MODULEENTRY32W entry{};
    entry.dwSize = sizeof(entry);

    uintptr_t base = 0;
    if (Module32FirstW(snapshot, &entry)) {
        do {
            if (_wcsicmp(entry.szModule, std::wstring(module_name).c_str()) == 0) {
                base = reinterpret_cast<uintptr_t>(entry.modBaseAddr);
                break;
            }
        } while (Module32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return base;
}

bool MemoryReader::read_raw(uintptr_t address, void* buffer, size_t size) const {
    if (!process_ || !buffer || size == 0) return false;

    SIZE_T bytes_read = 0;
    BOOL ok = ReadProcessMemory(process_, reinterpret_cast<LPCVOID>(address),
                                buffer, size, &bytes_read);
    // Require a full read; partial reads indicate the region ended early.
    return ok && bytes_read == size;
}

std::optional<uintptr_t> MemoryReader::read_ptr(uintptr_t address) const {
    // Apex is x64, so pointers are 8 bytes.
    return read<uintptr_t>(address);
}

std::optional<std::string> MemoryReader::read_string(uintptr_t address,
                                                     size_t max_len) const {
    if (!process_ || max_len == 0) return std::nullopt;

    std::string buffer(max_len, '\0');
    SIZE_T bytes_read = 0;
    if (!ReadProcessMemory(process_, reinterpret_cast<LPCVOID>(address),
                           buffer.data(), max_len, &bytes_read)) {
        return std::nullopt;
    }

    // Truncate at first NUL within what was actually read.
    size_t len = strnlen(buffer.data(), bytes_read);
    buffer.resize(len);
    return buffer;
}

std::optional<uintptr_t> MemoryReader::resolve_chain(
    uintptr_t base, const std::vector<uintptr_t>& offsets) const {
    uintptr_t addr = base;
    for (uintptr_t off : offsets) {
        auto ptr = read_ptr(addr + off);
        if (!ptr || *ptr == 0) return std::nullopt;
        addr = *ptr;
    }
    return addr;
}

} // namespace apex


auto base = reader.module_base(L"r5apex.exe");
auto local = reader.resolve_chain(base + 0x23F6A78, {});
// or for multi-level: reader.resolve_chain(base, {0x23F6A78, 0x10})
