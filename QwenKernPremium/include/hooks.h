#pragma once
#include <windows.h>
#include <d3d9.h>
#include <dxgi.h>

// Forward declarations
class MemoryReader;

// ============================================================================
// GameHooks — present-path interception + overlay rendering.
//
// BACKEND ORDER (decided in PHASE 0.4; do not reorder without the same reason):
//   PRIMARY  : IDXGISwapChain::Present (DXGI) — what r5apex_dx12.exe actually
//              presents through, and the only path that fires in-game.
//   FALLBACK : IDirect3DDevice9::Present (D3D9) — KEPT DELIBERATELY, not a
//              leftover.  Reasons: (a) DXVK/wine-style or `-dx9` style setups
//              present through D3D9; (b) it costs nothing at rest because
//              d3d9.dll is resolved with LoadLibrary/GetProcAddress instead of
//              being a static import, so the game process only gets the module
//              if the fallback is really taken; (c) it is the reference
//              implementation for the trampoline work in PHASE 4.
//   D3D12    : IMPLEMENTED (see d3d12_overlay.h).  r5apex_dx12.exe presents a
//              D3D12 swap chain, which has no ID3D11Device behind it, so the
//              D3D11 pipeline below can never be created for it.  The Present
//              thunk therefore calls D3D12Overlay::Render() first and only
//              falls back to RenderOverlayDX11() when the swap chain is not
//              D3D12-backed.  There is still only ONE patched slot (Present
//              index 8 on IDXGISwapChain..4) plus ResizeBuffers (index 13).
//
// PHASE 1.4 / decision D6 (measured on the live install, see
// docs\PHASE1_LADDER_AND_LIVE_ACCESS_MEASUREMENT.txt section 9): the payload
// carries NO static render imports at all.  d3d11.dll, dxgi.dll, d3d9.dll and
// d3dcompiler_47.dll are all resolved with LoadLibrary at hook time, so the IAT
// is {KERNEL32.dll, USER32.dll} and the *only* module our injection adds to
// r5apex_dx12.exe is apexcheat.dll itself.  Because the game is DX12-only
// (its own import table is just Core\Activation64.dll), d3d11.dll exists in the
// target purely as our vtable source - which is why the DX12 work in PHASE 4
// must either keep using it as a vtable oracle or move to a temp D3D12 device.
//
// Design notes (why the members below are static):
//   The hook thunks (WndProcHook / D3D9PresentHook / DXGISwapChainPresentHook)
//   are handed to Win32 and to a vtable slot, so they cannot be instance
//   methods.  Touch instance fields from a thunk and you get C2597 as well as a
//   meaningless `this` (the window subclass is process-global).  All hook state
//   is therefore static and initialised in hooks.cpp.
// ============================================================================
class GameHooks {
private:
    bool bHooksInstalled;

public:
    GameHooks();
    ~GameHooks();

    bool InstallHooks(MemoryReader* reader);
    void UninstallHooks();

    bool IsInstalled() const { return bHooksInstalled; }

    // Hook thunks
    static LRESULT CALLBACK WndProcHook(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam);

    // Present() must return HRESULT and use the STDMETHODCALLTYPE convention,
    // otherwise the vtable slot is called with the wrong ABI.
    static HRESULT STDMETHODCALLTYPE D3D9PresentHook(IDirect3DDevice9* pDevice,
                                                     CONST RECT* pSourceRect,
                                                     CONST RECT* pDestRect,
                                                     HWND hDestWindowOverride,
                                                     CONST RGNDATA* pDirtyRegion);

    // r5apex_dx12.exe presents a D3D12 swap chain, so IDXGISwapChain::Present
    // is the hook that actually fires in game; the thunk dispatches to the
    // D3D12 overlay backend first (d3d12_overlay.h).  The D3D9 path below is
    // the deliberate fallback (see the backend-order note at the top of this
    // file).
    static HRESULT STDMETHODCALLTYPE DXGISwapChainPresentHook(IDXGISwapChain* pSwapChain,
                                                              UINT syncInterval,
                                                              UINT flags);

    // IDXGISwapChain::ResizeBuffers (vtable index 13).  A D3D12 overlay keeps
    // render-target views that reference the back buffers, and ResizeBuffers()
    // fails with DXGI_ERROR_INVALID_CALL while any reference is outstanding.
    // The view heap (and the cached size) is dropped here, before the game's
    // own call, so a resolution change cannot be broken by the overlay.
    static HRESULT STDMETHODCALLTYPE DXGISwapChainResizeBuffersHook(
        IDXGISwapChain* pSwapChain, UINT bufferCount, UINT width, UINT height,
        DXGI_FORMAT newFormat, UINT swapChainFlags);

private:
    typedef HRESULT (STDMETHODCALLTYPE *PresentFunc)(IDirect3DDevice9*, CONST RECT*,
                                                     CONST RECT*, HWND,
                                                     CONST RGNDATA*);
    typedef HRESULT (STDMETHODCALLTYPE *DXGIPresentFunc)(IDXGISwapChain*, UINT, UINT);
    typedef HRESULT (STDMETHODCALLTYPE *DXGIResizeBuffersFunc)(IDXGISwapChain*, UINT,
                                                               UINT, UINT,
                                                               DXGI_FORMAT, UINT);

    static bool  FindGameWindow();
    static bool  HookPresent(IDirect3DDevice9* pDevice);
    static bool  HookPresentDXGI();
    static void  RenderOverlay(IDirect3DDevice9* pDevice);
    static void  RenderOverlayDX11(IDXGISwapChain* pSwapChain);

    // Static hook state (see class comment)
    static WNDPROC            originalWndProc;
    static PresentFunc        originalPresent;
    static DXGIPresentFunc    originalDXGIPresent;
    static DXGIResizeBuffersFunc originalDXGIResizeBuffers;
    static IDirect3DDevice9*  pHookedDevice;
    static MemoryReader*      pMemoryReader;
    static HWND               hGameWindow;
    static bool               bPresentHooked;
    static bool               bDXGIHooked;
};

// Global hook instance
extern GameHooks* g_pGameHooks;
