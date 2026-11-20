// TRANSPORT: \\.\ApexDrv (apexdrv, tier T2 - a custom driver we load). DIAGNOSTIC PATH ONLY.
// The shipping reader is ext\qk_va.py on gdrv3 (tier T1 - parasitic, vendor-signed, already
// resident, never attaches). apexdrv attaches per IOCTL and is what killed the game in 14 s-4 min.

// ============================================================================
// tools\qk_probe.cpp — PLAN stage 1: the live read bridge (read-only).
//
// Answers ONE question, on the real game: "can OUR driver read r5apex_dx12 and
// is the game still alive 60 s later?"  That is the hole h328 left
// ("P3 driver-game SKIPPED (game not running)").
//
// What it does, in order, and nothing else:
//   1. open \\.\ApexDrv, VERSION must be >= 14 (refuse an older ABI);
//   2. BASE(pid) -> main image base, and record which source answered;
//   3. READBUF(base, 2) -> 'MZ';  READBUF(base+0x3C, 4) -> e_lfanew;
//      READ8 batch { sig, machine } -> 'PE\0\0' + 0x8664, using the per-item
//      status array (the ESP primitive: one dead pointer costs one item);
//   4. READBUF(base + e_lfanew, 0x100) -> Machine / NumberOfSections /
//      TimeDateStamp / SizeOfImage.  The build stamp is how a patch day is
//      detected later, for free;
//   5. liveness loop: every sample re-reads 'MZ' at the base and polls the
//      process.  A dead page or a dead process is the verdict, not a guess.
//
// Read-only: no write, no allocate, no service start/stop, nothing to restore
// (R4 is satisfied by construction).  Safe to re-run at any time.
//
// --self targets this very process and compares the driver's BASE against
// GetModuleHandle(NULL), so the tool is testable with no game running.
//
// Usage:
//   qk_probe.exe [--self] [--pid=N] [--secs=60] [--hz=1] [--out=FILE]
// Exit: 0 PASS, 2 no driver, 3 no target, 4 base/MZ/PE fail, 5 target died,
//       6 ABI too old, 7 window shorter than the 60 s gate.
// ============================================================================
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winioctl.h>      // CTL_CODE / METHOD_BUFFERED / FILE_ANY_ACCESS
#include <tlhelp32.h>
#include <stdio.h>
#include <share.h>          // _SH_DENYNO for _fsopen
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

#include "apex_driver_ioctl.h"

static FILE*  g_out = nullptr;
static DWORD  g_t0  = 0;

