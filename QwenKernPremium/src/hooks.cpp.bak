#include "hooks.h"
#include "memory.h"
#include "features.h"
#include "d3d12_overlay.h"
#include "log.h"

#include <d3d11.h>
#include <d3dcompiler.h>
#include <cstdio>

// PHASE 1.4 / decision D6: there are deliberately NO #pragma comment(lib)
// here.  Every render module we touch (d3d11.dll, dxgi.dll, d3d9.dll,
// d3dcompiler_47.dll) is resolved with LoadLibrary/GetProcAddress at hook time,
// so the payload's import table stays {KERNEL32.dll, USER32.dll} and the loader
// never drags a foreign module into r5apex_dx12.exe on our behalf.
// Rationale + the measured consequences: docs\PHASE1_LADDER_AND_LIVE_ACCESS_
// MEASUREMENT.txt (section 9) and tools\BuildGate.ps1 (allowlist comment).

// ============================================================================
// Hook state (declared static in hooks.h â€” see the rationale there)
// ============================================================================
GameHooks*                 g_pGameHooks            = nullptr;
WNDPROC                    GameHooks::originalWndProc = nullptr;
GameHooks::PresentFunc     GameHooks::originalPresent = nullptr;
GameHooks::DXGIPresentFunc GameHooks::originalDXGIPresent = nullptr;
GameHooks::DXGIResizeBuffersFunc GameHooks::originalDXGIResizeBuffers = nullptr;
IDirect3DDevice9*          GameHooks::pHookedDevice = nullptr;
MemoryReader*              GameHooks::pMemoryReader = nullptr;
HWND                       GameHooks::hGameWindow   = nullptr;
bool                       GameHooks::bPresentHooked = false;
bool                       GameHooks::bDXGIHooked    = false;

GameHooks::GameHooks() : bHooksInstalled(false) {
    originalWndProc    = nullptr;
    originalPresent    = nullptr;
    originalDXGIPresent = nullptr;
    originalDXGIResizeBuffers = nullptr;
}


GameHooks::~GameHooks() {
    UninstallHooks();
}

namespace {

// r5apex.exe main window class.
const wchar_t* const kGameWindowClass = L"Respawn001";

// Vtable slots we patched (kept so UninstallHooks can restore them).
void** g_d3d9PresentSlot = nullptr;
void** g_dxgiPresentSlot = nullptr;
void** g_dxgiResizeBuffersSlot = nullptr;

// IDXGISwapChain vtable indices (identical for IDXGISwapChain..IDXGISwapChain4).
const size_t kSwapChainPresentIndex       = 8;
const size_t kSwapChainResizeBuffersIndex = 13;

// Generic vtable slot patch
template <typename TFunc>
bool PatchVtableSlot(void** slot, TFunc replacement, TFunc* originalOut) {
    DWORD oldProtect = 0;
    if (!VirtualProtect(slot, sizeof(void*), PAGE_EXECUTE_READWRITE, &oldProtect)) {
        return false;
    }

    if (originalOut) *originalOut = reinterpret_cast<TFunc>(*slot);
    *slot = reinterpret_cast<void*>(replacement);

    DWORD ignored = 0;
    VirtualProtect(slot, sizeof(void*), oldProtect, &ignored);
    FlushInstructionCache(GetCurrentProcess(), slot, sizeof(void*));
    return true;
}

// ---- D3D9 overlay primitives ----------------------------------------------
struct D3D9Vertex {
    float    x, y, z, rhw;
    D3DCOLOR color;
};

void DrawLineD3D9(IDirect3DDevice9* device, float x1, float y1,
                  float x2, float y2, DWORD color) {
    D3D9Vertex vertices[2] = {
        { x1, y1, 0.0f, 1.0f, color },
        { x2, y2, 0.0f, 1.0f, color },
    };
    device->DrawPrimitiveUP(D3DPT_LINELIST, 1, vertices, sizeof(D3D9Vertex));
}

// ---- D3D11 overlay pipeline ------------------------------------------------
// The screen size travels per-vertex instead of through a constant buffer, so
// the hook needs no per-frame state object updates beyond the vertex data.
struct D3D11Vertex {
    float x, y;
    DWORD color;
    float screenWidth, screenHeight;
};

const char kOverlayShaderSource[] = R"(
struct VSInput  { float2 position : POSITION; float4 color : COLOR0; float2 screen : TEXCOORD0; };
struct VSOutput { float4 position : SV_POSITION; float4 color : COLOR0; };

VSOutput VSMain(VSInput input) {
    VSOutput output;
    float2 ndc = (input.position / input.screen) * 2.0f - 1.0f;
    output.position = float4(ndc.x, -ndc.y, 0.0f, 1.0f);
    output.color    = input.color;
    return output;
}

float4 PSMain(VSOutput input) : SV_TARGET { return input.color; }
)";

