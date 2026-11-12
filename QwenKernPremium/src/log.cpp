#include "log.h"

#include <cstdarg>
#include <cstdio>
#include <cwchar>

namespace {

FILE*    g_logFile = nullptr;
SRWLOCK  g_logLock = SRWLOCK_INIT;
wchar_t  g_logPath[MAX_PATH] = { 0 };

void EnsureDirectory(const wchar_t* path) {
    // Creates every missing component of `path` (a directory path, no trailing
    // separator).  Failures are ignored: CreateFile in LogInit reports them.
    wchar_t buffer[MAX_PATH] = { 0 };
    const size_t length = wcslen(path);
    if (length == 0 || length >= MAX_PATH) return;

    wcscpy_s(buffer, path);
    for (size_t i = 3; i < length; ++i) {          // skip "C:\"
        if (buffer[i] == L'\\') {
            buffer[i] = L'\0';
            CreateDirectoryW(buffer, nullptr);     // ERROR_ALREADY_EXISTS is fine
            buffer[i] = L'\\';
        }
    }
    CreateDirectoryW(buffer, nullptr);
}

} // namespace

bool LogInit(const wchar_t* tag) {
    AcquireSRWLockExclusive(&g_logLock);
    if (g_logFile) {
        ReleaseSRWLockExclusive(&g_logLock);
        return true;
    }

    wchar_t base[MAX_PATH] = { 0 };
    const DWORD envLength = GetEnvironmentVariableW(L"LOCALAPPDATA", base, MAX_PATH);
    if (envLength == 0 || envLength >= MAX_PATH) {
        // No profile (service context): fall back to the temp directory.
        if (GetTempPathW(MAX_PATH, base) == 0) {
            ReleaseSRWLockExclusive(&g_logLock);
            return false;
        }
    }

    wchar_t directory[MAX_PATH] = { 0 };
    swprintf_s(directory, L"%s\\QwenKern", base);
    EnsureDirectory(directory);

    const wchar_t* safeTag = (tag && *tag) ? tag : L"payload";
    swprintf_s(g_logPath, L"%s\\%s_%lu.log", directory, safeTag,
               static_cast<unsigned long>(GetCurrentProcessId()));

    if (_wfopen_s(&g_logFile, g_logPath, L"ab") != 0 || !g_logFile) {
        // Fallback: the payload's own directory.  If the game runs with a
        // restricted token or a hooked file path (anti-cheat jail), the profile
        // directory can be unwritable even though it exists.  The module
        // directory is where the loader found this DLL, and in this tree it is
        // always writable.  Same file name, different directory.
        g_logFile = nullptr;
        wchar_t self[MAX_PATH] = { 0 };
        HMODULE mine = nullptr;
        if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                               GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                               reinterpret_cast<LPCWSTR>(&LogInit), &mine) && mine) {
            GetModuleFileNameW(mine, self, MAX_PATH);
            wchar_t* slash = wcsrchr(self, L'\\');
            if (slash) *slash = L'\0';
            swprintf_s(g_logPath, L"%s\\%s_%lu.log", self, safeTag,
                       static_cast<unsigned long>(GetCurrentProcessId()));
            _wfopen_s(&g_logFile, g_logPath, L"ab");
        }
        if (!g_logFile) {
            g_logPath[0] = L'\0';
            ReleaseSRWLockExclusive(&g_logLock);
            return false;
        }
    }

    ReleaseSRWLockExclusive(&g_logLock);

    SYSTEMTIME now{};
    GetLocalTime(&now);
    Logf("==================== session start %04u-%02u-%02u %02u:%02u:%02u pid=%lu",
         now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond,
         static_cast<unsigned long>(GetCurrentProcessId()));
    return true;
}

void LogClose() {
    AcquireSRWLockExclusive(&g_logLock);
    if (g_logFile) {
        fclose(g_logFile);
        g_logFile = nullptr;
    }
    ReleaseSRWLockExclusive(&g_logLock);
}

const wchar_t* LogPath() {
    return g_logPath;
}

void Logf(const char* format, ...) {
    if (!format) return;

    char message[2048];
    va_list args;
    va_start(args, format);
    _vsnprintf_s(message, sizeof(message), _TRUNCATE, format, args);
    va_end(args);

    SYSTEMTIME now{};
    GetLocalTime(&now);

    AcquireSRWLockExclusive(&g_logLock);
    if (g_logFile) {
        fprintf(g_logFile, "[%02u:%02u:%02u.%03u] %s\r\n",
                now.wHour, now.wMinute, now.wSecond, now.wMilliseconds, message);
        // Flush every line: the process is usually killed by the anti-cheat or
        // the operator, never shut down cleanly.
        fflush(g_logFile);
    }
    ReleaseSRWLockExclusive(&g_logLock);
}
