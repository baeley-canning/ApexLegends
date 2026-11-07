// ============================================================================
// tools\qk_overlay.cpp — standalone EXTERNAL overlay (own process, nothing
// injected into any game, no driver, no hooks, nothing to restore).
//
// One question: "can a separate process put a box on the screen, click-through
// and never focused, reading its data out of shared memory?"  That is the pixel
// side of PLAN stages 1-5 without touching r5apex.
//
// Design notes, i.e. why it looks like this:
//   * Real per-pixel alpha needs UpdateLayeredWindow; a D3D12/DXGI swapchain
//     does NOT compose onto a layered window (measured repeatedly in this
//     repo).  So: WS_EX_LAYERED + SetLayeredWindowAttributes(LWA_COLORKEY)
//     with black as the key, and a plain GDI memory DC as the back buffer.
//     Anything drawn black is a hole; everything else is opaque.
//   * WS_EX_TRANSPARENT + WS_EX_NOACTIVATE + WS_EX_TOOLWINDOW + WS_POPUP:
//     input falls through to whatever is underneath and the overlay never
//     takes focus (so the game keeps the foreground).
//   * The producer is optional.  A missing producer, an empty mapping, or a
//     stale/garbage one all render "nothing" — never a crash, never a spin.
//
// Data source: named shared memory "Global\\qk_boxes" (falls back to
// "Local\\qk_boxes" when the caller may not create a global object):
//
//   struct Header { unsigned int magic; unsigned int count; unsigned __int64 frame; };
//   struct Box    { float x0, y0, x1, y1; unsigned int color; unsigned int pad; };
//
//   magic = 0x514B4258 ("QKBX"), count <= 256, Box[] immediately after the
//   header, all little endian, packed.  color is a COLORREF (0x00BBGGRR).
//
// Usage:
//   qk_overlay.exe [--fake] [--rect=x,y,w,h] [--fps=N] [--seconds=N]
//     --fake        create the mapping ourselves and animate 3 test boxes
//     --rect=...    overlay rect instead of the whole virtual desktop
//     --fps=N       target repaint rate, default 60 (1..1000)
//     --seconds=N   exit after N seconds (0 = run until WM_QUIT)
// Exit: 0 clean, 2 bad arguments, 3 window/rect setup, 5 GDI setup.
// ============================================================================
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <math.h>

#define QK_MAGIC        0x514B4258u   /* "QKBX" */
#define QK_MAX_BOXES    256u
#define QK_REPAINT_MS   250u           /* repaint at least this often */
#define QK_MAX_COORD    20000.0f      /* |v| beyond this is producer garbage */
#define QK_EDGE          2             /* outline thickness, px */
#define QK_BAR_H         4             /* small filled bar, px */

#pragma pack(push, 1)
struct QkHeader {
    unsigned int  magic;
    unsigned int  count;
    unsigned __int64 frame;
};
struct QkBox {
    float        x0, y0, x1, y1;
    unsigned int color;   /* COLORREF 0x00BBGGRR, low 24 bits used */
    unsigned int pad;
};
#pragma pack(pop)

static const DWORD kMapSize =
    (DWORD)(sizeof(QkHeader) + (size_t)QK_MAX_BOXES * sizeof(QkBox));

// ---------------------------------------------------------------------------
// state
// ---------------------------------------------------------------------------
static HWND        g_hwnd      = nullptr;
static HDC         g_memDC     = nullptr;
static HBITMAP     g_memBmp    = nullptr;
static HGDIOBJ     g_oldBmp    = nullptr;
static int         g_w         = 0;
static int         g_h         = 0;
static RECT        g_rect      = { 0, 0, 0, 0 };

static HANDLE      g_map       = nullptr;
static void*       g_view      = nullptr;
static size_t      g_viewBytes = 0;
static unsigned int g_capacity = 0;          /* boxes the view can hold */
static const char* g_mapNameA  = "Global\\qk_boxes";