ID3D11Device*            g_d3d11Device     = nullptr;
ID3D11DeviceContext*     g_d3d11Context    = nullptr;
ID3D11VertexShader*      g_overlayVS       = nullptr;
ID3D11PixelShader*       g_overlayPS       = nullptr;
ID3D11InputLayout*       g_overlayLayout   = nullptr;
ID3D11Buffer*            g_overlayBuffer   = nullptr;
ID3D11BlendState*        g_overlayBlend    = nullptr;
ID3D11DepthStencilState* g_overlayDepth    = nullptr;
ID3D11RasterizerState*   g_overlayRaster   = nullptr;
UINT                     g_overlayCapacity = 0;
bool                     g_d3d11Ready      = false;

// ---------------------------------------------------------------------------
// Entry points resolved on demand.
//
// d3d9.dll and d3dcompiler_47.dll are NOT loaded by r5apex.exe.  Importing
// them statically would both inject two foreign modules into the game and put
// them in the IAT - exactly what the anti-cheat's module whitelist inspects.
// ---------------------------------------------------------------------------
typedef HRESULT (WINAPI *D3DCompileFn)(LPCVOID, SIZE_T, LPCSTR,
                                       const D3D_SHADER_MACRO*, ID3DInclude*,
                                       LPCSTR, LPCSTR, UINT, UINT,
                                       ID3DBlob**, ID3DBlob**);

D3DCompileFn ResolveD3DCompile() {
    static D3DCompileFn cached = nullptr;
    if (cached) return cached;

    HMODULE compiler = LoadLibraryA("d3dcompiler_47.dll");
    if (!compiler) return nullptr;

    cached = reinterpret_cast<D3DCompileFn>(GetProcAddress(compiler, "D3DCompile"));
    return cached;
}

typedef IDirect3D9* (WINAPI *Direct3DCreate9Fn)(UINT);

Direct3DCreate9Fn ResolveDirect3DCreate9() {
    static Direct3DCreate9Fn cached = nullptr;
    if (cached) return cached;

    HMODULE d3d9Module = LoadLibraryA("d3d9.dll");
    if (!d3d9Module) return nullptr;

    cached = reinterpret_cast<Direct3DCreate9Fn>(
        GetProcAddress(d3d9Module, "Direct3DCreate9"));
    return cached;
}

// ---- d3d11.dll (lazy) ------------------------------------------------------
// d3d11.dll used to be a static import here, which contradicts the rule above:
// the target imports exactly ONE module of its own (Core\Activation64.dll) and,
// being a DX12 title, never loads d3d11.dll itself.  A static import therefore
// made LoadLibraryW(<our dll>) resolve our whole dependency set - apexcheat.dll
// AND d3d11.dll AND d3d11.dll's dxgi.dll - inside the one loader call the
// anti-cheat can watch, i.e. one foreign module plus two "was that the game?"
// modules.  Resolved lazily, the injection adds exactly one module (ours), and
// d3d11.dll appears afterwards from our own worker thread, where it is
// indistinguishable from the game loading it.
//
// typedef via decltype(&...) so the pointer type can never drift from the SDK
// declaration (the file is built /W4 /WX).
typedef decltype(&D3D11CreateDeviceAndSwapChain) D3D11CreateDeviceAndSwapChainFn;

D3D11CreateDeviceAndSwapChainFn ResolveD3D11CreateDeviceAndSwapChain() {
    static D3D11CreateDeviceAndSwapChainFn cached = nullptr;
    if (cached) return cached;

    HMODULE d3d11Module = LoadLibraryA("d3d11.dll");
    if (!d3d11Module) return nullptr;

    cached = reinterpret_cast<D3D11CreateDeviceAndSwapChainFn>(
        GetProcAddress(d3d11Module, "D3D11CreateDeviceAndSwapChain"));
    return cached;
}

