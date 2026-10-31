#include "d3d12_overlay.h"
#include "features.h"
#include "log.h"

#include <d3d12.h>
#include <dxgi1_4.h>
#include <d3dcompiler.h>

// NOTE: d3d12.dll / d3dcompiler_47.dll are resolved with GetProcAddress, never
// linked, so this translation unit adds no entry to the payload's IAT.

namespace {

// ---------------------------------------------------------------------------
// Vertex format shared with the shaders below.
//
// ESP boxes arrive in back-buffer pixels (features.cpp projects world space to
// screen space there).  Positions are converted to normalised device
// coordinates on the CPU, so the vertex shader is a pure pass-through and the
// same vertex data would work for any viewport.
// ---------------------------------------------------------------------------
struct OverlayVertex {
    float x, y;          // NDC
    float r, g, b, a;
};

const UINT kMaxVertices = MAX_ESP_BOXES * 8u;      // 4 lines x 2 vertices
const UINT kVbBytes     = kMaxVertices * sizeof(OverlayVertex);

// ---------------------------------------------------------------------------
// Resolved entry points (no static imports — see file header)
// ---------------------------------------------------------------------------
typedef HRESULT (WINAPI *D3DCompileFn)(LPCVOID pSrcData, SIZE_T SrcDataSize,
                                       LPCSTR pSourceName,
                                       const D3D_SHADER_MACRO* pDefines,
                                       ID3DInclude* pInclude, LPCSTR pEntrypoint,
                                       LPCSTR pTarget, UINT Flags1, UINT Flags2,
                                       ID3DBlob** ppCode, ID3DBlob** ppErrorMsgs);

typedef HRESULT (WINAPI *D3D12SerializeRootSignatureFn)(
    const D3D12_ROOT_SIGNATURE_DESC* pRootSignature,
    D3D_ROOT_SIGNATURE_VERSION Version,
    ID3DBlob** ppBlob, ID3DBlob** ppErrorBlob);

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
ID3D12Device*               g_device        = nullptr;
ID3D12CommandQueue*         g_queue         = nullptr;   // game's queue when reachable
ID3D12CommandAllocator*     g_allocator     = nullptr;
ID3D12GraphicsCommandList*  g_commandList   = nullptr;
ID3D12RootSignature*        g_rootSignature = nullptr;
ID3D12PipelineState*        g_pipelineState = nullptr;
ID3D12DescriptorHeap*       g_rtvHeap       = nullptr;

ID3D12Fence*                g_fence         = nullptr;
HANDLE                      g_fenceEvent    = nullptr;
UINT64                      g_fenceValue    = 0;

ID3D12Resource*             g_vertexBuffer  = nullptr;
OverlayVertex*              g_vertexMapped  = nullptr;

UINT        g_rtvStride      = 0;
UINT        g_rtvCount       = 0;
UINT        g_width          = 0;
UINT        g_height         = 0;
DXGI_FORMAT g_format         = DXGI_FORMAT_UNKNOWN;
UINT        g_sampleCount    = 1;
bool        g_usesOwnQueue   = false;
bool        g_ready          = false;

// One-shot latches so a broken state (or a per-frame event) does not spam the
// log at 240 Hz.
bool g_loggedNotD3D12 = false;
bool g_loggedQueue    = false;
bool g_loggedDraw     = false;

template <typename T>
void SafeRelease(T*& pointer) {
    if (pointer) {
        pointer->Release();
        pointer = nullptr;
    }
}

D3D12_RESOURCE_BARRIER TransitionBarrier(ID3D12Resource* resource,
                                         D3D12_RESOURCE_STATES before,
                                         D3D12_RESOURCE_STATES after) {
    D3D12_RESOURCE_BARRIER barrier{};
    barrier.Type                   = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Flags                  = D3D12_RESOURCE_BARRIER_FLAG_NONE;
    barrier.Transition.pResource   = resource;
    barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    barrier.Transition.StateBefore = before;
    barrier.Transition.StateAfter  = after;
    return barrier;
}

// Blocks until every command list we submitted has completed.  Needed before
// the command allocator is reset and before the mapped vertex buffer is
// overwritten; a 1 s timeout keeps a wedged GPU from hanging the game thread.
void WaitForGpu() {
    if (!g_fence || !g_fenceEvent || g_fenceValue == 0) return;
    if (g_fence->GetCompletedValue() >= g_fenceValue) return;

    if (SUCCEEDED(g_fence->SetEventOnCompletion(g_fenceValue, g_fenceEvent))) {
        WaitForSingleObject(g_fenceEvent, 1000);
    }
}

// ============================================================================
// Shaders — deliberately trivial: the CPU already produced NDC vertices, so a
// pass-through VS and a colour-copy PS are all that is required.  Compiled at
// init with D3DCompile, which means no .cso files to ship or map.
// ============================================================================
const char* const kShaderSource =
    "struct VSIn  { float2 pos : POSITION; float4 color : COLOR; };\n"
    "struct VSOut { float4 pos : SV_Position; float4 color : COLOR; };\n"
    "VSOut VSMain(VSIn input) {\n"
    "    VSOut output;\n"
    "    output.pos   = float4(input.pos, 0.0f, 1.0f);\n"
    "    output.color = input.color;\n"
    "    return output;\n"
    "}\n"
    "float4 PSMain(VSOut input) : SV_Target {\n"
    "    return input.color;\n"
    "}\n";

D3DCompileFn ResolveD3DCompile() {
    // d3dcompiler_47 ships with the OS on every supported Windows 10/11 build.
    // Older names are tried only as a courtesy for stripped-down images.
    static const wchar_t* const kCandidates[] = {
        L"d3dcompiler_47.dll", L"d3dcompiler_46.dll", L"d3dcompiler_43.dll"
    };
    static D3DCompileFn cached = nullptr;
    if (cached) return cached;

    for (size_t i = 0; i < sizeof(kCandidates) / sizeof(kCandidates[0]); ++i) {
        HMODULE module = GetModuleHandleW(kCandidates[i]);
        if (!module) module = LoadLibraryW(kCandidates[i]);
        if (!module) continue;

        cached = reinterpret_cast<D3DCompileFn>(
            reinterpret_cast<void*>(GetProcAddress(module, "D3DCompile")));
        if (cached) return cached;
    }

    Logf("[-] d3d12: D3DCompile not found, overlay shaders cannot be compiled");
    return nullptr;
}

bool CompileShaders(ID3DBlob** vsOut, ID3DBlob** psOut) {
    const D3DCompileFn compile = ResolveD3DCompile();
    if (!compile) return false;

    const UINT flags = D3DCOMPILE_ENABLE_STRICTNESS | D3DCOMPILE_OPTIMIZATION_LEVEL3;

    ID3DBlob* errors = nullptr;
    HRESULT hr = compile(kShaderSource, strlen(kShaderSource), "overlay",
                         nullptr, nullptr, "VSMain", "vs_5_0", flags, 0,
                         vsOut, &errors);
    if (FAILED(hr) || !*vsOut) {
        Logf("[-] d3d12: vs_5_0 compile failed hr=0x%08X %s", hr,
             errors ? static_cast<const char*>(errors->GetBufferPointer()) : "");
        if (errors) { errors->Release(); errors = nullptr; }
        return false;
    }
    if (errors) { errors->Release(); errors = nullptr; }

    hr = compile(kShaderSource, strlen(kShaderSource), "overlay",
                 nullptr, nullptr, "PSMain", "ps_5_0", flags, 0,
                 psOut, &errors);
    if (FAILED(hr) || !*psOut) {
        Logf("[-] d3d12: ps_5_0 compile failed hr=0x%08X %s", hr,
             errors ? static_cast<const char*>(errors->GetBufferPointer()) : "");
        if (errors) errors->Release();
        SafeRelease(*vsOut);
        return false;
    }
    if (errors) errors->Release();
    return true;
}

} // namespace