// ---------------------------------------------------------------------------
// console
// ---------------------------------------------------------------------------
static void Say(const char* fmt, ...) {
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    vsprintf_s(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    printf("%s\n", buf);
    fflush(stdout);
}

// ---------------------------------------------------------------------------
// shared memory
// ---------------------------------------------------------------------------
static void ComputeCapacity(void) {
    MEMORY_BASIC_INFORMATION mbi;
    g_viewBytes = 0;
    g_capacity  = 0;
    if (VirtualQuery(g_view, &mbi, sizeof(mbi)) != 0) {
        g_viewBytes = (size_t)mbi.RegionSize;   // == mapping size, for a view
    }
    if (g_viewBytes > sizeof(QkHeader)) {
        size_t cap = (g_viewBytes - sizeof(QkHeader)) / sizeof(QkBox);
        if (cap > QK_MAX_BOXES) cap = QK_MAX_BOXES;
        g_capacity = (unsigned int)cap;
    }
}

static void MapOpen(bool needWrite) {
    static const DWORD accesses[2] = { PAGE_READWRITE, PAGE_READONLY };
    static const wchar_t* const names[2] = { L"Global\\qk_boxes", L"Local\\qk_boxes" };

    for (int ni = 0; ni < 2 && !g_view; ++ni) {
        for (int ai = 0; ai < 2 && !g_view; ++ai) {
            const DWORD access = accesses[ai];
            if (needWrite && access == PAGE_READONLY) continue;
            HANDLE h = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, access,
                                          0, kMapSize, names[ni]);
            if (!h) continue;                    // no rights / bad name
            const DWORD viewAccess = (access == PAGE_READWRITE)
                                   ? (FILE_MAP_READ | FILE_MAP_WRITE)
                                   : FILE_MAP_READ;
            void* v = MapViewOfFile(h, viewAccess, 0, 0, 0);
            if (!v) { CloseHandle(h); continue; }
            g_map = h;
            g_view = v;
            g_mapNameA = (ni == 0) ? "Global\\qk_boxes" : "Local\\qk_boxes";
            ComputeCapacity();
        }
    }
}

static void MapClose(void) {
    if (g_view) { UnmapViewOfFile(g_view); g_view = nullptr; }
    if (g_map)  { CloseHandle(g_map);      g_map  = nullptr; }
    g_viewBytes = 0;
    g_capacity  = 0;
}

// Frame counter only - cheap, and the repaint decision needs nothing else.
static unsigned __int64 ReadFrame(void) {
    unsigned __int64 fr = 0;
    if (!g_view || g_capacity == 0) return 0;
    __try {
        const volatile QkHeader* h = (const volatile QkHeader*)g_view;
        if (h->magic == QK_MAGIC) fr = h->frame;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        fr = 0;
    }
    return fr;
}

