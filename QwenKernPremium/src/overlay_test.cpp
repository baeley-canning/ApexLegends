// ============================================================================
// overlay_test.cpp — PHASE 1 / T1 (ov-series): standalone DX12 test target.
//
// NOT part of the payload DLL and NOT in apex_cheat.vcxproj: this exe links
// the REAL overlay translation unit (src\d3d12_overlay.cpp) into its own
// process, creates its own window + D3D12 swap chain, and drives the exact
// same Render() entry the Present hook calls (hooks.cpp
// DXGISwapChainPresentHook) — with NO vtable hook installed.
//
// One run proves, offline and without touching the game:
//   T2  filled quads, 5x7 bitmap text from quads, the menu (category strip,
//       bordered panels, checkbox/slider/choice/button widgets with the focused
//       row highlighted), ESP outline boxes via the real g_EspBoxes ring;
//   T3  MenuHandleKey navigation over the real page/panel/item tables: open
//       (INSERT), row selection, slider repeat, TAB category switch +
//       selection re-clamp, toggle + repeat suppression, BACKSPACE close,
//       pass-through of non-menu keys;
//   T4  ConfigManager::FlushFeatureToggles round-trip on a scratch ini, plus
//       the LIVE menu-toggle flush path (SharedMenuConfig writes apexcheat.ini
//       in the process working directory);
//   T5  the per-frame Present counter (PresentCount()), which Render() logs
//       every 600 frames through Logf into
//       %LOCALAPPDATA%\QwenKern\overlay_test_<pid>.log.
//
// The window clears to a KNOWN background (an opaque full-screen quad pushed
// first each frame) and draws static content, so a screenshot is a stable
// visual test (evidence: _ritual\ov3_test.png + ov4 OCR).
//
// Usage:  overlay_test.exe [--seconds N] [--outdir DIR] [--late-queue N]
//                          [--menu-tab N]
//   --late-queue N  do not hand the overlay its queue up front; deliver it at
//                   frame N instead.  That is the in-game order (the queue only
//                   arrives from the ExecuteCommandLists hook): the renderer has
//                   to build on a private queue, hold the frames and switch.
//   --menu-tab N    leave the open menu on category N (0 AIMBOT .. 4 MISC) so
//                   each category can be captured as its own screenshot.
// Exit code 0 = RESULT: PASS, 2 = FAIL.  Writes <outdir>\ov_test_result.txt.
// ============================================================================

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <d3d12.h>
#include <d3d12sdklayers.h>
#include <dxgi1_4.h>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <string>

#include "d3d12_overlay.h"
#include "features.h"
#include "config.h"
#include "log.h"

namespace {

const UINT kWidth  = 960;
const UINT kHeight = 620;

struct Run {
    std::string outdir;
    int         seconds  = 14;
    int         frames   = 0;
    bool        renderOk = true;
    bool        cfgRt    = false;
    bool        menuLive = false;
    bool        navOk    = false;
    // --menu-tab N: leave the menu open on category N when the frames start, so
    // a screenshot per category is one run with one different argument.  -1 =
    // the T3 default (VISUALS with GLOW toggled on).
    int         menuTab = -1;
    // --late-queue N: do NOT hand the overlay its queue before the frames start.
    // The renderer must then build itself on a private queue, hold the frames
    // (SetQueueWaitFrames budget) and switch over once the queue arrives at frame
    // N — the exact in-game order, where the queue only shows up from the
    // ExecuteCommandLists hook.  -1 = off (queue handed over before frame 1).
    int         lateQueue = -1;
    bool        queueDelivered = false;
    int         heldFrames = 0;
    FILE*       result   = nullptr;

    // live client size (pixels).  Everything — chain, viewport, background —
    // derives from THIS, never from the kWidth/kHeight request (T6).
    UINT        cw        = 0;
    UINT        ch        = 0;
    int         presentFails = 0;
    bool        covDone   = false;
    bool        iqDone    = false;
    double      coverage  = 0.0;   // fraction of non-white pixels, 0..1
    LONG        bx0 = 0, by0 = 0, bx1 = 0, by1 = 0;   // bbox of drawn pixels
};

void Say(Run& r, const char* fmt, ...) {
    char line[1024];
    va_list args;
    va_start(args, fmt);
    _vsnprintf_s(line, sizeof(line), _TRUNCATE, fmt, args);
    va_end(args);
    if (r.result) fprintf(r.result, "%s\r\n", line);
    Logf("[test] %s", line);
}

LRESULT CALLBACK TestWndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == WM_DESTROY) { PostQuitMessage(0); return 0; }
    if (msg == WM_KEYDOWN && wp == VK_ESCAPE) { DestroyWindow(hwnd); return 0; }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