namespace {

bool CreateRootSignature() {
    HMODULE d3d12 = LoadLibraryW(L"d3d12.dll");
    if (!d3d12) {
        Logf("[-] d3d12: LoadLibrary(d3d12.dll) failed error=%lu", GetLastError());
        return false;
    }

    const D3D12SerializeRootSignatureFn serialize =
        reinterpret_cast<D3D12SerializeRootSignatureFn>(
            reinterpret_cast<void*>(GetProcAddress(d3d12,
                                                   "D3D12SerializeRootSignature")));
    if (!serialize) {
        Logf("[-] d3d12: D3D12SerializeRootSignature not exported");
        return false;
    }

    // Empty root signature: no CBVs/SRVs/UAVs, no samplers.  Vertices already
    // carry NDC positions and their colour, so nothing has to be bound.
    D3D12_ROOT_SIGNATURE_DESC desc{};
    desc.NumParameters     = 0;
    desc.pParameters       = nullptr;
    desc.NumStaticSamplers = 0;
    desc.pStaticSamplers   = nullptr;
    desc.Flags = D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT;

    ID3DBlob* blob  = nullptr;
    ID3DBlob* error = nullptr;
    HRESULT hr = serialize(&desc, D3D_ROOT_SIGNATURE_VERSION_1, &blob, &error);
    if (FAILED(hr) || !blob) {
        Logf("[-] d3d12: SerializeRootSignature failed hr=0x%08X %s", hr,
             error ? static_cast<const char*>(error->GetBufferPointer()) : "");
        if (error) error->Release();
        return false;
    }

    hr = g_device->CreateRootSignature(0, blob->GetBufferPointer(),
                                       blob->GetBufferSize(),
                                       __uuidof(ID3D12RootSignature),
                                       reinterpret_cast<void**>(&g_rootSignature));
    blob->Release();
    if (error) error->Release();

    if (FAILED(hr)) {
        Logf("[-] d3d12: CreateRootSignature failed hr=0x%08X", hr);
        return false;
    }
    return true;
}

bool CreatePipelineState() {
    ID3DBlob* vsBlob = nullptr;
    ID3DBlob* psBlob = nullptr;
    if (!CompileShaders(&vsBlob, &psBlob)) return false;

    const D3D12_INPUT_ELEMENT_DESC layout[] = {
        { "POSITION", 0, DXGI_FORMAT_R32G32_FLOAT,       0, 0,
          D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0 },
        { "COLOR",    0, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, 8,
          D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0 },
    };

    D3D12_GRAPHICS_PIPELINE_STATE_DESC desc{};
    desc.pRootSignature        = g_rootSignature;
    desc.VS                    = { vsBlob->GetBufferPointer(), vsBlob->GetBufferSize() };
    desc.PS                    = { psBlob->GetBufferPointer(), psBlob->GetBufferSize() };
    desc.InputLayout           = { layout, _countof(layout) };
    desc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_LINE;
    desc.SampleMask            = UINT_MAX;

    // Alpha blending, no depth, no culling: an overlay must not be occluded by
    // the frame it is drawn onto.
    desc.RTVFormats[0]    = g_format;
    desc.NumRenderTargets = 1;
    desc.SampleDesc.Count = g_sampleCount;
    desc.SampleDesc.Quality = 0;

    desc.RasterizerState.FillMode              = D3D12_FILL_MODE_SOLID;
    desc.RasterizerState.CullMode              = D3D12_CULL_MODE_NONE;
    desc.RasterizerState.FrontCounterClockwise = FALSE;
    desc.RasterizerState.DepthClipEnable       = FALSE;

    desc.BlendState.RenderTarget[0].BlendEnable    = TRUE;
    desc.BlendState.RenderTarget[0].SrcBlend       = D3D12_BLEND_SRC_ALPHA;
    desc.BlendState.RenderTarget[0].DestBlend      = D3D12_BLEND_INV_SRC_ALPHA;
    desc.BlendState.RenderTarget[0].BlendOp        = D3D12_BLEND_OP_ADD;
    desc.BlendState.RenderTarget[0].SrcBlendAlpha  = D3D12_BLEND_ONE;
    desc.BlendState.RenderTarget[0].DestBlendAlpha = D3D12_BLEND_INV_SRC_ALPHA;
    desc.BlendState.RenderTarget[0].BlendOpAlpha   = D3D12_BLEND_OP_ADD;
    desc.BlendState.RenderTarget[0].RenderTargetWriteMask = D3D12_COLOR_WRITE_ENABLE_ALL;

    desc.DepthStencilState.DepthEnable    = FALSE;
    desc.DepthStencilState.StencilEnable  = FALSE;
    desc.DepthStencilState.DepthWriteMask = D3D12_DEPTH_WRITE_MASK_ZERO;

    const HRESULT hr = g_device->CreateGraphicsPipelineState(
        &desc, __uuidof(ID3D12PipelineState),
        reinterpret_cast<void**>(&g_pipelineState));

    vsBlob->Release();
    psBlob->Release();

    if (FAILED(hr)) {
        Logf("[-] d3d12: CreateGraphicsPipelineState failed hr=0x%08X", hr);
        return false;
    }
    return true;
}

bool CreateUploadBuffer() {
    D3D12_HEAP_PROPERTIES heap{};
    heap.Type                 = D3D12_HEAP_TYPE_UPLOAD;
    heap.CPUPageProperty      = D3D12_CPU_PAGE_PROPERTY_UNKNOWN;
    heap.MemoryPoolPreference = D3D12_MEMORY_POOL_UNKNOWN;
    heap.CreationNodeMask     = 1;
    heap.VisibleNodeMask      = 1;

    D3D12_RESOURCE_DESC resource{};
    resource.Dimension        = D3D12_RESOURCE_DIMENSION_BUFFER;
    resource.Alignment        = 0;
    resource.Width            = kVbBytes;
    resource.Height           = 1;
    resource.DepthOrArraySize = 1;
    resource.MipLevels        = 1;
    resource.Format           = DXGI_FORMAT_UNKNOWN;
    resource.SampleDesc.Count = 1;
    resource.Layout           = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    resource.Flags            = D3D12_RESOURCE_FLAG_NONE;

    const HRESULT hr = g_device->CreateCommittedResource(
        &heap, D3D12_HEAP_FLAG_NONE, &resource,
        D3D12_RESOURCE_STATE_GENERIC_READ, nullptr,
        __uuidof(ID3D12Resource), reinterpret_cast<void**>(&g_vertexBuffer));
    if (FAILED(hr)) {
        Logf("[-] d3d12: vertex buffer creation failed hr=0x%08X", hr);
        return false;
    }

    void* mapped = nullptr;
    D3D12_RANGE readRange{ 0, 0 };            // write-only mapping
    if (FAILED(g_vertexBuffer->Map(0, &readRange, &mapped)) || !mapped) {
        Logf("[-] d3d12: vertex buffer Map failed");
        SafeRelease(g_vertexBuffer);
        return false;
    }

    g_vertexMapped = static_cast<OverlayVertex*>(mapped);
    return true;
}

// Creates one RTV per swap-chain buffer.  Re-run after every ResizeBuffers
// (OnResize() drops the heap so the next Render() rebuilds it).
bool CreateRenderTargets(IDXGISwapChain* pSwapChain, UINT bufferCount) {
    const UINT wanted = bufferCount ? bufferCount : 1;
    if (g_rtvHeap && g_rtvCount >= wanted) return true;

    SafeRelease(g_rtvHeap);
    g_rtvCount = 0;

    D3D12_DESCRIPTOR_HEAP_DESC heapDesc{};
    heapDesc.Type           = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
    heapDesc.NumDescriptors = wanted;
    heapDesc.Flags          = D3D12_DESCRIPTOR_HEAP_FLAG_NONE;

    HRESULT hr = g_device->CreateDescriptorHeap(&heapDesc,
                                                __uuidof(ID3D12DescriptorHeap),
                                                reinterpret_cast<void**>(&g_rtvHeap));
    if (FAILED(hr)) {
        Logf("[-] d3d12: CreateDescriptorHeap(RTV) failed hr=0x%08X", hr);
        return false;
    }

    g_rtvStride = g_device->GetDescriptorHandleIncrementSize(
        D3D12_DESCRIPTOR_HEAP_TYPE_RTV);

    D3D12_CPU_DESCRIPTOR_HANDLE handle = g_rtvHeap->GetCPUDescriptorHandleForHeapStart();
    for (UINT i = 0; i < wanted; ++i) {
        ID3D12Resource* backBuffer = nullptr;
        hr = pSwapChain->GetBuffer(i, __uuidof(ID3D12Resource),
                                   reinterpret_cast<void**>(&backBuffer));
        if (FAILED(hr) || !backBuffer) {
            Logf("[-] d3d12: GetBuffer(%u) failed hr=0x%08X", i, hr);
            break;      // fewer views than buffers is fine; Render() checks
        }

        // The view keeps its own reference; release ours so the game's
        // ResizeBuffers() can reclaim the buffer (see the header).
        g_device->CreateRenderTargetView(backBuffer, nullptr, handle);
        backBuffer->Release();

        ++g_rtvCount;
        handle.ptr += g_rtvStride;
    }

    return g_rtvCount > 0;
}

// One-time (per device) initialisation: everything that depends on the swap
// chain's description is created here so a format/size change just rebuilds.
bool CreateDeviceObjects(IDXGISwapChain* pSwapChain) {
    DXGI_SWAP_CHAIN_DESC desc{};
    if (FAILED(pSwapChain->GetDesc(&desc))) {
        Logf("[-] d3d12: IDXGISwapChain::GetDesc failed");
        return false;
    }

    g_width       = desc.BufferDesc.Width;
    g_height      = desc.BufferDesc.Height;
    g_format      = desc.BufferDesc.Format;
    g_sampleCount = desc.SampleDesc.Count ? desc.SampleDesc.Count : 1;

    // CreateSwapChainForHwnd() is handed the game's command queue, and
    // IDXGISwapChain::GetDevice() returns that same object.  Using it keeps our
    // draws ordered with the frame's own work and needs no extra queue.
    ID3D12CommandQueue* queue = nullptr;
    if (SUCCEEDED(pSwapChain->GetDevice(__uuidof(ID3D12CommandQueue),
                                        reinterpret_cast<void**>(&queue))) && queue) {
        g_queue = queue;
    } else {
        SafeRelease(g_queue);

        if (FAILED(pSwapChain->GetDevice(__uuidof(ID3D12Device),
                                         reinterpret_cast<void**>(&g_device))) ||
            !g_device) {
            if (!g_loggedNotD3D12) {
                g_loggedNotD3D12 = true;
                Logf("[*] d3d12: swap chain is not backed by a D3D12 device; "
                     "falling back to the D3D11 overlay");
            }
            return false;
        }

        D3D12_COMMAND_QUEUE_DESC queueDesc{};
        queueDesc.Type     = D3D12_COMMAND_LIST_TYPE_DIRECT;
        queueDesc.Priority = D3D12_COMMAND_QUEUE_PRIORITY_NORMAL;
        queueDesc.Flags    = D3D12_COMMAND_QUEUE_FLAG_NONE;
        if (FAILED(g_device->CreateCommandQueue(
                &queueDesc, __uuidof(ID3D12CommandQueue),
                reinterpret_cast<void**>(&g_queue)))) {
            Logf("[-] d3d12: CreateCommandQueue failed");
            SafeRelease(g_device);
            return false;
        }
        g_usesOwnQueue = true;
        if (!g_loggedQueue) {
            g_loggedQueue = true;
            Logf("[*] d3d12: the swap chain does not expose the game's queue - "
                 "using a private DIRECT queue");
        }
    }

    // A command queue is a device child: QI it for the device it came from.
    if (!g_device) {
        if (FAILED(g_queue->GetDevice(__uuidof(ID3D12Device),
                                      reinterpret_cast<void**>(&g_device))) ||
            !g_device) {
            Logf("[-] d3d12: ID3D12CommandQueue::GetDevice failed");
            SafeRelease(g_queue);
            return false;
        }
    }

    if (FAILED(g_device->CreateCommandAllocator(
            D3D12_COMMAND_LIST_TYPE_DIRECT, __uuidof(ID3D12CommandAllocator),
            reinterpret_cast<void**>(&g_allocator)))) {
        Logf("[-] d3d12: CreateCommandAllocator failed");
        return false;
    }

    if (FAILED(g_device->CreateCommandList(
            0, D3D12_COMMAND_LIST_TYPE_DIRECT, g_allocator, nullptr,
            __uuidof(ID3D12GraphicsCommandList),
            reinterpret_cast<void**>(&g_commandList)))) {
        Logf("[-] d3d12: CreateCommandList failed");
        return false;
    }
    g_commandList->Close();         // created open; keep it closed until use

    if (FAILED(g_device->CreateFence(0, D3D12_FENCE_FLAG_NONE,
                                     __uuidof(ID3D12Fence),
                                     reinterpret_cast<void**>(&g_fence)))) {
        Logf("[-] d3d12: CreateFence failed");
        return false;
    }

    g_fenceEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!g_fenceEvent) {
        Logf("[-] d3d12: CreateEvent(fence) failed error=%lu", GetLastError());
        return false;
    }