void ReleaseD3D11Overlay() {
    if (g_overlayBuffer) { g_overlayBuffer->Release(); g_overlayBuffer = nullptr; }
    if (g_overlayLayout) { g_overlayLayout->Release(); g_overlayLayout = nullptr; }
    if (g_overlayPS)     { g_overlayPS->Release();     g_overlayPS     = nullptr; }
    if (g_overlayVS)     { g_overlayVS->Release();     g_overlayVS     = nullptr; }
    if (g_overlayBlend)  { g_overlayBlend->Release();  g_overlayBlend  = nullptr; }
    if (g_overlayDepth)  { g_overlayDepth->Release();  g_overlayDepth  = nullptr; }
    if (g_overlayRaster) { g_overlayRaster->Release(); g_overlayRaster = nullptr; }
    if (g_d3d11Context)  { g_d3d11Context->Release();  g_d3d11Context  = nullptr; }
    if (g_d3d11Device)   { g_d3d11Device->Release();   g_d3d11Device   = nullptr; }
    g_d3d11Ready      = false;
    g_overlayCapacity = 0;
}

} // namespace

// ============================================================================
// D3D11 pipeline (re)creation â€” called lazily from the Present thunk, i.e. on
// the first frame the game actually presents.
// ============================================================================
static bool EnsureD3D11Overlay(IDXGISwapChain* swapChain) {
    if (g_d3d11Ready) return true;
    if (!swapChain) return false;

    if (FAILED(swapChain->GetDevice(__uuidof(ID3D11Device),
                                    reinterpret_cast<void**>(&g_d3d11Device)))) {
        return false;
    }
    g_d3d11Device->GetImmediateContext(&g_d3d11Context);

    const D3DCompileFn compile = ResolveD3DCompile();
    if (!compile) {
        ReleaseD3D11Overlay();
        return false;
    }

    ID3DBlob* vsBlob = nullptr;
    ID3DBlob* psBlob = nullptr;
    ID3DBlob* errors = nullptr;

    const bool vsOk = SUCCEEDED(compile(kOverlayShaderSource,
                                            sizeof(kOverlayShaderSource) - 1,
                                            "apex_overlay", nullptr, nullptr,
                                            "VSMain", "vs_4_0",
                                            D3DCOMPILE_OPTIMIZATION_LEVEL3, 0,
                                            &vsBlob, &errors));
    const bool psOk = SUCCEEDED(compile(kOverlayShaderSource,
                                            sizeof(kOverlayShaderSource) - 1,
                                            "apex_overlay", nullptr, nullptr,
                                            "PSMain", "ps_4_0",
                                            D3DCOMPILE_OPTIMIZATION_LEVEL3, 0,
                                            &psBlob, &errors));
    if (errors) { errors->Release(); errors = nullptr; }

    if (!vsOk || !psOk) {
        if (vsBlob) vsBlob->Release();
        if (psBlob) psBlob->Release();
        ReleaseD3D11Overlay();
        return false;
    }

    bool ok = SUCCEEDED(g_d3d11Device->CreateVertexShader(vsBlob->GetBufferPointer(),
                                                          vsBlob->GetBufferSize(),
                                                          nullptr, &g_overlayVS)) &&
              SUCCEEDED(g_d3d11Device->CreatePixelShader(psBlob->GetBufferPointer(),
                                                         psBlob->GetBufferSize(),
                                                         nullptr, &g_overlayPS));

    const D3D11_INPUT_ELEMENT_DESC layout[] = {
        { "POSITION", 0, DXGI_FORMAT_R32G32_FLOAT,   0, 0,
          D3D11_INPUT_PER_VERTEX_DATA, 0 },
        { "COLOR",    0, DXGI_FORMAT_R8G8B8A8_UNORM, 0, 8,
          D3D11_INPUT_PER_VERTEX_DATA, 0 },
        { "TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT,   0, 12,
          D3D11_INPUT_PER_VERTEX_DATA, 0 },
    };

    ok = ok && SUCCEEDED(g_d3d11Device->CreateInputLayout(
        layout, ARRAYSIZE(layout), vsBlob->GetBufferPointer(),
        vsBlob->GetBufferSize(), &g_overlayLayout));

    vsBlob->Release();
    psBlob->Release();

    g_overlayCapacity = 64 * 8;   // 64 boxes x 8 vertices (4 lines per box)

    D3D11_BUFFER_DESC bufferDesc{};
    bufferDesc.ByteWidth      = g_overlayCapacity * sizeof(D3D11Vertex);
    bufferDesc.Usage          = D3D11_USAGE_DYNAMIC;
    bufferDesc.BindFlags      = D3D11_BIND_VERTEX_BUFFER;
    bufferDesc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    ok = ok && SUCCEEDED(g_d3d11Device->CreateBuffer(&bufferDesc, nullptr,
                                                      &g_overlayBuffer));

    D3D11_BLEND_DESC blendDesc{};
    blendDesc.RenderTarget[0].BlendEnable           = TRUE;
    blendDesc.RenderTarget[0].SrcBlend              = D3D11_BLEND_SRC_ALPHA;
    blendDesc.RenderTarget[0].DestBlend             = D3D11_BLEND_INV_SRC_ALPHA;
    blendDesc.RenderTarget[0].BlendOp               = D3D11_BLEND_OP_ADD;
    blendDesc.RenderTarget[0].SrcBlendAlpha         = D3D11_BLEND_ONE;
    blendDesc.RenderTarget[0].DestBlendAlpha        = D3D11_BLEND_ZERO;
    blendDesc.RenderTarget[0].BlendOpAlpha          = D3D11_BLEND_OP_ADD;
    blendDesc.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
    ok = ok && SUCCEEDED(g_d3d11Device->CreateBlendState(&blendDesc, &g_overlayBlend));

    D3D11_DEPTH_STENCIL_DESC depthDesc{};
    depthDesc.DepthEnable = FALSE;
    ok = ok && SUCCEEDED(g_d3d11Device->CreateDepthStencilState(&depthDesc,
                                                                &g_overlayDepth));

    D3D11_RASTERIZER_DESC rasterDesc{};
    rasterDesc.FillMode        = D3D11_FILL_SOLID;
    rasterDesc.CullMode        = D3D11_CULL_NONE;
    rasterDesc.DepthClipEnable = TRUE;
    ok = ok && SUCCEEDED(g_d3d11Device->CreateRasterizerState(&rasterDesc,
                                                              &g_overlayRaster));

    if (!ok) {
        ReleaseD3D11Overlay();
        return false;
    }

    g_d3d11Ready = true;
    return true;
}