// T4 dedicated round-trip: write the seven feature keys, re-read with a fresh
// ConfigManager, compare.  Uses its own file so no real preset is touched.
bool ConfigRoundTrip(const std::string& path, Run& r) {
    DeleteFileA(path.c_str());          // a previous run's file is stale (R5)
    {
        ConfigManager writer(path);
        (void)writer.LoadConfig();      // a missing file just creates defaults
        if (!writer.FlushFeatureToggles(true, false, true, false,
                                        true, false, true)) {
            Say(r, "T4 round-trip FAIL: FlushFeatureToggles (write) returned false");
            return false;
        }
    }
    ConfigManager reader(path);
    if (!reader.LoadConfig()) {
        Say(r, "T4 round-trip FAIL: LoadConfig (read-back) returned false");
        return false;
    }
    const bool aimbot = reader.GetBoolValue("aimbot", false);
    const bool esp    = reader.GetBoolValue("esp", false);
    const bool glow   = reader.GetBoolValue("glow", false);
    const bool recoil = reader.GetBoolValue("recoil", false);
    const bool boxes  = reader.GetBoolValue("esp_boxes", false);
    const bool names  = reader.GetBoolValue("esp_names", false);
    const bool lines  = reader.GetBoolValue("esp_lines", false);
    const bool ok = aimbot && !esp && glow && !recoil && boxes && !names && lines;
    Say(r, "T4 round-trip %s: aimbot=%d esp=%d glow=%d recoil=%d boxes=%d names=%d lines=%d",
        ok ? "PASS" : "FAIL", aimbot ? 1 : 0, esp ? 1 : 0, glow ? 1 : 0,
        recoil ? 1 : 0, boxes ? 1 : 0, names ? 1 : 0, lines ? 1 : 0);
    return ok;
}

} // namespace
// ============================================================================
// T6 — coverage probe: copy the buffer we just drew into to a READBACK heap and
// measure it.  The buffer is ground truth; the screen path (DWM, capture, OCR)
// is not.  Also dumps it to ov_buffer.bmp so the pixels can be inspected even
// when the window compositing path lies.
// ============================================================================
namespace {

const UINT kWhiteBgra = 0xFFFFFFFFu;   // untouched flip-model buffer content

// Dumps the device's debug-layer messages: the queue/back-buffer errors that a
// bare Present HRESULT only hints at.  Harness wiring, not product code.
void DumpInfoQueue(ID3D12Device* device, Run& r) {
    ID3D12InfoQueue* iq = nullptr;
    if (!device || FAILED(device->QueryInterface(__uuidof(ID3D12InfoQueue),
                                                 reinterpret_cast<void**>(&iq))) || !iq) {
        Say(r, "T7 info queue: unavailable (debug layer off?)");
        return;
    }
    const UINT64 n = iq->GetNumStoredMessages();
    Say(r, "T7 info queue: %llu stored message(s)", static_cast<unsigned long long>(n));
    const UINT64 limit = n < 12 ? n : 12;
    for (UINT64 i = 0; i < limit; ++i) {
        SIZE_T len = 0;
        if (FAILED(iq->GetMessage(i, nullptr, &len)) || len == 0) continue;
        std::string buf(len, '\0');
        D3D12_MESSAGE* m = reinterpret_cast<D3D12_MESSAGE*>(&buf[0]);
        if (FAILED(iq->GetMessage(i, m, &len))) continue;
        std::string text = m->pDescription ? m->pDescription : "(null)";
        if (text.size() > 900) text.resize(900);
        for (char& c : text) if (c == '\r' || c == '\n') c = ' ';
        Say(r, "T7 [%d id=%d] %s", static_cast<int>(m->Severity),
            static_cast<int>(m->ID), text.c_str());
    }
    iq->Release();
}

// Bypasses the overlay entirely: clears the back buffer on the queue that
// CREATED the chain.  Splits "our submit path is bad" from "a second queue is
// bad" without touching product code.
bool DirectClearTest(ID3D12Device* device, ID3D12CommandQueue* queue,
                     IDXGISwapChain* chain, UINT index, Run& r, bool doClear = true) {
    ID3D12Resource* bb = nullptr;
    if (FAILED(chain->GetBuffer(index, __uuidof(ID3D12Resource),
                               reinterpret_cast<void**>(&bb))) || !bb) {
        Say(r, "T8 direct clear[%u]: GetBuffer failed", index);
        return false;
    }

    D3D12_RESOURCE_DESC bd = bb->GetDesc();
    Say(r, "T8 buffer[%u] desc: %llux%u fmt=%u samples=%u mips=%u flags=0x%X",
        index, static_cast<unsigned long long>(bd.Width), bd.Height,
        static_cast<unsigned>(bd.Format), bd.SampleDesc.Count, bd.MipLevels,
        static_cast<unsigned>(bd.Flags));

    D3D12_DESCRIPTOR_HEAP_DESC hd = {};
    hd.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
    hd.NumDescriptors = 1;
    ID3D12DescriptorHeap* heap = nullptr;
    HRESULT hr = device->CreateDescriptorHeap(&hd, __uuidof(ID3D12DescriptorHeap),
                                              reinterpret_cast<void**>(&heap));
    if (SUCCEEDED(hr) && heap) {
        // explicit view desc: covers the case where the null-desc path derives a
        // wrong view for a non-current back buffer
        D3D12_RENDER_TARGET_VIEW_DESC rvd = {};
        rvd.Format        = bd.Format;
        rvd.ViewDimension = D3D12_RTV_DIMENSION_TEXTURE2D;
        rvd.Texture2D.MipSlice   = 0;
        rvd.Texture2D.PlaneSlice = 0;
        device->CreateRenderTargetView(bb, &rvd,
                                       heap->GetCPUDescriptorHandleForHeapStart());
    }

    ID3D12CommandAllocator* alloc = nullptr;
    ID3D12GraphicsCommandList* list = nullptr;
    ID3D12Fence* fence = nullptr;
    HANDLE ev = nullptr;
    bool ok = false;
    do {
        if (FAILED(hr) || !heap) { Say(r, "T8 direct clear: RTV failed"); break; }
        if (FAILED(device->CreateCommandAllocator(
                D3D12_COMMAND_LIST_TYPE_DIRECT, __uuidof(ID3D12CommandAllocator),
                reinterpret_cast<void**>(&alloc)))) break;
        if (FAILED(device->CreateCommandList(
                0, D3D12_COMMAND_LIST_TYPE_DIRECT, alloc, nullptr,
                __uuidof(ID3D12GraphicsCommandList),
                reinterpret_cast<void**>(&list)))) break;
        if (FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_NONE,
                                       __uuidof(ID3D12Fence),
                                       reinterpret_cast<void**>(&fence)))) break;
        ev = CreateEventW(nullptr, FALSE, FALSE, nullptr);
        if (!ev) break;

        D3D12_RESOURCE_BARRIER b = {};
        b.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        b.Transition.pResource   = bb;
        b.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        // COMMON, not PRESENT: only the current back buffer is really in PRESENT,
        // the others are still COMMON and a declared PRESENT->RT transition on
        // them faults the GPU (DEVICE_REMOVED / ACCESS_DENIED).
        b.Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
        b.Transition.StateAfter  = D3D12_RESOURCE_STATE_RENDER_TARGET;
        list->ResourceBarrier(1, &b);

        D3D12_CPU_DESCRIPTOR_HANDLE rtv = heap->GetCPUDescriptorHandleForHeapStart();
        if (doClear) {
            const float green[4] = { 0.2f, 0.8f, 0.2f, 1.0f };
            list->OMSetRenderTargets(1, &rtv, FALSE, nullptr);
            list->ClearRenderTargetView(rtv, green, 0, nullptr);
        }

        b.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
        b.Transition.StateAfter  = D3D12_RESOURCE_STATE_PRESENT;
        list->ResourceBarrier(1, &b);
        if (FAILED(list->Close())) { Say(r, "T8 direct clear: Close failed"); break; }

        ID3D12CommandList* lists[1] = { list };
        queue->ExecuteCommandLists(1, lists);
        if (FAILED(fence->SetEventOnCompletion(1, ev))) break;
        if (FAILED(queue->Signal(fence, 1))) break;
        if (WaitForSingleObject(ev, 5000) != WAIT_OBJECT_0) {
            Say(r, "T8 direct clear: fence timeout");
            break;
        }