    if (!CreateRootSignature()) return false;
    if (!CreatePipelineState()) return false;
    if (!CreateUploadBuffer())  return false;
    if (!CreateRenderTargets(pSwapChain, desc.BufferCount)) return false;

    g_ready = true;
    Logf("[+] d3d12: overlay ready (%ux%u fmt=%u samples=%u buffers=%u queue=%s)",
         g_width, g_height, static_cast<unsigned>(g_format), g_sampleCount,
         desc.BufferCount, g_usesOwnQueue ? "private" : "game");
    return true;
}

} // namespace

namespace D3D12Overlay {

bool Ensure(IDXGISwapChain* pSwapChain) {
    if (g_ready) return g_device != nullptr && g_queue != nullptr;
    if (!pSwapChain) return false;

    const bool ok = CreateDeviceObjects(pSwapChain);
    if (!ok && !g_device) return false;      // not D3D12 => caller falls back
    if (!ok) {
        // Partially built on a real D3D12 chain: tear down and retry next frame.
        Release();
    }
    return g_ready;
}

void OnResize() {
    // Only the views are size-dependent.  Dropping the heap is what lets the
    // game's ResizeBuffers() release the old back buffers.
    SafeRelease(g_rtvHeap);
    g_rtvCount = 0;
    g_width    = 0;
    g_height   = 0;
}

bool IsReady() {
    return g_ready;
}

// ---------------------------------------------------------------------------
// Per-frame draw.  Runs on the render thread, inside the Present hook, i.e.
// after the game finished recording this frame and before it presents it.
//
// The back buffer arrives in D3D12_RESOURCE_STATE_PRESENT (that is where
// Present() leaves every flip-model buffer), so it is transitioned to
// RENDER_TARGET, drawn onto, and transitioned back before the list is
// submitted.  Forgetting the second barrier makes Present() fail, so both
// transitions are always emitted together.
// ---------------------------------------------------------------------------
bool Render(IDXGISwapChain* pSwapChain) {
    if (!Ensure(pSwapChain)) {
        // false means "not a D3D12 swap chain" — the caller then tries D3D11.
        return g_device != nullptr;
    }

    DXGI_SWAP_CHAIN_DESC desc{};
    if (FAILED(pSwapChain->GetDesc(&desc))) return true;

    // The game can resize without our ResizeBuffers hook running (alt-tab, HDR
    // toggle, a resolution change from the menus).  Re-create the views when
    // the description no longer matches the one they were built from.
    if (desc.BufferDesc.Width  != g_width ||
        desc.BufferDesc.Height != g_height ||
        desc.BufferDesc.Format != g_format) {
        Logf("[*] d3d12: back buffer changed %ux%u fmt=%u -> %ux%u fmt=%u, "
             "rebuilding views",
             g_width, g_height, static_cast<unsigned>(g_format),
             desc.BufferDesc.Width, desc.BufferDesc.Height,
             static_cast<unsigned>(desc.BufferDesc.Format));

        OnResize();
        if (desc.BufferDesc.Format != g_format) {
            // The RTV format is baked into the pipeline state.
            SafeRelease(g_pipelineState);
            g_format      = desc.BufferDesc.Format;
            g_sampleCount = desc.SampleDesc.Count ? desc.SampleDesc.Count : 1;
            if (!CreatePipelineState()) return true;
        }
        if (!CreateRenderTargets(pSwapChain, desc.BufferCount)) return true;
        g_width  = desc.BufferDesc.Width;
        g_height = desc.BufferDesc.Height;
    }

    g_ScreenWidth  = static_cast<int>(g_width);
    g_ScreenHeight = static_cast<int>(g_height);

    const LONG boxCount = g_EspBoxCount;
    if (boxCount <= 0) return true;          // nothing to draw, touch no state

    // Which buffer will the next Present hand to the display?
    UINT bufferIndex = 0;
    IDXGISwapChain3* swapChain3 = nullptr;
    if (SUCCEEDED(pSwapChain->QueryInterface(__uuidof(IDXGISwapChain3),
                                           reinterpret_cast<void**>(&swapChain3))) &&
        swapChain3) {
        bufferIndex = swapChain3->GetCurrentBackBufferIndex();
        swapChain3->Release();
    }
    if (bufferIndex >= g_rtvCount) bufferIndex = 0;

    ID3D12Resource* backBuffer = nullptr;
    if (FAILED(pSwapChain->GetBuffer(bufferIndex, __uuidof(ID3D12Resource),
                                     reinterpret_cast<void**>(&backBuffer))) ||
        !backBuffer) {
        if (!g_loggedNotD3D12) {
            g_loggedNotD3D12 = true;
            Logf("[-] d3d12: GetBuffer(%u) failed in Render", bufferIndex);
        }
        return true;
    }
    // The previous frame's list may still be reading the mapped vertex buffer,
    // so the GPU has to finish before it is overwritten.  This is the same
    // fence that makes the command-allocator Reset() below legal.
    WaitForGpu();

    // ---- build the line list (pixels -> NDC, colour -> float4) -------------
    const float invW = 1.0f / static_cast<float>(g_width  ? g_width  : 1);
    const float invH = 1.0f / static_cast<float>(g_height ? g_height : 1);
    const LONG  limit = (boxCount < MAX_ESP_BOXES) ? boxCount : MAX_ESP_BOXES;

    UINT vertexCount = 0;
    for (LONG i = 0; i < limit; ++i) {
        if (vertexCount + 8 > kMaxVertices) break;

        const ESPBox& box = g_EspBoxes[i];
        if (box.right <= box.left || box.bottom <= box.top) continue;

        const float r = static_cast<float>((box.color >> 16) & 0xFF) / 255.0f;
        const float g = static_cast<float>((box.color >>  8) & 0xFF) / 255.0f;
        const float b = static_cast<float>( box.color        & 0xFF) / 255.0f;
        const float a = static_cast<float>((box.color >> 24) & 0xFF) / 255.0f;

        const float x0 = box.left   * 2.0f * invW - 1.0f;
        const float x1 = box.right  * 2.0f * invW - 1.0f;
        const float y0 = 1.0f - box.top    * 2.0f * invH;   // D3D y grows down
        const float y1 = 1.0f - box.bottom * 2.0f * invH;

        // 4 lines => 8 vertices (LINELIST): top, bottom, left, right.
        const float coords[4][4] = {
            { x0, y0, x1, y0 },
            { x0, y1, x1, y1 },
            { x0, y0, x0, y1 },
            { x1, y0, x1, y1 },
        };

        for (int line = 0; line < 4; ++line) {
            OverlayVertex& first  = g_vertexMapped[vertexCount++];
            first.x = coords[line][0]; first.y = coords[line][1];
            first.r = r; first.g = g; first.b = b; first.a = a;

            OverlayVertex& second = g_vertexMapped[vertexCount++];
            second.x = coords[line][2]; second.y = coords[line][3];
            second.r = r; second.g = g; second.b = b; second.a = a;
        }
    }

    if (vertexCount == 0) { backBuffer->Release(); return true; }

    // ---- record and submit ------------------------------------------------
    // WaitForGpu() above already guaranteed the GPU is done with the previous
    // list, so the allocator (and the list) can be reset.
    if (FAILED(g_allocator->Reset()) ||
        FAILED(g_commandList->Reset(g_allocator, g_pipelineState))) {
        backBuffer->Release();
        return true;
    }

    D3D12_RESOURCE_BARRIER barrier =
        TransitionBarrier(backBuffer, D3D12_RESOURCE_STATE_PRESENT,
                          D3D12_RESOURCE_STATE_RENDER_TARGET);
    g_commandList->ResourceBarrier(1, &barrier);

    D3D12_CPU_DESCRIPTOR_HANDLE rtv =
        g_rtvHeap->GetCPUDescriptorHandleForHeapStart();
    rtv.ptr += static_cast<SIZE_T>(bufferIndex) * g_rtvStride;
    g_commandList->OMSetRenderTargets(1, &rtv, FALSE, nullptr);

    const D3D12_VIEWPORT viewport = {
        0.0f, 0.0f, static_cast<float>(g_width), static_cast<float>(g_height),
        0.0f, 1.0f
    };
    const D3D12_RECT scissor = {
        0, 0, static_cast<LONG>(g_width), static_cast<LONG>(g_height)
    };
    g_commandList->RSSetViewports(1, &viewport);
    g_commandList->RSSetScissorRects(1, &scissor);

    const D3D12_VERTEX_BUFFER_VIEW vbv = {
        g_vertexBuffer->GetGPUVirtualAddress(), kVbBytes,
        static_cast<UINT>(sizeof(OverlayVertex))
    };
    g_commandList->SetGraphicsRootSignature(g_rootSignature);
    g_commandList->IASetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_LINELIST);
    g_commandList->IASetVertexBuffers(0, 1, &vbv);
    g_commandList->DrawInstanced(vertexCount, 1, 0, 0);