// ============================================================================
// Install / uninstall
// ============================================================================
bool GameHooks::InstallHooks(MemoryReader* reader) {
    if (bHooksInstalled || !reader)
        return false;

    pMemoryReader = reader;
    FindGameWindow();

    // Apex Legends is a DX11 title: hook IDXGISwapChain::Present first.  The
    // D3D9 path is only used when d3d9.dll is already loaded in the process
    // (loading it ourselves would be an obvious module artifact).
    bDXGIHooked = HookPresentDXGI();
    if (!bDXGIHooked && GetModuleHandleA("d3d9.dll") != nullptr) {
        bPresentHooked = HookPresent(nullptr);
    }

    if (!bDXGIHooked && !bPresentHooked) {
        Logf("[-] No render backend could be hooked");
    } else {
        Logf("[+] Render hook installed (%s Present)", bDXGIHooked ? "DXGI" : "D3D9");
    }

    // Subclass the game window (overlay toggle keys / input filtering).
    if (hGameWindow) {
        originalWndProc = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(
            hGameWindow, GWLP_WNDPROC,
            reinterpret_cast<LONG_PTR>(&GameHooks::WndProcHook)));
    }

    bHooksInstalled = true;
    return bDXGIHooked || bPresentHooked;
}

void GameHooks::UninstallHooks() {
    if (!bHooksInstalled)
        return;

    if (originalWndProc && hGameWindow) {
        SetWindowLongPtrW(hGameWindow, GWLP_WNDPROC,
                          reinterpret_cast<LONG_PTR>(originalWndProc));
        originalWndProc = nullptr;
    }

    DWORD oldProtect = 0;
    if (g_dxgiResizeBuffersSlot && originalDXGIResizeBuffers) {
        if (VirtualProtect(g_dxgiResizeBuffersSlot, sizeof(void*),
                           PAGE_EXECUTE_READWRITE, &oldProtect)) {
            *g_dxgiResizeBuffersSlot =
                reinterpret_cast<void*>(originalDXGIResizeBuffers);
            VirtualProtect(g_dxgiResizeBuffersSlot, sizeof(void*), oldProtect,
                           &oldProtect);
        }
        originalDXGIResizeBuffers = nullptr;
    }
    if (g_dxgiPresentSlot && originalDXGIPresent) {
        if (VirtualProtect(g_dxgiPresentSlot, sizeof(void*),
                           PAGE_EXECUTE_READWRITE, &oldProtect)) {
            *g_dxgiPresentSlot = reinterpret_cast<void*>(originalDXGIPresent);
            VirtualProtect(g_dxgiPresentSlot, sizeof(void*), oldProtect, &oldProtect);
        }
        originalDXGIPresent = nullptr;
    }
    if (g_d3d9PresentSlot && originalPresent) {
        if (VirtualProtect(g_d3d9PresentSlot, sizeof(void*),
                           PAGE_EXECUTE_READWRITE, &oldProtect)) {
            *g_d3d9PresentSlot = reinterpret_cast<void*>(originalPresent);
            VirtualProtect(g_d3d9PresentSlot, sizeof(void*), oldProtect, &oldProtect);
        }
        originalPresent = nullptr;
    }

    ReleaseD3D11Overlay();
    D3D12Overlay::Release();
    bDXGIHooked     = false;
    bPresentHooked  = false;
    bHooksInstalled = false;
}

