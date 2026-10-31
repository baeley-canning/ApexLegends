#pragma once

#include <d3d11.h>
#include <dxgi.h>
#include <imgui.h>
#include <functional>
#include <memory>
#include <string>

// Forward declarations
struct ID3D11Device;
struct ID3D11DeviceContext;
struct IDXGISwapChain;
struct ID3D11RenderTargetView;

namespace d3d {

/**
 * D3D11Renderer — manages a DXGI/Direct3D 11 overlay window with ImGui integration.
 * 
 * Architecture:
 *   - Creates a layered, click-through topmost window (WS_EX_LAYERED | WS_EX_TOPMOST)
 *   - Binds an IDXGISwapChain + ID3D11Device for rendering
 *   - Hooks Present() to intercept frames and render ImGui overlays
 *   - Supports transparent background, custom DPI scaling, and resize callbacks
 */
class D3D11Renderer {
public:
    struct Config {
        int width  = 1920;
        int height = 1080;
        std::string windowName = "ApexOverlay";

        // Overlay appearance
        bool transparentBackground = true;
        uint32_t bgColor           = 0x00000000; // ABGR: fully transparent
        float dpiScale             = 1.0f;

        // Hooking behavior
        bool hookPresent           = true;
        bool renderOnResize        = true;
    };

    D3D11Renderer();
    ~D3D11Renderer();

    // Non-copyable, movable
    D3D11Renderer(D3D11Renderer&& other) noexcept;
    D3D11Renderer& operator=(D3D11Renderer&& other) noexcept;

    /**
     * Initialize the renderer: create window + device + swap chain.
     * Must be called on the UI thread (STA for COM).
     */
    bool initialize(HWND hwndTarget, const Config& config = {});

    /**
     * Shutdown and release all D3D resources.
     */
    void shutdown();

    // ── State queries ───────────────────────────────────────────────
    bool isReady()      const { return m_ready; }
    int  getWidth()     const { return m_config.width; }
    int  getHeight()    const { return m_config.height; }
    HWND getHwnd()      const { return m_hwnd; }
    ID3D11Device*    getDevice()    const { return m_device; }
    ID3D11DeviceContext* getContext() const { return m_context; }
    IDXGISwapChain*  getSwapChain() const { return m_swapChain; }

    // ── ImGui helpers ───────────────────────────────────────────────
    /** Begin a frame: setup render target, clear background. */
    void beginFrame();

    /** End a frame: present via hooked or manual Present(). */
    void endFrame();

    /**
     * Render the overlay manually (used when not hooking Present).
     * Calls beginFrame() → ImGui::Render() → endFrame().
     */
    void renderOverlay();

    // ── Resize ──────────────────────────────────────────────────────
    using ResizeCallback = std::function<void(int w, int h)>;
    void setResizeCallback(ResizeCallback cb) { m_resizeCb = std::move(cb); }

    // ── Background color (ABGR) ────────────────────────────────────
    void setBackgroundColor(uint32_t abgr) { m_config.bgColor = abgr; }
    uint32_t getBackgroundColor() const { return m_config.bgColor; }

private:
    // ── Window creation ───────────────────────────────────────────
    bool createOverlayWindow();
    void destroyOverlayWindow();

    // ── D3D11 device + swap chain ────────────────────────────────
    bool createDeviceAndSwapChain(HWND hwnd);
    void releaseDeviceResources();

    // ── DXGI hooking ─────────────────────────────────────────────
    using PresentFn = HRESULT(__stdcall*)(IDXGISwapChain*, UINT, UINT);
    static HRESULT __stdcall hookedPresent(IDXGISwapChain* pThis, UINT syncInterval, UINT flags);
    HRESULT presentReal(IDXGISwapChain* pThis, UINT syncInterval, UINT flags);

    // ── ImGui setup / teardown ───────────────────────────────────
    bool createImGuiContext();
    void destroyImGuiContext();
    void setupImGuiStyle();

    // ── Render target view management ────────────────────────────
    bool createRenderTargetView();
    void releaseRenderTargetView();

    // ── Members ──────────────────────────────────────────────────
    Config              m_config;
    HWND                m_hwnd       = nullptr;
    ID3D11Device*       m_device     = nullptr;
    ID3D11DeviceContext* m_context   = nullptr;
    IDXGISwapChain*     m_swapChain  = nullptr;
    ID3D11RenderTargetView* m_rtv   = nullptr;

    bool                m_ready      = false;
    bool                m_hooked     = false;

    // Original Present vtable function pointer
    PresentFn           m_originalPresent = nullptr;

    // Hook target: the swap chain's vtable (stored separately so we can restore)
    void**              m_vTable       = nullptr;

    ResizeCallback      m_resizeCb;
};

} // namespace d3d