        const HRESULT rr = device->GetDeviceRemovedReason();
        Say(r, "T8 direct clear[%u]: removedReason=0x%08X", index,
            static_cast<unsigned>(rr));
        ok = SUCCEEDED(rr);
    } while (false);

    if (ev) CloseHandle(ev);
    if (fence) fence->Release();
    if (list) list->Release();
    if (alloc) alloc->Release();
    if (heap) heap->Release();
    bb->Release();
    return ok;
}

bool WriteBmp(const char* path, const unsigned char* px, UINT w, UINT h, UINT pitch) {
    FILE* f = fopen(path, "wb");
    if (!f) return false;
    const unsigned long long imgBytes = 4ull * w * h;
    BITMAPFILEHEADER fh = {};
    fh.bfType = 0x4D42;                       // 'BM'
    fh.bfOffBits = sizeof(fh) + sizeof(BITMAPINFOHEADER);
    fh.bfSize = static_cast<DWORD>(fh.bfOffBits + imgBytes);
    BITMAPINFOHEADER ih = {};
    ih.biSize = sizeof(ih);
    ih.biWidth = static_cast<LONG>(w);
    ih.biHeight = -static_cast<LONG>(h);       // top-down rows
    ih.biPlanes = 1;
    ih.biBitCount = 32;
    ih.biCompression = BI_RGB;
    ih.biSizeImage = static_cast<DWORD>(imgBytes);
    fwrite(&fh, sizeof(fh), 1, f);
    fwrite(&ih, sizeof(ih), 1, f);
    for (UINT y = 0; y < h; ++y) {             // RowPitch is >= w * 4
        fwrite(px + static_cast<size_t>(y) * pitch, 4ull * w, 1, f);
    }
    fflush(f);
    fclose(f);
    return true;
}