// ============================================================================
// Window discovery
// ============================================================================
namespace {

struct WindowSearch {
    DWORD processId;
    HWND  result;
};

BOOL CALLBACK EnumGameWindowsProc(HWND hwnd, LPARAM param) {
    WindowSearch* search = reinterpret_cast<WindowSearch*>(param);

    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid != search->processId) return TRUE;
    if (!IsWindowVisible(hwnd)) return TRUE;
    if (GetWindow(hwnd, GW_OWNER) != nullptr) return TRUE;
    if (GetWindowTextLengthW(hwnd) == 0) return TRUE;

    search->result = hwnd;
    return FALSE;
}

} // namespace

bool GameHooks::FindGameWindow() {
    if (hGameWindow && IsWindow(hGameWindow)) return true;

    // Primary: the known r5apex window class.  Fallback: any visible
    // top-level window owned by our own process (covers class renames).
    hGameWindow = FindWindowW(kGameWindowClass, nullptr);
    if (hGameWindow) return true;

    WindowSearch search{ GetCurrentProcessId(), nullptr };
    EnumWindows(EnumGameWindowsProc, reinterpret_cast<LPARAM>(&search));
    hGameWindow = search.result;
    return hGameWindow != nullptr;
}

// ============================================================================
// D3D9 Present hook (idx 17 of IDirect3DDevice9)
// ============================================================================
bool GameHooks::HookPresent(IDirect3DDevice9* pDevice) {
    if (bPresentHooked) return true;
    (void)pDevice;

    HWND dummyWindow = CreateWindowExW(0, L"STATIC", L"apex_dummy", WS_POPUP,
                                       0, 0, 8, 8, nullptr, nullptr, nullptr, nullptr);
    if (!dummyWindow) return false;

    const Direct3DCreate9Fn createD3D9 = ResolveDirect3DCreate9();
    IDirect3D9* d3d9 = createD3D9 ? createD3D9(D3D_SDK_VERSION) : nullptr;
    if (!d3d9) {
        DestroyWindow(dummyWindow);
        return false;
    }

    D3DPRESENT_PARAMETERS params{};
    params.Windowed         = TRUE;
    params.hDeviceWindow    = dummyWindow;
    params.SwapEffect       = D3DSWAPEFFECT_DISCARD;
    params.BackBufferFormat = D3DFMT_UNKNOWN;

    IDirect3DDevice9* dummyDevice = nullptr;
    if (FAILED(d3d9->CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, dummyWindow,
                                  D3DCREATE_SOFTWARE_VERTEXPROCESSING,
                                  &params, &dummyDevice))) {
        d3d9->Release();
        DestroyWindow(dummyWindow);
        return false;
    }

    void** vtable = *reinterpret_cast<void***>(dummyDevice);
    g_d3d9PresentSlot = &vtable[17];

    const bool patched = PatchVtableSlot(g_d3d9PresentSlot,
                                         &GameHooks::D3D9PresentHook,
                                         &originalPresent);
    dummyDevice->Release();
    d3d9->Release();
    DestroyWindow(dummyWindow);

    bPresentHooked = patched;
    return patched;
}

