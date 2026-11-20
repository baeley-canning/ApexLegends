#include "drv.h"
#include <cstdio>
#include <cstdint>
#include <windows.h>
#include <fstream>
#include <cstring>
#include <sstream>
#include <algorithm>   // std::min/max needed for Dump() calls in step_02

#pragma warning(push)
#pragma warning(disable : 4505) // dead-code - will be fully wired at step 02+
static void Dump(const char* tag, uint64_t pa, const uint8_t* b, size_t n) {
    printf("%s 0x%llX: ", tag, (unsigned long long)pa);
    for (size_t i = 0; i < n; i++) printf("%02X ", b[i]);
    printf("\n");
}

static bool UniformFill(const uint8_t* b, size_t n) {
    for (size_t i = 1; i < n; i++) if (b[i] != b[0]) return false;
    return true;
}
#pragma warning(pop)


// ── STEP 01: probe every DWORD-aligned code in [base .. base + span), print table to console & VERIFY.md ────
int run_step_01(HANDLE dev, DWORD baseCode, int spanCodes) {
    printf("\n--- Step 01: IOCTL Probe Table [%08X ... %08X] (%d codes) ---\n",
           baseCode, static_cast<DWORD>(baseCode + ((spanCodes-1)*4)), spanCodes);

    std::ostringstream vf_stream;   // build full file content first
    
    vf_stream << "\n## Phase 1 -- " 
              << "[device label]"  
              << ": IOCTL scan at base=0x" << std::hex << baseCode << std::dec << "\n";
    vf_stream << "| Code | Ioctl rc | GetLastError | Notes |\n|------|----------|--------------|-------|\n";

    int okCount = 0, errFuncCount = 0;
    
    for (int i = 0; i < spanCodes; ++i) {
        DWORD code = static_cast<DWORD>(baseCode + i * 4);
        BYTE in_buf[64]{}, out_buf[64]{};
        
        BOOL succeeded = DeviceIoControl(dev, code, in_buf, sizeof(in_buf),
                                         out_buf, sizeof(out_buf), nullptr, nullptr);
        DWORD gle = GetLastError();
        
        const char* note = "";
        if (!succeeded && gle == ERROR_INVALID_FUNCTION) {
            note = "[UNVERIFIED] invalid function";
            ++errFuncCount;
        } else if (gle != NO_ERROR) {
            note = "(GLE not zero)";
        } else {
            ++okCount;
        }

        printf("  [0x%08X] -> %d GLE=%lu%s\n", code, succeeded ? 1 : 0, gle, 
               !note[0] ? "" : (" " + std::string(note)).c_str());
       
        // Write table row to VERIFY.md  
        vf_stream << "| 0x" << std::hex << code << std::dec
                  << " | " << (succeeded ? 1 : 0)
                  << " | " << gle
                  << " | " << (strlen(note)>0 ? note : "")
                  << " |\n";
    }
    
    vf_stream << "---\n";

    printf("\n--- Step 01 Summary: %d non-error, %d INVALID_FUNCTION out of %d probed ---\n\n",
           okCount, errFuncCount, spanCodes);

    // Persist the full probe table at once
    {
        FILE* fp = fopen("VERIFY.md", "a");   // append mode for multi-phase safety
        if (fp) {
            fputs(vf_stream.str().c_str(), fp);
            fclose(fp);
        }
    }
           
    return errFuncCount == static_cast<DWORD>(spanCodes) ? -1 : 0;   // all invalid -> device likely wrong
}


// ── STEP 02/03 smoke tests for the selected driver/device combination ────
void run_step_02(HANDLE dev) {
    printf("--- Step 02: Physical Read Smoke Test ---\n");
    
    uint8_t bufA[64]{}, bufB[64]{};
    
    bool rA = gdrv::ReadPhys(0x1000ULL,     bufA, sizeof(bufA));
    bool rB = gdrv::ReadPhys(0x100000ULL,    bufB, sizeof(bufB));
    
    printf("read 0x1000   : %s\n", rA ? "ok" : "FAIL");
    printf("read 0x100000 : %s\n", rB ? "ok" : "FAIL");

    if (rA) Dump("  @0x1000 ", static_cast<uint64_t>(0x1000), bufA, std::min(static_cast<size_t>(32), sizeof(bufA)));
    if (rB) Dump("  @0x100000", static_cast<uint64_t>(0x100000ull), bufB, std::min(static_cast<size_t>(32), sizeof(bufB)));

    // Uniform-fill check per Phase-1 acceptance criteria  
    if ((rA || rB)) {
        const char* which = nullptr;
        uint8_t* ubuf = nullptr; size_t ulen = 0;
        if (!rA && !UniformFill(bufA, sizeof(bufA))) { which="bufA"; ubuf=bufA; ulen=sizeof(bufA); }
        else if (!rB && !UniformFill(bufB, sizeof(bufB))) { which="bufB"; ubuf=bufB; ulen=sizeof(bufB); }
        
        bool bothUniform = rA && rB && UniformFill(bufA,sizeof(bufA)) && UniformFill(bufB,sizeof(bufB));
        printf("%s\n", bothUniform ? "WARN: BOTH reads uniform fill - mapping likely wrong" : "");
    }
}


// ── STEP 03: physical write + readback at EBDA scratch space (usually safe) ────
void run_step_03(HANDLE dev) {
    printf("--- Step 03: Physical Write Smoke Test ---\n");
    
    uint64_t testPA = 0x1800ULL;   // EBDA region - usually free/scratch
    
    uint8_t orig[2]{};
    gdrv::ReadPhys(testPA, orig, sizeof(orig));
    Dump("before_write", testPA, orig, sizeof(orig));

    uint8_t wByte = static_cast<uint8_t>(0x41);
    if (!gdrv::WritePhys(testPA, &wByte, 1)) {
        printf("[STEP 03] Write FAILED\n"); return;
    }

    uint8_t check = 0xFFu;
    gdrv::ReadPhys(testPA, &check, 1);
    printf("after write  : %02X (expected 41)\n", check);
    bool pass = (check == 0x41);
    printf("%s\n", pass ? "PASS" : "FAIL - mismatch");

    // Restore original byte  
    gdrv::WritePhys(testPA, orig, sizeof(orig));
    
    uint8_t restored = 0xFFu;
    gdrv::ReadPhys(testPA, &restored, 1);
    printf("restored     : %02X (was %02X) %s\n", 
           restored, orig[0], (restored==orig[0])?"OK":"MISMATCH");
}


int main(int argc, char* argv[]) {
    printf("=== gdrv Phase-1 Harness ===\n");
    printf("Usage: cheatv2 [device_path] [copy_base_hex] [label]\n\n");
    
    const char* device   = (argc > 1) ? argv[1] : "\\\\.\\\\DBUtil_2_3";
    DWORD       baseCode = (argc > 2) ? static_cast<DWORD>(strtoul(argv[2], nullptr, 16)) : 0x9B332000;
    const char* label    = (argc > 3) ? argv[3] : "DBUtilDrv_default";
    
    if (!gdrv::Open(device, baseCode)) return 1;

    HANDLE devHandle = gdrv::GetDeviceHandle();

    // STEP 01 -- probe table  
    int stepRc = run_step_01(devHandle, baseCode, 514);          // span ≈ (0xC350280F - C3502000)/4 + 1 or DBUtil equivalent
    
    // STEP 02/03 smoke tests on the live handle  
    run_step_02(devHandle);
    run_step_03(devHandle);

    printf("=== Phase-1 complete ===\n");
    return stepRc == 0 ? 0 : 2;
}