// Maps the drawn back buffer, counts non-white pixels (bbox + ratio) and writes
// ov_buffer.bmp.  Returns false when the readback itself failed.
bool MeasureCoverage(ID3D12Device* device, ID3D12CommandQueue* queue,
                     IDXGISwapChain* chain, UINT bufferIndex, Run& r) {
    if (!device || !queue || !chain || r.cw == 0 || r.ch == 0) return false;

    ID3D12Resource* bb = nullptr;
    if (FAILED(chain->GetBuffer(bufferIndex, __uuidof(ID3D12Resource),
                               reinterpret_cast<void**>(&bb))) || !bb) {
        return false;
    }

    // D3D12 readback heaps are buffer-only: copy the texture into a placed
    // footprint in a readback BUFFER (a readback texture is E_INVALIDARG).
    const D3D12_RESOURCE_DESC texDesc = bb->GetDesc();
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT fp = {};
    UINT   numRows = 0;
    UINT64 rowBytes = 0;
    UINT64 totalBytes = 0;
    device->GetCopyableFootprints(&texDesc, 0, 1, 0, &fp, &numRows, &rowBytes,
                                  &totalBytes);
    if (totalBytes == 0) {
        Say(r, "T6 readback: footprint 0 for buf=%u", bufferIndex);
        bb->Release();
        return false;
    }

    D3D12_HEAP_PROPERTIES hp = {};
    hp.Type = D3D12_HEAP_TYPE_READBACK;
    hp.CreationNodeMask = 1;
    hp.VisibleNodeMask  = 1;

    D3D12_RESOURCE_DESC rd = {};
    rd.Dimension        = D3D12_RESOURCE_DIMENSION_BUFFER;
    rd.Alignment        = 0;
    rd.Width            = totalBytes;
    rd.Height           = 1;
    rd.DepthOrArraySize = 1;
    rd.MipLevels        = 1;
    rd.Format           = DXGI_FORMAT_UNKNOWN;
    rd.SampleDesc.Count = 1;
    rd.Layout           = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    rd.Flags            = D3D12_RESOURCE_FLAG_NONE;

    ID3D12Resource* rb = nullptr;
    HRESULT hr = device->CreateCommittedResource(
        &hp, D3D12_HEAP_FLAG_NONE, &rd, D3D12_RESOURCE_STATE_COPY_DEST,
        nullptr, __uuidof(ID3D12Resource), reinterpret_cast<void**>(&rb));
    if (FAILED(hr) || !rb) {
        Say(r, "T6 readback: CreateCommittedResource hr=0x%08X buf=%u",
            static_cast<unsigned>(hr), bufferIndex);
        bb->Release();
        return false;
    }

    ID3D12CommandAllocator* alloc = nullptr;
    ID3D12GraphicsCommandList* list = nullptr;
    ID3D12Fence* fence = nullptr;
    HANDLE ev = nullptr;
    bool ok = false;
    do {
        if (FAILED(device->CreateCommandAllocator(
                D3D12_COMMAND_LIST_TYPE_DIRECT, __uuidof(ID3D12CommandAllocator),
                reinterpret_cast<void**>(&alloc)))) break;
        if (FAILED(device->CreateCommandList(
                0, D3D12_COMMAND_LIST_TYPE_DIRECT, alloc, nullptr,
                __uuidof(ID3D12GraphicsCommandList),
                reinterpret_cast<void**>(&list)))) break;
        if (FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_NONE,
                                       __uuidof(ID3D12Fence),
                                       reinterpret_cast<void**>(&fence)))) break;
        ev = CreateEventW(nullptr, FALSE, FALSE, nullptr);
        if (!ev) break;

        D3D12_RESOURCE_BARRIER b = {};
        b.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        b.Transition.pResource   = bb;
        b.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        b.Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT;
        b.Transition.StateAfter  = D3D12_RESOURCE_STATE_COPY_SOURCE;
        list->ResourceBarrier(1, &b);
        D3D12_TEXTURE_COPY_LOCATION src = {};
        src.pResource        = bb;
        src.Type             = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
        src.SubresourceIndex = 0;
        D3D12_TEXTURE_COPY_LOCATION dst = {};
        dst.pResource       = rb;
        dst.Type            = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
        dst.PlacedFootprint = fp;
        list->CopyTextureRegion(&dst, 0, 0, 0, &src, nullptr);
        b.Transition.StateBefore = D3D12_RESOURCE_STATE_COPY_SOURCE;
        b.Transition.StateAfter  = D3D12_RESOURCE_STATE_PRESENT;
        list->ResourceBarrier(1, &b);
        if (FAILED(list->Close())) break;

        ID3D12CommandList* lists[1] = { list };
        queue->ExecuteCommandLists(1, lists);
        if (FAILED(fence->SetEventOnCompletion(1, ev))) break;
        if (FAILED(queue->Signal(fence, 1))) break;
        if (WaitForSingleObject(ev, 5000) != WAIT_OBJECT_0) {
            Say(r, "T6 readback: fence timeout, removed=0x%08X",
                static_cast<unsigned>(device->GetDeviceRemovedReason()));
            break;
        }

        void* mapped = nullptr;
        const D3D12_RANGE rr = { 0, static_cast<SIZE_T>(totalBytes) };
        if (FAILED(rb->Map(0, &rr, &mapped)) || !mapped) {
            Say(r, "T6 readback: Map failed");
            break;
        }

        const unsigned char* px = static_cast<const unsigned char*>(mapped);
        const UINT pitch = fp.Footprint.RowPitch;
        unsigned long long drawn = 0;
        LONG x0 = LONG_MAX, y0 = LONG_MAX, x1 = -1, y1 = -1;
        for (UINT y = 0; y < r.ch; ++y) {
            const unsigned* row =
                reinterpret_cast<const unsigned*>(px + static_cast<size_t>(y) * pitch);
            for (UINT x = 0; x < r.cw; ++x) {
                if (row[x] == kWhiteBgra) continue;
                ++drawn;
                if (static_cast<LONG>(x) < x0) x0 = static_cast<LONG>(x);
                if (static_cast<LONG>(y) < y0) y0 = static_cast<LONG>(y);
                if (static_cast<LONG>(x) > x1) x1 = static_cast<LONG>(x);
                if (static_cast<LONG>(y) > y1) y1 = static_cast<LONG>(y);
            }
        }
        r.coverage = static_cast<double>(drawn) /
                     (static_cast<double>(r.cw) * static_cast<double>(r.ch));
        r.bx0 = (x0 == LONG_MAX) ? 0 : x0;
        r.by0 = (y0 == LONG_MAX) ? 0 : y0;
        r.bx1 = (x1 < 0) ? 0 : x1;
        r.by1 = (y1 < 0) ? 0 : y1;
        (void)WriteBmp((r.outdir + "\\ov_buffer.bmp").c_str(), px, r.cw, r.ch, pitch);

        const D3D12_RANGE wr = { 0, 0 };
        rb->Unmap(0, &wr);
        ok = true;
    } while (false);

    if (ev) CloseHandle(ev);
    if (fence) fence->Release();
    if (list) list->Release();
    if (alloc) alloc->Release();
    rb->Release();
    bb->Release();
    return ok;
}
// __PART2__

} // namespace
// ============================================================================
// wWinMain
// ============================================================================

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE, PWSTR cmdLine, int) {
    Run r;

    // ---- args ----------------------------------------------------------------
    {
        const std::wstring args(cmdLine ? cmdLine : L"");
        size_t p = args.find(L"--seconds ");
        if (p != std::wstring::npos) {
            r.seconds = _wtoi(args.c_str() + p + 10);
            if (r.seconds <= 0) r.seconds = 14;
        }
        p = args.find(L"--late-queue ");
        if (p != std::wstring::npos) {
            r.lateQueue = _wtoi(args.c_str() + p + 13);
            if (r.lateQueue < 0) r.lateQueue = 0;
        }
        p = args.find(L"--menu-tab ");
        if (p != std::wstring::npos) {
            r.menuTab = _wtoi(args.c_str() + p + 11);
            if (r.menuTab < 0) r.menuTab = 0;
        }
        p = args.find(L"--outdir ");
        if (p != std::wstring::npos) {
            std::wstring d = args.substr(p + 9);
            if (!d.empty() && d.front() == L'"') {
                // quoted path: read to the closing quote (spaces are legal)
                const size_t e = d.find(L'"', 1);
                if (e != std::wstring::npos) d.resize(e);
                d.erase(0, 1);
            } else {
                const size_t e = d.find(L' ');
                if (e != std::wstring::npos) d.resize(e);
            }
            std::string narrow;                       // scratch dirs are ASCII
            for (wchar_t ch : d) narrow.push_back(static_cast<char>(ch));
            r.outdir = narrow;
        }
        if (r.outdir.empty()) r.outdir = ".";
    }

    LogInit(L"overlay_test");
    const std::string resultPath = r.outdir + "\\ov_test_result.txt";
    r.result = fopen(resultPath.c_str(), "wb");
    Say(r, "overlay_test start: seconds=%d outdir=%s size=%ux%u",
        r.seconds, r.outdir.c_str(), kWidth, kHeight);

    // ---- T4: dedicated round-trip file ---------------------------------------
    r.cfgRt = ConfigRoundTrip(r.outdir + "\\ov_rt.ini", r);

    // ---- window ---------------------------------------------------------------
    // DPI awareness BEFORE any window math: under virtualisation AdjustWindowRect
    // and the client rect disagree with the physical pixels and DXGI stretches
    // the buffer to the real client.
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    WNDCLASSW wc = {};
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = TestWndProc;
    wc.hInstance = inst;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = L"QwenKernOverlayTestClass";
    if (!RegisterClassW(&wc)) {
        Say(r, "FAIL: RegisterClassW error=%lu", GetLastError());
        if (r.result) fclose(r.result);
        LogClose();
        return 2;
    }
    RECT rc = { 0, 0, static_cast<LONG>(kWidth), static_cast<LONG>(kHeight) };
    AdjustWindowRect(&rc, WS_OVERLAPPEDWINDOW, FALSE);
    HWND hwnd = CreateWindowW(L"QwenKernOverlayTestClass", L"QwenKern Overlay Test",
                              WS_OVERLAPPEDWINDOW, 80, 60,
                              rc.right - rc.left, rc.bottom - rc.top,
                              nullptr, nullptr, inst, nullptr);
    if (!hwnd) {
        Say(r, "FAIL: CreateWindowW error=%lu", GetLastError());
        if (r.result) fclose(r.result);
        LogClose();
        return 2;
    }

    // A FLIP-model chain created on a HIDDEN window is not composed by DWM:
    // Present() then takes the "occluded" fast path (that is why the loop used
    // to run at 20k fps) and the client keeps its bare GDI background.  Show the
    // window, let it settle, and take the size from the LIVE client rect — the
    // chain, the viewport and the background quad all use this one number.
    ShowWindow(hwnd, SW_SHOWNORMAL);
    UpdateWindow(hwnd);
    {
        RECT crc = { 0, 0, 0, 0 };
        GetClientRect(hwnd, &crc);
        r.cw = static_cast<UINT>(crc.right - crc.left);
        r.ch = static_cast<UINT>(crc.bottom - crc.top);
    }
    Say(r, "client rect: %ux%u (requested %ux%u, dpi-aware)", r.cw, r.ch,
        kWidth, kHeight);
    if (r.cw < 320 || r.ch < 240) {
        Say(r, "FAIL: live client %ux%u under 320x240", r.cw, r.ch);
        if (r.result) fclose(r.result);
        LogClose();
        return 2;
    }

    // Debug layer ON (harness only): it names the exact call that kills the
    // device instead of leaving us with a bare DXGI_ERROR_DEVICE_REMOVED.
    {
        ID3D12Debug* dbg = nullptr;
        if (SUCCEEDED(D3D12GetDebugInterface(__uuidof(ID3D12Debug),
                                             reinterpret_cast<void**>(&dbg))) && dbg) {
            dbg->EnableDebugLayer();
            dbg->Release();
            Say(r, "debug layer: enabled");
        } else {
            Say(r, "debug layer: NOT available");
        }
    }

    // ---- D3D12 device / queue / swap chain ------------------------------------
    // This box is HYBRID: Intel UHD 730 + RTX 5060.  A device on the *wrong*
    // adapter creates fine and then the FIRST Present returns
    // DXGI_ERROR_DEVICE_REMOVED with removedReason DXGI_ERROR_ACCESS_DENIED
    // (0x887A002B) - it cannot reach the window's output.  Only DXGI can judge
    // that, so probe every adapter (WARP last) with one real Present and keep the
    // first device+queue+chain pair that survives.
    ID3D12Device* device = nullptr;
    ID3D12CommandQueue* queue = nullptr;
    IDXGIFactory4* factory = nullptr;
    IDXGISwapChain* chain = nullptr;

    DXGI_SWAP_CHAIN_DESC1 scd = {};
    scd.Width       = r.cw;
    scd.Height      = r.ch;
    scd.Format      = DXGI_FORMAT_B8G8R8A8_UNORM;
    scd.Stereo      = FALSE;
    scd.SampleDesc.Count  = 1;
    scd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    // BLIT model, not flip: with FLIP_DISCARD every back buffer except index 0
    // removed the device (DEVICE_REMOVED / removedReason ACCESS_DENIED) on all
    // three adapters here, even Microsoft Basic Render.  With DISCARD the single
    // back buffer is a plain render target and the whole path works.  DISCARD is
    // only accepted by the LEGACY IDXGIFactory::CreateSwapChain (see below).
    scd.BufferCount = 2;
    scd.Scaling     = DXGI_SCALING_STRETCH;
    scd.SwapEffect  = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    scd.AlphaMode   = DXGI_ALPHA_MODE_UNSPECIFIED;

    DXGI_SWAP_CHAIN_DESC scdLegacy = {};
    scdLegacy.BufferDesc.Width  = r.cw;
    scdLegacy.BufferDesc.Height = r.ch;
    scdLegacy.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    scdLegacy.SampleDesc.Count  = 1;
    scdLegacy.BufferUsage       = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    scdLegacy.BufferCount       = 1;
    scdLegacy.OutputWindow      = hwnd;
    scdLegacy.Windowed          = TRUE;
    scdLegacy.SwapEffect        = DXGI_SWAP_EFFECT_DISCARD;

    HRESULT hr = CreateDXGIFactory1(__uuidof(IDXGIFactory4),
                                    reinterpret_cast<void**>(&factory));

    IDXGIAdapter1* cands[8] = {};
    UINT candCount = 0;
    if (SUCCEEDED(hr)) {
        for (UINT i = 0; candCount < 6; ++i) {
            IDXGIAdapter1* a = nullptr;
            if (factory->EnumAdapters1(i, &a) == DXGI_ERROR_NOT_FOUND) break;
            DXGI_ADAPTER_DESC1 d = {};
            a->GetDesc1(&d);
            if (d.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) { a->Release(); continue; }
            cands[candCount++] = a;
        }
        IDXGIAdapter1* warp = nullptr;
        if (SUCCEEDED(factory->EnumWarpAdapter(__uuidof(IDXGIAdapter1),
                                             reinterpret_cast<void**>(&warp))) && warp) {
            cands[candCount++] = warp;      // last resort: always presents
        }
    }

    for (UINT i = 0; i < candCount && !chain; ++i) {
        DXGI_ADAPTER_DESC1 ad = {};
        char name[256] = {};
        if (SUCCEEDED(cands[i]->GetDesc1(&ad))) {
            WideCharToMultiByte(CP_ACP, 0, ad.Description, -1, name,
                                sizeof(name) - 1, nullptr, nullptr);
        }

        ID3D12Device* dev = nullptr;
        ID3D12CommandQueue* q = nullptr;
        IDXGISwapChain* ch = nullptr;
        HRESULT h = D3D12CreateDevice(cands[i], D3D_FEATURE_LEVEL_11_0,
                                      __uuidof(ID3D12Device),
                                      reinterpret_cast<void**>(&dev));
        if (SUCCEEDED(h)) {
            D3D12_COMMAND_QUEUE_DESC qd = {};
            qd.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
            h = dev->CreateCommandQueue(&qd, __uuidof(ID3D12CommandQueue),
                                        reinterpret_cast<void**>(&q));
        }
        if (SUCCEEDED(h)) {
            // CreateSwapChainForHwnd (the D3D12-entry point) with a flip model;
            // the blit model is D3D11-only for D3D12 (INVALID_CALL).
            IDXGISwapChain1* ch1 = nullptr;
            h = factory->CreateSwapChainForHwnd(q, hwnd, &scd, nullptr, nullptr, &ch1);
            if (SUCCEEDED(h) && ch1) {
                h = ch1->QueryInterface(__uuidof(IDXGISwapChain),
                                        reinterpret_cast<void**>(&ch));
                DXGI_SWAP_CHAIN_DESC cd = {};
                if (ch && SUCCEEDED(ch->GetDesc(&cd))) {
                    Say(r, "chain desc: buffers=%u %ux%u fmt=%u effect=%u hwnd=%p",
                        cd.BufferCount, cd.BufferDesc.Width, cd.BufferDesc.Height,
                        static_cast<unsigned>(cd.BufferDesc.Format),
                        static_cast<unsigned>(cd.SwapEffect), cd.OutputWindow);
                }
                IDXGISwapChain3* c3 = nullptr;
                if (ch && SUCCEEDED(ch->QueryInterface(__uuidof(IDXGISwapChain3),
                                                       reinterpret_cast<void**>(&c3))) && c3) {
                    Say(r, "chain current back buffer index = %u",
                        c3->GetCurrentBackBufferIndex());
                    c3->Release();
                }
                IDXGISwapChain2* c2 = nullptr;
                if (ch && SUCCEEDED(ch->QueryInterface(__uuidof(IDXGISwapChain2),
                                                       reinterpret_cast<void**>(&c2))) && c2) {
                    Say(r, "SetMaximumFrameLatency(3) hr=0x%08X",
                        static_cast<unsigned>(c2->SetMaximumFrameLatency(3)));
                    c2->Release();
                }
                for (UINT probe = 0; ch && probe < 4; ++probe) {
                    ID3D12Resource* tmp = nullptr;
                    const HRESULT gh = ch->GetBuffer(probe, __uuidof(ID3D12Resource),
                                                     reinterpret_cast<void**>(&tmp));
                    Say(r, "GetBuffer(%u) hr=0x%08X res=%p", probe,
                        static_cast<unsigned>(gh), static_cast<void*>(tmp));
                    if (tmp) tmp->Release();
                }
                ch1->Release();
            }
        }
        // The layer's rule (id 907): a command list may only write the *current*
        // back buffer, i.e. the one the next Present renders.  Writing any other
        // index removes the device with ACCESS_DENIED.  Right after creation that
        // buffer is not known reliably, so warm up with one Present; from then on
        // GetCurrentBackBufferIndex() is trustworthy and the overlay targets
        // exactly that index.
        if (SUCCEEDED(h)) h = ch->Present(1, 0);
        if (SUCCEEDED(h)) {
            for (int k = 0; k < 8; ++k) {
                const HRESULT rr = dev->GetDeviceRemovedReason();
                if (FAILED(rr)) { h = rr; break; }
                Sleep(10);
            }
        }

        if (SUCCEEDED(h)) {
            device = dev;
            queue  = q;
            chain  = ch;
            factory->MakeWindowAssociation(hwnd, DXGI_MWA_NO_ALT_ENTER);
            if (r.lateQueue < 0) {
                // back-buffer writes must run on the creating queue
                D3D12Overlay::SetCommandQueue(queue);
            } else {
                // In-game order: the queue is unknown while the overlay builds
                // itself.  Allow a generous hold budget; the loop delivers the
                // queue at frame r.lateQueue, exactly like the hook would.
                D3D12Overlay::SetQueueWaitFrames(600);
                Say(r, "late-queue mode: no queue before frame %d (hold budget 600)",
                    r.lateQueue);
            }
            Say(r, "adapter[%u] %s: device+chain+probe present OK", i, name);
        } else {
            Say(r, "adapter[%u] %s: REJECTED hr=0x%08X removed=0x%08X", i, name,
                static_cast<unsigned>(h),
                static_cast<unsigned>(dev ? dev->GetDeviceRemovedReason() : 0));
            if (dev) DumpInfoQueue(dev, r);      // what did the layer actually see?
            if (ch) ch->Release();
            if (q) q->Release();
            if (dev) dev->Release();
        }
    }
    for (UINT i = 0; i < candCount; ++i) cands[i]->Release();
    if (!chain) hr = E_FAIL;
    if (FAILED(hr) || !chain || !queue || !device) {
        Say(r, "FAIL: no adapter could present, hr=0x%08X", static_cast<unsigned>(hr));
        if (r.result) fclose(r.result);
        LogClose();
        if (chain) chain->Release();
        if (factory) factory->Release();
        if (queue) queue->Release();
        if (device) device->Release();
        return 2;
    }

    // ---- features + the real ESP ring -----------------------------------------
    CheatFeatures features;
    g_pCheatFeatures = &features;
    features.EnableFeature(FEATURE_ESP, true);      // VISUALS row 0 draws ON

    g_EspBoxes[0] = { 560.0f, 120.0f, 730.0f, 320.0f, 0xFFFF4040, false };
    g_EspBoxes[1] = { 760.0f, 160.0f, 900.0f, 340.0f, 0xFF40FF40, false };
    g_EspBoxes[2] = { 600.0f, 360.0f, 930.0f, 440.0f, 0xFFFFD040, true  };
    g_EspBoxCount = 3;

    // (no extra clear here: buffer 0 is no longer the current buffer after the
    // warm-up Present, and only the current one may be written)

    // ---- T3: drive MenuHandleKey exactly like WndProcHook would ---------------
    // AIMBOT page (7 rows): 0 ENABLED, 1 HITBOX, 2 SMOOTHING, 3 FOV,
    //                        4 RECOIL ENABLED, 5 VERTICAL, 6 HORIZONTAL.
    const bool kIns   = D3D12Overlay::MenuHandleKey(VK_INSERT, false);   // open
    const int  tab0   = D3D12Overlay::Menu()->tab;                       // 0
    const int  rows0  = D3D12Overlay::Menu()->rowCount;                  // 7
    const int  sel0   = D3D12Overlay::Menu()->selIndex;                   // 0
    D3D12Overlay::MenuHandleKey(VK_DOWN, false);   // 1 (HITBOX choice)
    D3D12Overlay::MenuHandleKey(VK_DOWN, false);   // 2 (SMOOTHING slider)
    const int  sel2   = D3D12Overlay::Menu()->selIndex;

    // The smoothing slider writes the LIVE aimbot value, not a copy of it.
    const float smooth0 = features.AimbotSmoothness();
    D3D12Overlay::MenuHandleKey(VK_RIGHT, false);                        // one step
    const float smooth1 = features.AimbotSmoothness();
    const bool  kRep    = D3D12Overlay::MenuHandleKey(VK_RIGHT, true);   // held: repeats
    const float smooth2 = features.AimbotSmoothness();
    D3D12Overlay::MenuHandleKey(VK_LEFT, false);                         // back one step
    D3D12Overlay::MenuHandleKey(VK_LEFT, true);                          // repeat LEFT steps
    const float smooth3 = features.AimbotSmoothness();

    // TAB switches category and re-clamps the selection.
    // VISUALS page (8 rows): 0 ENABLED, 1 BOXES, 2 NAMES, 3 LINES,
    //                         4 MAX DISTANCE, 5 GLOW ENABLED, 6 INTENSITY,
    //                         7 TEAM CHECK.
    const bool kTab   = D3D12Overlay::MenuHandleKey(VK_TAB, false);
    const int  tab1   = D3D12Overlay::Menu()->tab;                       // 1
    const int  rows1  = D3D12Overlay::Menu()->rowCount;                  // 8
    const int  selTab = D3D12Overlay::Menu()->selIndex;                  // still 2
    for (int i = 0; i < 3; ++i) D3D12Overlay::MenuHandleKey(VK_DOWN, false);
    const int  selGlow = D3D12Overlay::Menu()->selIndex;                 // 5 (GLOW)
    const bool kEnter = D3D12Overlay::MenuHandleKey(VK_RETURN, false);    // toggle + flush
    const bool glowOn = features.IsFeatureEnabled(FEATURE_GLOW);
    const bool kRepEnter = D3D12Overlay::MenuHandleKey(VK_RETURN, true);  // repeat: no re-toggle
    const bool glowAfter = features.IsFeatureEnabled(FEATURE_GLOW);
    const bool kPass  = D3D12Overlay::MenuHandleKey(0x57, false);         // 'W' passes
    const bool kBack  = D3D12Overlay::MenuHandleKey(VK_BACK, false);
    const bool closed = !D3D12Overlay::Menu()->open;
    // Re-open so the captured frames show the menu, on VISUALS with GLOW ON:
    // one screenshot then proves the frame, the focused row and a live toggle.
    D3D12Overlay::MenuHandleKey(VK_INSERT, false);
    const int  selCap  = D3D12Overlay::Menu()->selIndex;                 // 5
    const bool iniThere =
        GetFileAttributesA("apexcheat.ini") != INVALID_FILE_ATTRIBUTES;

    // Every category reports its own table, and a full TAB cycle comes back.
    bool tabsOk = D3D12Overlay::MenuTabCount() == 5;
    // Normalise to category 0 first: the loop below asserts that the live tab
    // equals the loop index, so it has to start on AIMBOT rather than on
    // whichever category the navigation sequence above left behind.
    for (int guard = 0; guard < D3D12Overlay::MenuTabCount() &&
                        D3D12Overlay::Menu()->tab != 0; ++guard) {
        D3D12Overlay::MenuHandleKey(VK_TAB, false);
    }
    const int tabBefore = D3D12Overlay::Menu()->tab;
    for (int i = 0; i < D3D12Overlay::MenuTabCount(); ++i) {
        const int active = D3D12Overlay::Menu()->tab;
        const int rows   = D3D12Overlay::Menu()->rowCount;
        Say(r, "T3 tab[%d] %-8s rows=%d active=%d sel=%d", i,
            D3D12Overlay::MenuTabName(i), D3D12Overlay::MenuTabRowCount(i),
            active == i ? 1 : 0, D3D12Overlay::Menu()->selIndex);
        if (active != i || rows != D3D12Overlay::MenuTabRowCount(i)) tabsOk = false;
        D3D12Overlay::MenuHandleKey(VK_TAB, false);
    }
    if (D3D12Overlay::Menu()->tab != tabBefore) tabsOk = false;

    r.navOk    = kIns && kTab && kEnter && kRep && kRepEnter && !kPass &&
                 kBack && closed && tabsOk &&
                 tab0 == 0 && rows0 == 7 && sel0 == 0 &&
                 sel2 == 2 && tab1 == 1 && rows1 == 8 && selTab == 2 &&
                 selGlow == 5 && selCap == 5;
    r.menuLive = glowOn && glowAfter && iniThere &&
                 smooth1 > smooth0 && smooth2 > smooth1 && smooth3 < smooth1;
    Say(r, "T3 nav: ins=%d tab=%d enter=%d repeat=%d back=%d closed=%d "
           "pass-through=%d tabsOk=%d",
        kIns ? 1 : 0, kTab ? 1 : 0, kEnter ? 1 : 0, kRep ? 1 : 0,
        kBack ? 1 : 0, closed ? 1 : 0, kPass ? 1 : 0, tabsOk ? 1 : 0);
    Say(r, "T3 rows: aimbot=%d visuals=%d sel %d->%d->%d->%d",
        rows0, rows1, sel0, sel2, selGlow, selCap);
    Say(r, "T3 slider: smoothing %.1f -> %.1f -> %.1f -> %.1f (live value)",
        static_cast<double>(smooth0), static_cast<double>(smooth1),
        static_cast<double>(smooth2), static_cast<double>(smooth3));
    Say(r, "T3 repeat suppression: glow=%d after repeat-ENTER glow=%d",
        glowOn ? 1 : 0, glowAfter ? 1 : 0);
    Say(r, "T4 live flush: GLOW toggled via menu ENTER, apexcheat.ini present=%d",
        iniThere ? 1 : 0);

    // --menu-tab N: leave the capture on category N (default: VISUALS/GLOW).
    {
        const int wantTab = (r.menuTab >= 0) ? r.menuTab : 1;   // 1 = VISUALS
        for (int guard = 0; guard < D3D12Overlay::MenuTabCount() &&
                            D3D12Overlay::Menu()->tab != wantTab; ++guard) {
            D3D12Overlay::MenuHandleKey(VK_TAB, false);
        }
    }
    Say(r, "T3 capture state: tab=%d (%s) row %d/%d open=%d",
        D3D12Overlay::Menu()->tab,
        D3D12Overlay::MenuTabName(D3D12Overlay::Menu()->tab),
        D3D12Overlay::Menu()->selIndex + 1, D3D12Overlay::Menu()->rowCount,
        D3D12Overlay::Menu()->open ? 1 : 0);

    // ---- frame loop ------------------------------------------------------------
    const ULONGLONG t0 = GetTickCount64();
    bool quit = false;
    while (!quit) {
        MSG msg;
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) { quit = true; break; }
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        if (quit) break;
        if (GetTickCount64() - t0 >= static_cast<ULONGLONG>(r.seconds) * 1000ull) break;

        // Per-frame content: the stage queues live exactly one frame.
        D3D12Overlay::PushQuad(0.0f, 0.0f, static_cast<float>(r.cw),
                               static_cast<float>(r.ch), 0xFF202830);   // known bg
        // sample lines (distinct from the ESP boxes)
        D3D12Overlay::PushLine(520.0f, 64.0f, 940.0f, 64.0f, 0xFF505860);
        D3D12Overlay::PushLine(520.0f, 96.0f, 940.0f, 64.0f, 0xFFE0B040);
        D3D12Overlay::PushLine(940.0f, 96.0f, 520.0f, 64.0f, 0xFFE0B040);
        D3D12Overlay::PushLine(520.0f, 40.0f, 520.0f, 440.0f, 0xFF3F8FE0);
        // filled semi-transparent panel with a line border (T2 quad + lines)
        D3D12Overlay::PushQuad(800.0f, 470.0f, 940.0f, 600.0f, 0x8C101820);
        D3D12Overlay::PushLine(800.0f, 470.0f, 940.0f, 470.0f, 0xFF3F8FE0);
        D3D12Overlay::PushLine(800.0f, 600.0f, 940.0f, 600.0f, 0xFF3F8FE0);
        // 5x7 text rows (T2), sized to OCR cleanly
        D3D12Overlay::PushTextA("QWENKERN OVERLAY TEST", 24.0f, 456.0f, 6.0f, 0xFFFFFFFF);
        D3D12Overlay::PushTextA("5X7 FONT QUADS 0123456789", 24.0f, 516.0f, 5.0f, 0xFF7FD4FF);
        D3D12Overlay::PushTextA("MENU ROWS ESP GLOW RECOIL AIMBOT", 24.0f, 568.0f, 4.0f,
                               0xFFB0BEC5);

        // the same entry the Present hook calls, no vtable hook involved
        if (r.lateQueue >= 0 && !r.queueDelivered) {
            if (r.frames >= r.lateQueue) {
                r.queueDelivered = D3D12Overlay::SetCommandQueue(queue);
                Say(r, "late-queue: delivered creating queue %p at frame %d, "
                       "accepted=%d, ownQueue=%d",
                    static_cast<void*>(queue), r.frames,
                    r.queueDelivered ? 1 : 0, D3D12Overlay::UsesOwnQueue() ? 1 : 0);
            } else {
                ++r.heldFrames;      // frames the renderer must survive queue-less
            }
        }
        if (!D3D12Overlay::Render(chain)) r.renderOk = false;

        if (!r.iqDone && r.frames == 1) {
            r.iqDone = true;
            DumpInfoQueue(device, r);
        }

        // T6: measure the buffer we just drew into at ~2 s, before Present flips.
        if (!r.covDone && r.frames == 120) {
            IDXGISwapChain3* sc3 = nullptr;
            UINT idx = 0;
            if (SUCCEEDED(chain->QueryInterface(__uuidof(IDXGISwapChain3),
                                                 reinterpret_cast<void**>(&sc3))) && sc3) {
                idx = sc3->GetCurrentBackBufferIndex();
                sc3->Release();
            }
            r.covDone = MeasureCoverage(device, queue, chain, idx, r);
            Say(r, "T6 buffer readback: ok=%d coverage=%.1f%% bbox %ld,%ld - %ld,%ld "
                   "of %ux%u (client)",
                r.covDone ? 1 : 0, r.coverage * 100.0, r.bx0, r.by0, r.bx1, r.by1,
                r.cw, r.ch);
        }

        const HRESULT phr = chain->Present(1, 0);
        if (phr != S_OK) {
            if (r.frames < 5) {
                Say(r, "T5 Present hr=0x%08X (%s) removedReason=0x%08X",
                    static_cast<unsigned>(phr),
                    SUCCEEDED(phr) ? "status" : "FAILED",
                    static_cast<unsigned>(device->GetDeviceRemovedReason()));
            }
            if (FAILED(phr)) ++r.presentFails;

            // 3rd failure: does SyncInterval matter, or is the device gone?
            if (r.presentFails == 3) {
                const HRESULT h0 = chain->Present(0, 0);
                Say(r, "T5 Present(0,0) hr=0x%08X removedReason=0x%08X",
                    static_cast<unsigned>(h0),
                    static_cast<unsigned>(device->GetDeviceRemovedReason()));
            }
        }
        ++r.frames;

        // A removed device makes every later frame noise; stop instead of
        // burning 40 s at 20k fps.
        if (r.presentFails > 8 && r.frames > 200) quit = true;
    }

    // ---- verdict ---------------------------------------------------------------
    const unsigned long long pc = D3D12Overlay::PresentCount();
    const bool pcOk = (pc == static_cast<unsigned long long>(r.frames));
    Say(r, "T5 PresentCount()=%llu frames=%d equal=%s", pc, r.frames,
        pcOk ? "yes" : "no");
    Say(r, "renderOk=%d cfgRt=%d navOk=%d menuLive=%d frames=%d presentFails=%d",
        r.renderOk ? 1 : 0, r.cfgRt ? 1 : 0, r.navOk ? 1 : 0, r.menuLive ? 1 : 0,
        r.frames, r.presentFails);
    Say(r, "T8 direct clear on creating queue: done in the adapter probe");

    // T6 geometry gate: the drawn pixels must cover the client, not a strip of
    // it.  Regression guard for the squeezed-viewport class of bug.
    const bool covOk    = r.covDone && r.coverage >= 0.80;
    const bool bboxOk   = r.covDone &&
                          r.bx0 <= 2 &&
                          r.by0 <= 2 &&
                          r.bx1 >= static_cast<LONG>(r.cw) - 3 &&
                          r.by1 >= static_cast<LONG>(r.ch) - 3;
    Say(r, "T6 geometry gate: readback=%d coverage=%.1f%% (>=80%% required) "
           "bboxOk=%d", r.covDone ? 1 : 0, r.coverage * 100.0, bboxOk ? 1 : 0);
    if (!covOk || !bboxOk) {
        Say(r, "T6 GEOMETRY FAIL: drawn area does not fill the %ux%u client "
               "(bbox %ld,%ld - %ld,%ld)", r.cw, r.ch, r.bx0, r.by0, r.bx1, r.by1);
    }

    // Late-queue gate: the queue really arrived, was accepted, and the overlay
    // ended on it instead of the private fallback.
    const bool lateOk = r.lateQueue < 0 ||
                        (r.queueDelivered && !D3D12Overlay::UsesOwnQueue() &&
                         r.heldFrames == r.lateQueue);
    if (r.lateQueue >= 0) {
        Say(r, "T9 late queue gate: held=%d/%d delivered=%d ownQueue=%d ok=%d",
            r.heldFrames, r.lateQueue, r.queueDelivered ? 1 : 0,
            D3D12Overlay::UsesOwnQueue() ? 1 : 0, lateOk ? 1 : 0);
    }

    const bool pass = r.renderOk && r.cfgRt && r.navOk && r.menuLive && pcOk &&
                      covOk && bboxOk && lateOk && r.presentFails == 0 && r.frames > 0;
    Say(r, "RESULT: %s", pass ? "PASS" : "FAIL");
    Say(r, "VERDICT: overlay draw path, menu state, key handling, ini flush,");
    Say(r, "VERDICT: present counter and client-filling coverage verified offline");

    if (r.result) { fclose(r.result); r.result = nullptr; }
    Logf("[test] exit pass=%d", pass ? 1 : 0);
    LogClose();
    D3D12Overlay::Release();
    if (chain) chain->Release();
    if (factory) factory->Release();
    if (queue) queue->Release();
    if (device) device->Release();
    return pass ? 0 : 2;
}