// ============================================================================
// DXGI SwapChain::Present hook (idx 8 of IDXGISwapChain)
// ============================================================================
bool GameHooks::HookPresentDXGI() {
    if (bDXGIHooked) return true;

    HWND dummyWindow = CreateWindowExW(0, L"STATIC", L"apex_dummy", WS_POPUP,
                                       0, 0, 8, 8, nullptr, nullptr, nullptr, nullptr);
    if (!dummyWindow) return false;

    DXGI_SWAP_CHAIN_DESC desc{};
    desc.BufferCount                        = 1;
    desc.BufferDesc.Width                  = 8;
    desc.BufferDesc.Height                 = 8;
    desc.BufferDesc.Format                 = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.BufferUsage                        = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    desc.OutputWindow                       = dummyWindow;
    desc.SampleDesc.Count                   = 1;
    desc.Windowed                           = TRUE;
    desc.SwapEffect                         = DXGI_SWAP_EFFECT_DISCARD;

    // Lazily resolved - NOT a static import (decision D6).  A failure here means
    // d3d11.dll could not be mapped, which is also the honest reason the DXGI
    // vtable could not be discovered (report it, do not fall through silently).
    const D3D11CreateDeviceAndSwapChainFn createDeviceAndSwapChain =
        ResolveD3D11CreateDeviceAndSwapChain();
    if (!createDeviceAndSwapChain) {
        Logf("[-] d3d11.dll unavailable - DXGI swap-chain vtable not discoverable");
        DestroyWindow(dummyWindow);
        return false;
    }

    ID3D11Device*        device    = nullptr;
    ID3D11DeviceContext* context   = nullptr;
    IDXGISwapChain*      swapChain = nullptr;
    D3D_FEATURE_LEVEL     level     = D3D_FEATURE_LEVEL_11_0;

    HRESULT hr = createDeviceAndSwapChain(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, nullptr, 0,
        D3D11_SDK_VERSION, &desc, &swapChain, &device, &level, &context);

    if (FAILED(hr)) {
        // Headless/VM fallback: WARP still exposes the same dxgi vtable.
        hr = createDeviceAndSwapChain(
            nullptr, D3D_DRIVER_TYPE_WARP, nullptr, 0, nullptr, 0,
            D3D11_SDK_VERSION, &desc, &swapChain, &device, &level, &context);
    }

    if (FAILED(hr) || !swapChain) {
        if (context) context->Release();
        if (device)  device->Release();
        DestroyWindow(dummyWindow);
        return false;
    }

    void** vtable = *reinterpret_cast<void***>(swapChain);
    g_dxgiPresentSlot       = &vtable[kSwapChainPresentIndex];
    g_dxgiResizeBuffersSlot = &vtable[kSwapChainResizeBuffersIndex];

    const bool patched = PatchVtableSlot(g_dxgiPresentSlot,
                                         &GameHooks::DXGISwapChainPresentHook,
                                         &originalDXGIPresent);

    // ResizeBuffers is secondary: if it cannot be patched the overlay still
    // works, it just re-creates its views from the Present hook instead
    // (D3D12Overlay::Render compares the swap-chain description every frame).
    if (patched) {
        PatchVtableSlot(g_dxgiResizeBuffersSlot,
                        &GameHooks::DXGISwapChainResizeBuffersHook,
                        &originalDXGIResizeBuffers);
    }

    swapChain->Release();
    context->Release();
    device->Release();
    DestroyWindow(dummyWindow);

    bDXGIHooked = patched;
    return patched;
}

