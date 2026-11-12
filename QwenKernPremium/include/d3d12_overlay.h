#pragma once
#include <windows.h>
#include <dxgi.h>
#include <d3d12.h>      // declarations only; the payload still resolves d3d12 at runtime

// ============================================================================
// d3d12_overlay.h — D3D12 overlay backend for the DXGI swap chain hook.
//
// WHY THIS EXISTS: r5apex_dx12.exe renders with D3D12.  The overlay in
// hooks.cpp was D3D11-only (GetDevice(__uuidof(ID3D11Device)) on the swap
// chain), which returns E_NOINTERFACE on a D3D12 swap chain, so on the live
// DX12 build the ESP never drew anything — silently.
//
// DESIGN CONSTRAINTS (all measured on the live install, see docs\
// DX12_ESP_VERDICT_AND_PROXY_PLAN.txt):
//   * No new static imports.  Every D3D12 function used here is either a COM
//     method on an interface we already have (device / queue / command list)
//     or resolved with LoadLibrary/GetProcAddress (d3d12.dll,
//     d3dcompiler_47.dll).  The payload's IAT stays {KERNEL32, USER32, psapi,
//     advapi32, d3d11, dxgi} — the last two exist because the vcxproj always
//     linked them, not because of this file.
//   * No retained back-buffer references.  CreateRenderTargetView() keeps the
//     resource alive internally, so the ID3D12Resource returned by GetBuffer()
//     is released immediately.  Holding it would make the game's own
//     ResizeBuffers() fail with DXGI_ERROR_INVALID_CALL.
//   * The game's own command queue is used when it can be reached (that is the
//     canonical, ordered path: our draws land after the frame's work and before
//     Present).  Only if the queue cannot be reached do we create our own.
//
// ORDER OF USE (from the Present hook):
//     if (!D3D12Overlay::Render(swapChain))  // false => not a D3D12 chain
//         RenderOverlayDX11(swapChain);
// ============================================================================
namespace D3D12Overlay {

// The DIRECT queue that created the swap chain.  Back-buffer writes must be
// executed on that queue (the debug layer enforces it, id 907, and removes the
// device otherwise), so the Present hook should hand it over.  Optional: without
// it we fall back to the chain's device QI and then to a private queue (which
// alone is not enough on any chain we tested).
// Hands the overlay the command queue that owns the presenting swap chain.
// REQUIRED for D3D12 (see CreateDeviceObjects): back-buffer writes must be
// executed on that queue, so without it the overlay burns a private queue and
// the device is removed with DXGI_ERROR_ACCESS_DENIED.
//
// Validated: only a D3D12_COMMAND_LIST_TYPE_DIRECT queue of the same device is
// accepted, and an already-known queue is a no-op.  Returns true when the queue
// is (now) the overlay's queue, false when it was rejected.
bool SetCommandQueue(ID3D12CommandQueue* pQueue);

// While the overlay had to fall back to a private queue it holds the first N
// frames instead of submitting on a queue that provably cannot present (the
// submit removes the device).  Called with a finite budget by the hook once the
// ExecuteCommandLists capture is known to be installed; if the game really has
// no direct queue, the private queue is tried after the budget expires.
void SetQueueWaitFrames(unsigned frames);

// Creates (once) the device-side objects.  Returns false when the swap chain
// does not belong to a D3D12 device, or on creation failure (logged).
bool Ensure(IDXGISwapChain* pSwapChain);

// Draws g_EspBoxes into the current back buffer, then returns.
// Returns false if this is not a D3D12 swap chain (caller falls back to D3D11).
bool Render(IDXGISwapChain* pSwapChain);

// Releases size-dependent state (render-target views).  Must be called before
// the game resizes the swap chain, otherwise our descriptors keep the old
// buffers alive and ResizeBuffers() returns DXGI_ERROR_INVALID_CALL.
void OnResize();

// Releases everything (module unload / device teardown).
void Release();

bool IsReady();

// True while the overlay submits on its own private queue instead of the game's.
// The late-queue test gates on this: a PASS has to end on the game queue.
bool UsesOwnQueue();

// ============================================================================
// PHASE 1 / ov-series — UI primitives + menu state (T2/T3/T5)
//
// All of this stays import-neutral: no new Win32 or D3D calls, glyph data is
// byte constants in d3d12_overlay.cpp, so the payload IAT is untouched.
// ============================================================================

// Menu navigation state.  Owned by the overlay because the renderer is what
// turns it into quads; the WndProc hook (hooks.cpp) only forwards keys.
//
// The menu is a category strip (tab) over two section panels per category;
// selIndex counts the rows of the ACTIVE category in panel order, so it is
// always < rowCount.  rowCount follows the category through MenuHandleKey(),
// which is what the offline test asserts on.
struct MenuState {
    bool open;        // INSERT toggles
    int  selIndex;   // selected row inside the active category (0-based)
    int  rowCount;   // rows in the active category (menu.cpp tables)
    int  tab;         // active category index, 0 .. MenuTabCount()-1
};

// Number of categories in the top strip (AIMBOT, VISUALS, PLAYERS, LOOT, MISC).
int MenuTabCount();

// Display name of a category ("AIMBOT", ...), for logs and the test harness.
const char* MenuTabName(int tab);

// Row count of a category, independent of the current selection.
int MenuTabRowCount(int tab);

// Singleton menu state (never null after first call).
MenuState* Menu();
bool MenuIsOpen();

// Key handler for the menu, called by GameHooks::WndProcHook (T3).  Returns
// true when the key was consumed; the caller then returns 1 so the game never
// sees it.  `repeat` is the WM_KEYDOWN repeat flag (bit 30 of lParam):
// navigation keys honour repeats, toggle keys act only on the initial press.
bool MenuHandleKey(WPARAM vk, bool repeat);

// Per-frame pixel-space primitives, queue-then-draw.  Queued from the frame
// owner (the test target now, the Present hook later) BEFORE Render() runs;
// Render() consumes the queues and resets them, so nothing survives a frame.
//   PushQuad  — axis-aligned filled quad (T2 filled-quad primitive)
//   PushLine  — line segment drawn with the line pipeline
//   PushTextA — 5x7 bitmap font rendered from quads (T2; in-code glyph data,
//               no font files, no font-related imports)
// Colours are 0xAARRGGBB, coordinates in back-buffer pixels.
void PushQuad(float x0, float y0, float x1, float y1, DWORD color);
void PushLine(float x0, float y0, float x1, float y1, DWORD color);
void PushTextA(const char* text, float x, float y, float scale, DWORD color);

// Text width helper (6*scale advance per character), for right alignment.
float TextWidthA(const char* text, float scale);

// T5: number of Render() calls (Present-hook frames) since module load.
// Incremented in the render path; a line is logged through Logf (the payload
// log path) every 600 frames and at frame 1.
unsigned long long PresentCount();

} // namespace D3D12Overlay