// Copy the boxes out.  magic is validated, count is clamped to both the caller
// cap and what the view can physically hold, and every read is guarded - a
// stale or truncated producer costs a blank frame, not an access violation.
static unsigned int Snapshot(QkBox* out, unsigned int cap, unsigned __int64* frameOut) {
    *frameOut = 0;
    if (!g_view || cap == 0 || g_capacity == 0) return 0;

    unsigned int limit = g_capacity;
    if (limit > cap) limit = cap;

    unsigned int count = 0;
    __try {
        const volatile QkHeader* h = (const volatile QkHeader*)g_view;
        if (h->magic == QK_MAGIC) {
            unsigned int c = h->count;
            if (c > limit) c = limit;
            if (c > 0u) {
                memcpy(out, (const BYTE*)g_view + sizeof(QkHeader),
                       (size_t)c * sizeof(QkBox));
            }
            *frameOut = h->frame;
            count = c;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        count = 0;
        *frameOut = 0;
    }
    return count;
}

// ---------------------------------------------------------------------------
// drawing (all GDI, no D3D: a DXGI swapchain does not compose on a layered
// window; a memory DC + BitBlt does)
// ---------------------------------------------------------------------------
static bool FiniteCoord(float v) {
    return (v == v) && (v > -QK_MAX_COORD) && (v < QK_MAX_COORD);   // NaN-safe
}

static int SnapF(float v) {
    return (v >= 0.0f) ? (int)(v + 0.5f) : (int)(v - 0.5f);
}

// The key colour is black, so a box whose colour is black would be a hole in
// the desktop; substitute a bright default in that one case.
static COLORREF BoxColour(unsigned int c) {
    COLORREF cr = (COLORREF)(c & 0x00FFFFFFu);
    if (GetRValue(cr) < 8 && GetGValue(cr) < 8 && GetBValue(cr) < 8) {
        return RGB(0, 255, 64);
    }
    return cr;
}

static void FillBand(HDC dc, int l, int t, int r, int b, HBRUSH br) {
    RECT rc;
    if (r <= l || b <= t) return;
    rc.left = l; rc.top = t; rc.right = r; rc.bottom = b;
    FillRect(dc, &rc, br);
}

// Producer floats -> client pixels, or false if the box is unusable.
static bool BoxToRect(const QkBox& b, RECT* out) {
    if (!FiniteCoord(b.x0) || !FiniteCoord(b.y0) ||
        !FiniteCoord(b.x1) || !FiniteCoord(b.y1)) return false;

    float x0 = b.x0, y0 = b.y0, x1 = b.x1, y1 = b.y1;
    if (x0 > x1) { const float t = x0; x0 = x1; x1 = t; }
    if (y0 > y1) { const float t = y0; y0 = y1; y1 = t; }

    int l  = SnapF(x0) - (int)g_rect.left;
    int t  = SnapF(y0) - (int)g_rect.top;
    int r  = SnapF(x1) - (int)g_rect.left;
    int bo = SnapF(y1) - (int)g_rect.top;

    if (l  < 0)   l  = 0;
    if (t  < 0)   t  = 0;
    if (r  > g_w) r  = g_w;
    if (bo > g_h) bo = g_h;

    if ((r - l) < QK_EDGE || (bo - t) < QK_EDGE) return false;
    out->left = l; out->top = t; out->right = r; out->bottom = bo;
    return true;
}

// One box: 2 px outline (four bands, so the thickness is exact and does not
// depend on pen join behaviour) plus a small filled bar inside the bottom edge.
static void DrawBox(HDC dc, const RECT& rc, COLORREF cr) {
    HBRUSH br = CreateSolidBrush(cr);
    if (!br) return;

    FillBand(dc, rc.left,         rc.top,         rc.right,         rc.top + QK_EDGE, br);
    FillBand(dc, rc.left,         rc.bottom - QK_EDGE, rc.right,    rc.bottom,        br);
    FillBand(dc, rc.left,         rc.top,         rc.left + QK_EDGE,  rc.bottom,       br);
    FillBand(dc, rc.right - QK_EDGE, rc.top,     rc.right,           rc.bottom,       br);

    const int barT = rc.bottom - QK_EDGE - QK_BAR_H - 2;
    FillBand(dc, rc.left + 4, barT, rc.right - 4, barT + QK_BAR_H, br);

    DeleteObject(br);
}

// Render one whole frame offscreen; returns how many boxes were actually drawn.
static unsigned int Paint(void) {
    if (!g_memDC) return 0;

    RECT full = { 0, 0, g_w, g_h };
    FillRect(g_memDC, &full, (HBRUSH)GetStockObject(BLACK_BRUSH));   // the key

    QkBox boxes[QK_MAX_BOXES];
    unsigned __int64 frame = 0;
    const unsigned int n = Snapshot(boxes, QK_MAX_BOXES, &frame);
    (void)frame;

    unsigned int drawn = 0;
    for (unsigned int i = 0; i < n; ++i) {
        RECT rc;
        if (!BoxToRect(boxes[i], &rc)) continue;
        DrawBox(g_memDC, rc, BoxColour(boxes[i].color));
        ++drawn;
    }
    return drawn;
}

static void Present(void) {
    if (!g_memDC) return;
    HDC dc = GetDC(g_hwnd);
    if (dc) {
        BitBlt(dc, 0, 0, g_w, g_h, g_memDC, 0, 0, SRCCOPY);
        ReleaseDC(g_hwnd, dc);
    }
}

// ---------------------------------------------------------------------------
// --fake producer: three animated boxes, written through exactly the layout a
// real producer will use, so the read + validation path is exercised too.
// ---------------------------------------------------------------------------
static unsigned int FakeColour(unsigned int i) {
    if (i == 0u) return RGB(255, 64, 64);
    if (i == 1u) return RGB(64, 255, 96);
    return RGB(96, 192, 255);
}

static void FakeProduce(double t) {
    if (!g_view || g_capacity < 3u) return;
    QkHeader* h = (QkHeader*)g_view;
    QkBox* boxes = (QkBox*)(void*)((BYTE*)g_view + sizeof(QkHeader));

    const double spanX = (double)((g_w > 300) ? (g_w - 300) : 1);
    const double spanY = (double)((g_h > 200) ? (g_h - 200) : 1);
    const double bw = 150.0;
    const double bh = 44.0;

    for (unsigned int i = 0; i < 3u; ++i) {
        const double phase = t * (0.9 + 0.35 * (double)i) + 2.1 * (double)i;
        const double cx = 100.0 + spanX * (0.5 + 0.45 * sin(phase));
        const double cy = 100.0 + spanY * (0.5 + 0.45 * cos(phase * 0.7));
        QkBox& b = boxes[i];
        b.x0 = (float)((double)g_rect.left + cx);
        b.y0 = (float)((double)g_rect.top  + cy);
        b.x1 = (float)((double)g_rect.left + cx + bw);
        b.y1 = (float)((double)g_rect.top  + cy + bh);
        b.color = FakeColour(i);
        b.pad   = 0u;
    }
    h->count = 3u;
    h->magic = QK_MAGIC;
    h->frame = h->frame + 1u;   // bumped last: a reader that sees it saw a full write
}

// ---------------------------------------------------------------------------
// window
// ---------------------------------------------------------------------------
static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM w, LPARAM l) {
    switch (msg) {
    case WM_ERASEBKGND:
        return 1;                            // the back buffer is the whole paint
    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC dc = BeginPaint(hwnd, &ps);
        if (dc && g_memDC) BitBlt(dc, 0, 0, g_w, g_h, g_memDC, 0, 0, SRCCOPY);
        EndPaint(hwnd, &ps);
        return 0;
    }
    case WM_NCHITTEST:
        return HTTRANSPARENT;                // belt and braces with WS_EX_TRANSPARENT
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    default:
        break;
    }
    return DefWindowProcW(hwnd, msg, w, l);
}