// ============================================================================
// Hook thunks
// ============================================================================
LRESULT CALLBACK GameHooks::WndProcHook(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
    // INSERT toggles the ESP overlay without touching the render thread.
    if (uMsg == WM_KEYDOWN && wParam == VK_INSERT && g_pCheatFeatures) {
        const bool enabled = g_pCheatFeatures->IsFeatureEnabled(FEATURE_ESP);
        g_pCheatFeatures->EnableFeature(FEATURE_ESP, !enabled);
        Logf("[*] ESP %s", enabled ? "disabled" : "enabled");
    }

    if (originalWndProc) {
        return CallWindowProcW(originalWndProc, hwnd, uMsg, wParam, lParam);
    }
    return DefWindowProcW(hwnd, uMsg, wParam, lParam);
}

HRESULT STDMETHODCALLTYPE GameHooks::D3D9PresentHook(IDirect3DDevice9* pDevice,
                                                     CONST RECT* pSourceRect,
                                                     CONST RECT* pDestRect,
                                                     HWND hDestWindowOverride,
                                                     CONST RGNDATA* pDirtyRegion) {
    // Draw before the real Present so the overlay lands in this frame.
    if (pDevice) {
        RenderOverlay(pDevice);
    }

    if (!originalPresent) return D3DERR_DEVICELOST;
    return originalPresent(pDevice, pSourceRect, pDestRect, hDestWindowOverride, pDirtyRegion);
}

HRESULT STDMETHODCALLTYPE GameHooks::DXGISwapChainPresentHook(IDXGISwapChain* pSwapChain,
                                                              UINT syncInterval,
                                                              UINT flags) {
    if (pSwapChain) {
        // One-shot confirmation that the vtable patch really fires in game.  A
        // silent "no ESP" is otherwise indistinguishable from "the hook was
        // never called" when reading the log afterwards.
        static LONG s_presentHits = 0;
        if (InterlockedExchange(&s_presentHits, 1) == 0) {
            Logf("[*] DXGI Present hook fired (swap chain %p)", pSwapChain);
        }

        // r5apex_dx12.exe presents a D3D12 swap chain, so the D3D11 pipeline
        // below can never be created for it (a D3D12 swap chain has no
        // ID3D11Device behind it - GetDevice() fails and the old code just
        // returned, which is why the overlay was invisible in game).
        //
        // D3D12Overlay::Render() returns false ONLY when the swap chain is not
        // D3D12-backed, so a D3D11 title still reaches the original path.
        if (!D3D12Overlay::Render(pSwapChain)) {
            RenderOverlayDX11(pSwapChain);
        }
    }

    if (!originalDXGIPresent) return S_OK;
    return originalDXGIPresent(pSwapChain, syncInterval, flags);
}

HRESULT STDMETHODCALLTYPE GameHooks::DXGISwapChainResizeBuffersHook(
    IDXGISwapChain* pSwapChain, UINT bufferCount, UINT width, UINT height,
    DXGI_FORMAT newFormat, UINT swapChainFlags) {
    // Drop every reference the overlay holds on the old back buffers; otherwise
    // ResizeBuffers() fails with DXGI_ERROR_INVALID_CALL and the game loses its
    // swap chain.  Both calls are cheap and idempotent.  Resizes are rare, so
    // they are logged unconditionally (a good marker in the log timeline).
    Logf("[*] ResizeBuffers(%ux%u, buffers=%u) - dropping overlay resources",
         width, height, bufferCount);
    D3D12Overlay::OnResize();
    ReleaseD3D11Overlay();

    if (!originalDXGIResizeBuffers) return E_FAIL;
    return originalDXGIResizeBuffers(pSwapChain, bufferCount, width, height,
                                     newFormat, swapChainFlags);
}

