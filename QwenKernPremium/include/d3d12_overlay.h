#pragma once
#include <windows.h>
#include <dxgi.h>

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

} // namespace D3D12Overlay