static bool GdiSetup(void) {
    HDC screen = GetDC(nullptr);
    if (!screen) return false;
    g_memDC  = CreateCompatibleDC(screen);
    g_memBmp = CreateCompatibleBitmap(screen, g_w, g_h);
    ReleaseDC(nullptr, screen);
    if (!g_memDC || !g_memBmp) return false;
    g_oldBmp = SelectObject(g_memDC, g_memBmp);
    if (!g_oldBmp || g_oldBmp == (HGDIOBJ)HGDI_ERROR) return false;
    return true;
}

static void GdiShutdown(void) {
    if (g_memDC) {
        if (g_oldBmp) SelectObject(g_memDC, g_oldBmp);
        DeleteDC(g_memDC);
        g_memDC = nullptr;
    }
    if (g_memBmp) { DeleteObject(g_memBmp); g_memBmp = nullptr; }
    g_oldBmp = nullptr;
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main(int argc, char** argv) {
    bool   fake     = false;
    int    fps      = 60;
    double seconds  = 0.0;
    bool   haveRect = false;
    RECT   rect     = { 0, 0, 0, 0 };

    for (int i = 1; i < argc; ++i) {
        const char* a = argv[i];
        if (!a) continue;
        if (strcmp(a, "--fake") == 0) { fake = true; continue; }
        if (strncmp(a, "--fps=", 6) == 0) {
            int v = atoi(a + 6);
            if (v < 1)    v = 1;
            if (v > 1000) v = 1000;
            fps = v;
            continue;
        }
        if (strncmp(a, "--seconds=", 10) == 0) {
            const double v = atof(a + 10);
            seconds = (v > 0.0) ? v : 0.0;
            continue;
        }
        if (strncmp(a, "--rect=", 7) == 0) {
            int x = 0, y = 0, w = 0, h = 0;
            if (sscanf_s(a + 7, "%d,%d,%d,%d", &x, &y, &w, &h) == 4 && w > 0 && h > 0) {
                rect.left = x; rect.top = y;
                rect.right = x + w; rect.bottom = y + h;
                haveRect = true;
                continue;
            }
            Say("OVERLAY: bad --rect (want --rect=x,y,w,h)");
            return 2;
        }
        Say("OVERLAY: unknown argument %s", a);
        return 2;
    }

    if (!haveRect) {
        const int vx = GetSystemMetrics(SM_XVIRTUALSCREEN);
        const int vy = GetSystemMetrics(SM_YVIRTUALSCREEN);
        const int vw = GetSystemMetrics(SM_CXVIRTUALSCREEN);
        const int vh = GetSystemMetrics(SM_CYVIRTUALSCREEN);
        if (vw <= 0 || vh <= 0) {
            Say("OVERLAY: no virtual desktop metrics (cx=%d cy=%d)", vw, vh);
            return 3;
        }
        rect.left = vx; rect.top = vy;
        rect.right = vx + vw; rect.bottom = vy + vh;
    }

    g_rect = rect;
    g_w = rect.right - rect.left;
    g_h = rect.bottom - rect.top;
    if (g_w <= 0 || g_h <= 0 || g_w > 32767 || g_h > 32767) {
        Say("OVERLAY: bad overlay size %dx%d", g_w, g_h);
        return 3;
    }

    MapOpen(fake);            // optional: no mapping simply means "no boxes"

    const HINSTANCE hinst = GetModuleHandleW(nullptr);
    WNDCLASSEXW wc;
    ZeroMemory(&wc, sizeof(wc));
    wc.cbSize        = sizeof(wc);
    wc.lpfnWndProc   = WndProc;
    wc.hInstance     = hinst;
    wc.lpszClassName = L"QkOverlayWindowClass";
    if (!RegisterClassExW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        Say("OVERLAY: RegisterClassEx failed err=%lu", GetLastError());
        MapClose();
        return 3;
    }

    g_hwnd = CreateWindowExW(
        WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST |
        WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW,
        L"QkOverlayWindowClass", L"qk_overlay", WS_POPUP,
        rect.left, rect.top, g_w, g_h,
        nullptr, nullptr, hinst, nullptr);
    if (!g_hwnd) {
        Say("OVERLAY: CreateWindowEx failed err=%lu", GetLastError());
        MapClose();
        return 3;
    }

    // Black is the key colour: every black pixel of the window is a hole.
    SetLayeredWindowAttributes(g_hwnd, RGB(0, 0, 0), 0, LWA_COLORKEY);

    if (!GdiSetup()) {
        Say("OVERLAY: GDI back buffer failed (%dx%d)", g_w, g_h);
        DestroyWindow(g_hwnd);
        g_hwnd = nullptr;
        MapClose();
        return 5;
    }

    ShowWindow(g_hwnd, SW_SHOWNOACTIVATE);
    UpdateWindow(g_hwnd);
    SetWindowPos(g_hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);

    Say("OVERLAY: rect=%d,%d,%d,%d fps=%d source=%s",
        (int)g_rect.left, (int)g_rect.top, g_w, g_h, fps,
        fake ? "fake" : "shared");
    if (!g_view) {
        Say("OVERLAY: shm missing - drawing nothing");
    } else if (strcmp(g_mapNameA, "Global\\qk_boxes") != 0) {
        Say("OVERLAY: shm fallback name=%s", g_mapNameA);
    }

    const DWORD     intervalMs = (DWORD)(1000 / fps);   // fps >= 1, so >= 1 ms
    const ULONGLONG t0         = GetTickCount64();
    bool             running   = true;
    bool             haveFrame = false;
    unsigned __int64 lastFrame = 0;
    ULONGLONG        lastPaint = t0;
    unsigned __int64 iter      = 0;
    unsigned int     drawn     = 0;

    while (running) {
        MSG msg;
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) { running = false; break; }
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        if (!running) break;

        const ULONGLONG now = GetTickCount64();
        if (seconds > 0.0 && (double)(now - t0) >= seconds * 1000.0) break;

        if (fake) FakeProduce((double)(now - t0) / 1000.0);

        // Repaint only when the producer moved the frame counter, and at least
        // every 250 ms so a stalled producer still gets its last state shown.
        const unsigned __int64 fr = ReadFrame();
        if (fake || !haveFrame || fr != lastFrame ||
            (now - lastPaint) >= QK_REPAINT_MS) {
            drawn = Paint();
            Present();
            lastFrame = fr;
            haveFrame = true;
            lastPaint = now;
        }

        ++iter;
        if ((iter % 120u) == 0u) {
            Say("OVERLAY: frames=%llu boxes=%u",
                (unsigned long long)iter, drawn);
        }

        // Never spin: sleep out whatever is left of this frame's slot.
        const ULONGLONG spent = GetTickCount64() - now;
        if (spent < (ULONGLONG)intervalMs) {
            Sleep((DWORD)((ULONGLONG)intervalMs - spent));
        }
    }

    Say("OVERLAY: done frames=%llu boxes=%u", (unsigned long long)iter, drawn);

    DestroyWindow(g_hwnd);
    g_hwnd = nullptr;
    GdiShutdown();
    MapClose();
    return 0;
}