// ============================================================================
// D3D9 overlay rendering
// ============================================================================
void GameHooks::RenderOverlay(IDirect3DDevice9* pDevice) {
    if (!pDevice) return;

    D3DVIEWPORT9 viewport{};
    if (FAILED(pDevice->GetViewport(&viewport))) return;

    g_ScreenWidth  = static_cast<int>(viewport.Width);
    g_ScreenHeight = static_cast<int>(viewport.Height);

    const LONG boxCount = g_EspBoxCount;
    if (boxCount <= 0) return;

    pDevice->SetFVF(D3DFVF_XYZRHW | D3DFVF_DIFFUSE);
    pDevice->SetTexture(0, nullptr);
    pDevice->SetRenderState(D3DRS_LIGHTING, FALSE);
    pDevice->SetRenderState(D3DRS_ZENABLE,  D3DZB_FALSE);
    pDevice->SetRenderState(D3DRS_ALPHABLENDENABLE, TRUE);
    pDevice->SetRenderState(D3DRS_SRCBLEND,  D3DBLEND_SRCALPHA);
    pDevice->SetRenderState(D3DRS_DESTBLEND, D3DBLEND_INVSRCALPHA);

    for (LONG i = 0; i < boxCount && i < MAX_ESP_BOXES; ++i) {
        const ESPBox& box = g_EspBoxes[i];
        const DWORD color = box.color;

        DrawLineD3D9(pDevice, box.left, box.top,    box.right, box.top,    color);
        DrawLineD3D9(pDevice, box.left, box.bottom, box.right, box.bottom, color);
        DrawLineD3D9(pDevice, box.left, box.top,    box.left,  box.bottom, color);
        DrawLineD3D9(pDevice, box.right, box.top,   box.right, box.bottom, color);
    }
}

// ============================================================================
// DXGI / D3D11 overlay rendering
// ============================================================================
void GameHooks::RenderOverlayDX11(IDXGISwapChain* pSwapChain) {
    if (!pSwapChain) return;

    DXGI_SWAP_CHAIN_DESC desc{};
    if (FAILED(pSwapChain->GetDesc(&desc))) return;

    g_ScreenWidth  = static_cast<int>(desc.BufferDesc.Width);
    g_ScreenHeight = static_cast<int>(desc.BufferDesc.Height);

    const LONG boxCount = g_EspBoxCount;
    if (boxCount <= 0) return;
    if (!EnsureD3D11Overlay(pSwapChain)) return;

    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(g_d3d11Context->Map(g_overlayBuffer, 0, D3D11_MAP_WRITE_DISCARD,
                                    0, &mapped))) {
        return;
    }

    D3D11Vertex* vertices = reinterpret_cast<D3D11Vertex*>(mapped.pData);
    UINT vertexCount = 0;
    const float screenW = static_cast<float>(g_ScreenWidth);
    const float screenH = static_cast<float>(g_ScreenHeight);

    for (LONG i = 0; i < boxCount && i < MAX_ESP_BOXES; ++i) {
        if (vertexCount + 8 > g_overlayCapacity) break;

        const ESPBox& box = g_EspBoxes[i];
        const DWORD color = box.color;

        // 4 lines => 8 vertices (LINELIST): top, bottom, left, right.
        const float lineCoords[4][4] = {
            { box.left,  box.top,    box.right, box.top    },
            { box.left,  box.bottom, box.right, box.bottom },
            { box.left,  box.top,    box.left,  box.bottom },
            { box.right, box.top,    box.right, box.bottom },
        };

        for (int line = 0; line < 4; ++line) {
            vertices[vertexCount].x            = lineCoords[line][0];
            vertices[vertexCount].y            = lineCoords[line][1];
            vertices[vertexCount].color        = color;
            vertices[vertexCount].screenWidth  = screenW;
            vertices[vertexCount].screenHeight = screenH;
            ++vertexCount;

            vertices[vertexCount].x            = lineCoords[line][2];
            vertices[vertexCount].y            = lineCoords[line][3];
            vertices[vertexCount].color        = color;
            vertices[vertexCount].screenWidth  = screenW;
            vertices[vertexCount].screenHeight = screenH;
            ++vertexCount;
        }
    }

    g_d3d11Context->Unmap(g_overlayBuffer, 0);
    if (vertexCount == 0) return;

    const UINT stride = sizeof(D3D11Vertex);
    const UINT offset = 0;

    g_d3d11Context->IASetInputLayout(g_overlayLayout);
    g_d3d11Context->IASetVertexBuffers(0, 1, &g_overlayBuffer, &stride, &offset);
    g_d3d11Context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_LINELIST);
    g_d3d11Context->VSSetShader(g_overlayVS, nullptr, 0);
    g_d3d11Context->PSSetShader(g_overlayPS, nullptr, 0);
    g_d3d11Context->OMSetBlendState(g_overlayBlend, nullptr, 0xFFFFFFFF);
    g_d3d11Context->OMSetDepthStencilState(g_overlayDepth, 0);
    g_d3d11Context->RSSetState(g_overlayRaster);
    g_d3d11Context->Draw(vertexCount, 0);
}