static void Say(const char* fmt, ...) {
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    vsprintf_s(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    printf("%s\n", buf);
    if (g_out) {
        fprintf(g_out, "%s\n", buf);
        fflush(g_out);              // R3: the file is the state feed, keep it current
    }
}

static unsigned ElapsedSec() {
    return (GetTickCount() - g_t0) / 1000u;
}

// ---------------------------------------------------------------------------
// driver client — one handle, four calls
// ---------------------------------------------------------------------------
static HANDLE DrvOpen(DWORD* err) {
    HANDLE h = CreateFileW(APEXDRV_WIN32_NAME, GENERIC_READ | GENERIC_WRITE,
                           0, nullptr, OPEN_EXISTING, 0, nullptr);
    if (err) *err = (h == INVALID_HANDLE_VALUE) ? GetLastError() : 0;
    return h;
}

static BOOL DrvVersion(HANDLE dev, ULONG* out, DWORD* err) {
    // 8 bytes, not 4: the driver reports Information=8 and METHOD_BUFFERED turns a
    // shorter output buffer into ERROR_INSUFFICIENT_BUFFER (122) - measured here.
    struct VersionReq { ULONG Version; ULONG Reserved; } req;
    memset(&req, 0, sizeof(req));
    DWORD ret = 0;
    const BOOL ok = DeviceIoControl(dev, IOCTL_APEXDRV_VERSION, &req, sizeof(req),
                                    &req, sizeof(req), &ret, nullptr);
    if (err) *err = ok ? 0 : GetLastError();
    if (ok && out) *out = req.Version;
    return ok;
}

// Returns the NTSTATUS in the response, or -1 when the IRP itself failed
// (in which case the out block was never copied back — the h283 lesson).
static LONG DrvBase(HANDLE dev, DWORD pid, ULONG* source, ULONG64* base, DWORD* err) {
    APEXDRV_BASE_REQUEST req;
    memset(&req, 0, sizeof(req));
    req.ProcessId = pid;
    DWORD ret = 0;
    const BOOL ok = DeviceIoControl(dev, IOCTL_APEXDRV_BASE, &req, sizeof(req),
                                    &req, sizeof(req), &ret, nullptr);
    if (err) *err = ok ? 0 : GetLastError();
    if (!ok) return -1;
    if (source) *source = req.Reserved2;
    if (base)   *base = req.Base;
    return req.Status;
}

static LONG DrvReadBuf(HANDLE dev, DWORD pid, ULONG64 addr, ULONG size, void* dst,
                       DWORD* err) {
    static APEXDRV_READBUF_REQUEST req;          // 4 KB + header: keep it off the stack
    memset(&req, 0, sizeof(req));
    req.ProcessId = pid;
    req.Size      = size;
    req.Address   = addr;
    DWORD ret = 0;
    const BOOL ok = DeviceIoControl(dev, IOCTL_APEXDRV_READBUF, &req, sizeof(req),
                                    &req, sizeof(req), &ret, nullptr);
    if (err) *err = ok ? 0 : GetLastError();
    if (!ok) return -1;
    if (req.Status == 0 && dst && size) memcpy(dst, req.Data, size);
    return req.Status;
}

// One batch of up to 64 independent 8-byte reads.  Per-item statuses come back
// in `status`; the return is the first non-zero status (0 when all read).
static LONG DrvRead8(HANDLE dev, DWORD pid, const ULONG64* addrs, ULONG count,
                     ULONG64* values, LONG* status, DWORD* err) {
    static APEXDRV_READ8_REQUEST req;             // ~1 KB: static, not stack
    memset(&req, 0, sizeof(req));
    if (count == 0 || count > APEXDRV_MAX_BATCH) { if (err) *err = 87; return -1; }
    req.ProcessId = pid;
    req.Count     = count;
    for (ULONG i = 0; i < count; ++i) req.Address[i] = addrs[i];
    DWORD ret = 0;
    const BOOL ok = DeviceIoControl(dev, IOCTL_APEXDRV_READ8, &req, sizeof(req),
                                    &req, sizeof(req), &ret, nullptr);
    if (err) *err = ok ? 0 : GetLastError();
    if (!ok) return -1;
    LONG first = 0;
    for (ULONG i = 0; i < count; ++i) {
        if (status) status[i] = req.Status[i];
        if (values) values[i] = req.Value[i];
        if (first == 0 && req.Status[i] != 0) first = req.Status[i];
    }
    return first;
}

// ---------------------------------------------------------------------------
// target discovery + liveness
// ---------------------------------------------------------------------------
static DWORD FindGamePid() {
    static const wchar_t* names[] = { L"r5apex_dx12.exe", L"r5apex.exe" };
    DWORD found = 0;
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return 0;
    for (size_t n = 0; n < sizeof(names) / sizeof(names[0]) && found == 0; ++n) {
        PROCESSENTRY32W pe;
        memset(&pe, 0, sizeof(pe));
        pe.dwSize = sizeof(pe);
        if (!Process32FirstW(snap, &pe)) break;
        do {
            if (_wcsicmp(pe.szExeFile, names[n]) == 0) { found = pe.th32ProcessID; break; }
        } while (Process32NextW(snap, &pe));
    }
    CloseHandle(snap);
    return found;
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

static BOOL ProcessAlive(DWORD pid) {
    HANDLE h = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!h) return FALSE;
    const DWORD wait = WaitForSingleObject(h, 0);
    CloseHandle(h);
    return wait == WAIT_TIMEOUT;              // still running, not signalled
}

static unsigned Rd16(const unsigned char* p) { return (unsigned)p[0] | ((unsigned)p[1] << 8); }
static unsigned Rd32(const unsigned char* p) {
    return (unsigned)p[0] | ((unsigned)p[1] << 8) | ((unsigned)p[2] << 16) | ((unsigned)p[3] << 24);
}

int main(int argc, char** argv) {
    g_t0 = GetTickCount();

    bool self = false;
    DWORD pidArg = 0;
    unsigned secs = 60, hz = 1;
    const char* outPath = "qk_probe_latest.txt";

    for (int i = 1; i < argc; ++i) {
        if (strncmp(argv[i], "--self", 6) == 0)        self = true;
        else if (strncmp(argv[i], "--pid=", 6) == 0)   pidArg = (DWORD)strtoul(argv[i] + 6, nullptr, 0);
        else if (strncmp(argv[i], "--secs=", 7) == 0)  secs = (unsigned)strtoul(argv[i] + 7, nullptr, 0);
        else if (strncmp(argv[i], "--hz=", 5) == 0)    hz = (unsigned)strtoul(argv[i] + 5, nullptr, 0);
        else if (strncmp(argv[i], "--out=", 6) == 0)   outPath = argv[i] + 6;
    }
    if (hz == 0) hz = 1;
    if (secs == 0) secs = 1;
    if (secs * hz > 600) secs = 600 / hz;      // never spin forever

    // _SH_DENYNO: a live 60 s run has to be tailable from another shell; an
    // exclusive fopen made Get-Content fail with "used by another process"
    // (measured), which is exactly when you need to watch it.
    g_out = _fsopen(outPath, "wb", _SH_DENYNO);

    Say("===== qk_probe v1 (PLAN stage 1: driver -> game read bridge, read-only) =====");
    Say("host=%s probe_pid=%lu self=%d secs=%u hz=%u out=%s",
        "DESKTOP-PPHFJBQ", (unsigned long)GetCurrentProcessId(), (int)self, secs, hz, outPath);

    DWORD ioErr = 0;
    HANDLE dev = DrvOpen(&ioErr);
    if (dev == INVALID_HANDLE_VALUE) {
        Say("driver: OPEN FAIL err=%lu (service not started?)", ioErr);
        Say("RESULT: driver-unavailable");
        Say("VERDICT: PARTIAL - variable = driver-backed BASE+READBUF on the game; game half SKIPPED");
        if (g_out) fclose(g_out);
        return 2;
    }
    ULONG abi = 0;
    if (!DrvVersion(dev, &abi, &ioErr)) {
        Say("driver: VERSION ioctl FAIL err=%lu", ioErr);
        Say("RESULT: abi-unknown");
        Say("VERDICT: PARTIAL - variable = driver-backed BASE+READBUF on the game; game half SKIPPED");
        CloseHandle(dev);
        if (g_out) fclose(g_out);
        return 2;
    }
    Say("driver: ABI v%lu (expect %d)", abi, (int)APEXDRV_VERSION);
    if (abi < APEXDRV_VERSION) {
        Say("RESULT: abi-too-old");
        Say("VERDICT: FAIL - driver ABI %lu < %d; rebuild/reload apexdrv before trusting reads",
            abi, (int)APEXDRV_VERSION);
        CloseHandle(dev);
        if (g_out) fclose(g_out);
        return 6;
    }

    const DWORD pid = self ? GetCurrentProcessId() : (pidArg ? pidArg : FindGamePid());
    if (pid == 0) {
        Say("target: NO r5apex_dx12.exe / r5apex.exe found and no --pid given");
        Say("RESULT: target-absent");
        Say("VERDICT: PARTIAL - variable = driver-backed BASE+READBUF on the game; game half SKIPPED");
        CloseHandle(dev);
        if (g_out) fclose(g_out);
        return 3;
    }
    Say("target: pid=%lu (%s)", (unsigned long)pid, self ? "self" : "game");

    // ---- BASE -------------------------------------------------------------
    ULONG source = 0;
    ULONG64 base = 0;
    const LONG stBase = DrvBase(dev, pid, &source, &base, &ioErr);
    Say("BASE: io=%s status=0x%08X source=%lu base=0x%llX",
        (stBase == -1) ? "FAIL" : "ok", (unsigned)stBase, source,
        (unsigned long long)base);
    if (stBase != 0 || base == 0) {
        Say("RESULT: base-failed (io_err=%lu)", ioErr);
        Say("VERDICT: FAIL - variable = BASE(pid); driver could not name the main image");
        CloseHandle(dev);
        if (g_out) fclose(g_out);
        return 4;
    }
    if (self) {
        const ULONG64 truth = (ULONG64)(ULONG_PTR)GetModuleHandleW(nullptr);
        Say("BASE self ground_truth=0x%llX match=%d",
            (unsigned long long)truth, (int)(truth == base));
        if (truth != base) {
            Say("RESULT: self-groundtruth-mismatch");
            Say("VERDICT: FAIL - variable = BASE(self) vs GetModuleHandle(NULL)");
            CloseHandle(dev);
            if (g_out) fclose(g_out);
            return 4;
        }
    }

    // ---- MZ + e_lfanew ----------------------------------------------------
    unsigned char mz[4] = { 0, 0, 0, 0 };
    LONG st = DrvReadBuf(dev, pid, base, 4, mz, &ioErr);
    Say("READBUF[4@base] status=0x%08X bytes=%02X %02X %02X %02X",
        (unsigned)st, mz[0], mz[1], mz[2], mz[3]);
    if (st != 0 || mz[0] != 'M' || mz[1] != 'Z') {
        Say("RESULT: not-an-image (status=0x%08X io_err=%lu)", (unsigned)st, ioErr);
        Say("VERDICT: FAIL - variable = READBUF(base,4) on the game; no 'MZ'");
        CloseHandle(dev);
        if (g_out) fclose(g_out);
        return 4;
    }

    unsigned char lfanewRaw[4] = { 0, 0, 0, 0 };
    st = DrvReadBuf(dev, pid, base + 0x3C, 4, lfanewRaw, &ioErr);
    const ULONG e_lfanew = Rd32(lfanewRaw);
    Say("READBUF[4@base+0x3C] status=0x%08X e_lfanew=0x%X", (unsigned)st, e_lfanew);
    if (st != 0 || e_lfanew < 0x40 || e_lfanew > 0x1000) {
        Say("RESULT: bad-lfanew");
        Say("VERDICT: FAIL - variable = READBUF(base+0x3C) e_lfanew");
        CloseHandle(dev);
        if (g_out) fclose(g_out);
        return 4;
    }

    // ---- READ8 batch: the ESP primitive, exercised for real ---------------
    {
        ULONG64 addrs[2];
        ULONG64 vals[2] = { 0, 0 };
        LONG    sts[2]  = { 0, 0 };
        addrs[0] = base + e_lfanew;        // 'PE\0\0'
        addrs[1] = base + e_lfanew + 4;    // Machine + NumberOfSections
        const LONG first = DrvRead8(dev, pid, addrs, 2, vals, sts, &ioErr);
        Say("READ8[2] first=0x%08X st0=0x%08X st1=0x%08X v0=0x%016llX",
            (unsigned)first, (unsigned)sts[0], (unsigned)sts[1],
            (unsigned long long)vals[0]);
        const unsigned sig = (unsigned)vals[0] & 0xFFFFFFFFu;   // 'PE\0\0' = 0x00004550
        if (first != 0 || sig != 0x00004550u) {
            Say("RESULT: no-PE-signature (got 0x%08X)", sig);
            Say("VERDICT: FAIL - variable = READ8 batch at the image base");
            CloseHandle(dev);
            if (g_out) fclose(g_out);
            return 4;
        }
        Say("READ8 signature=PE machine=0x%04X sections=%u",
            (unsigned)(vals[1] & 0xFFFFu), (unsigned)((vals[1] >> 16) & 0xFFFFu));
    }

    // ---- headers: identity of the build (the patch-day stamp) -------------
    {
        unsigned char hdr[0x100];
        memset(hdr, 0, sizeof(hdr));
        st = DrvReadBuf(dev, pid, base + e_lfanew, (ULONG)sizeof(hdr), hdr, &ioErr);
        if (st == 0) {
            const unsigned machine   = Rd16(hdr + 0x04);
            const unsigned nSections = Rd16(hdr + 0x06);
            const unsigned stamp     = Rd32(hdr + 0x08);
            const unsigned optMagic  = Rd16(hdr + 0x18);
            const unsigned sizeOfImg = Rd32(hdr + 0x50);   // OptionalHeader+0x38, PE32 and PE32+
            Say("PE: machine=0x%04X sections=%u stamp=0x%08X optMagic=0x%04X SizeOfImage=0x%X",
                machine, nSections, stamp, optMagic, sizeOfImg);
            Say("PE: build_stamp=%u (unix seconds) - the patch-day fingerprint", stamp);
        } else {
            Say("PE header read status=0x%08X (io_err=%lu) - identity line skipped",
                (unsigned)st, ioErr);
        }
    }

    // ---- liveness ---------------------------------------------------------
    Say("--- liveness: re-read MZ + poll the process every %u ms ---", 1000u / hz);
    unsigned samples = 0, good = 0, bad = 0;
    const unsigned total = secs * hz;
    for (unsigned i = 0; i < total; ++i) {
        Sleep(1000u / hz);
        unsigned char b[4] = { 0, 0, 0, 0 };
        const LONG s2 = DrvReadBuf(dev, pid, base, 4, b, &ioErr);
        const BOOL alive = ProcessAlive(pid);
        const BOOL mzOk = (s2 == 0 && b[0] == 'M' && b[1] == 'Z');
        ++samples;
        if (mzOk) ++good; else ++bad;
        Say("T+%02us read=0x%08X mz=%d proc=%d", ElapsedSec(), (unsigned)s2,
            (int)mzOk, (int)alive);
        if (!alive) break;
    }

    const BOOL aliveEnd = ProcessAlive(pid);
    Say("ALIVE samples=%u/%u good=%u bad=%u proc_end=%d elapsed=%us secs_gate=%u",
        samples, total, good, bad, (int)aliveEnd, ElapsedSec(), secs);
    Say("RESULT: base=0x%llX mz=1 pe=1 readbuf_good=%u/%u proc_alive=%d",
        (unsigned long long)base, good, samples, (int)aliveEnd);

    int rc = 0;
    if (!aliveEnd) {
        Say("VERDICT: FAIL - variable = driver-backed reads on a live pid; the target DIED in the window");
        rc = 5;
    } else if (self) {
        // A control, not the gate: the game half was never exercised (R9).
        Say("VERDICT: PARTIAL - SELF-MODE CONTROL (own pid): BASE+READ8+READBUF agree with "
            "ground truth, %u/%u samples clean at +%us; game half NOT exercised",
            good, samples, ElapsedSec());
        rc = 7;
    } else if (secs >= 60) {
        Say("VERDICT: PASS - variable = driver-backed BASE+READ8+READBUF on a live pid; "
            "MZ+PE at the base, %u/%u samples clean, process alive at +%us",
            good, samples, ElapsedSec());
    } else {
        Say("VERDICT: PARTIAL - variable = driver-backed BASE+READ8+READBUF; window %us < 60 s gate",
            secs);
        rc = 7;
    }
    CloseHandle(dev);
    if (g_out) fclose(g_out);
    return rc;
}