    barrier = TransitionBarrier(backBuffer, D3D12_RESOURCE_STATE_RENDER_TARGET,
                                D3D12_RESOURCE_STATE_PRESENT);
    g_commandList->ResourceBarrier(1, &barrier);

    if (FAILED(g_commandList->Close())) {
        backBuffer->Release();
        return true;
    }

    ID3D12CommandList* lists[] = { g_commandList };
    g_queue->ExecuteCommandLists(1, lists);

    // One-shot confirmation that geometry really reached the queue.  Without it
    // an "overlay ready" log plus an empty screen is indistinguishable from
    // "no ESP boxes were produced this session".
    if (!g_loggedDraw) {
        g_loggedDraw = true;
        Logf("[+] d3d12: first overlay draw submitted (%u vertices, %lld box(es), "
             "buffer %u/%u)",
             vertexCount, static_cast<long long>(limit), bufferIndex, g_rtvCount);
    }

    // Signal so the next frame knows when the allocator and the mapped vertex
    // buffer are safe to reuse (and so Release() cannot free live memory).
    if (g_fence && SUCCEEDED(g_queue->Signal(g_fence, ++g_fenceValue))) {
        // completion is waited for by WaitForGpu() on the next frame
    } else {
        g_fenceValue = 0;      // no fence: WaitForGpu() becomes a no-op
    }

    // The RTV keeps the resource alive; our reference must go or the game's
    // ResizeBuffers() fails with DXGI_ERROR_INVALID_CALL.
    backBuffer->Release();
    return true;
}



void Release() {
    // The GPU may still be reading the vertex buffer we are about to free.
    WaitForGpu();

    SafeRelease(g_vertexBuffer);
    g_vertexMapped = nullptr;

    SafeRelease(g_pipelineState);
    SafeRelease(g_rootSignature);
    SafeRelease(g_rtvHeap);
    g_rtvCount = 0;

    SafeRelease(g_fence);
    if (g_fenceEvent) { CloseHandle(g_fenceEvent); g_fenceEvent = nullptr; }
    g_fenceValue = 0;

    SafeRelease(g_commandList);
    SafeRelease(g_allocator);
    SafeRelease(g_queue);
    SafeRelease(g_device);

    g_width = g_height = 0;
    g_format = DXGI_FORMAT_UNKNOWN;
    g_sampleCount = 1;
    g_usesOwnQueue = false;
    g_ready = false;
}

} // namespace D3D12Overlay

