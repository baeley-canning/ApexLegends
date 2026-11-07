#include "d3d12_overlay.h"
#include "features.h"
#include "config.h"
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

// PHASE 1 / ov-series (T2): the vertex buffer is split into a UI region
// (TRIANGLELIST: filled quads + 5x7 text + menu) followed by a line region
// (LINELIST: pushed sample lines, then the historical ESP box slots).
// kLineBase is the first vertex of the line region.
const UINT kMaxStageQuads  = 8192u;                // queued quads incl. text
const UINT kMaxStageLines   = 1024u;                // queued line segments
const UINT kMaxUiTris       = kMaxStageQuads * 6u; // 49152 tri vertices
const UINT kMaxUiLineVerts  = kMaxStageLines * 2u;
const UINT kLineBase        = kMaxUiTris;
const UINT kMaxLineVerts    = kMaxVertices + kMaxUiLineVerts;
const UINT kVbBytes         = (kMaxUiTris + kMaxLineVerts) * sizeof(OverlayVertex);

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
ID3D12PipelineState*        g_pipelineStateTri = nullptr;   // TRIANGLELIST (quads/text)
ID3D12DescriptorHeap*       g_rtvHeap       = nullptr;

ID3D12Fence*                g_fence         = nullptr;
HANDLE                      g_fenceEvent    = nullptr;
UINT64                      g_fenceValue    = 0;

ID3D12Resource*             g_vertexBuffer  = nullptr;
ID3D12CommandQueue*         g_queueOverride = nullptr;
OverlayVertex*              g_vertexMapped  = nullptr;

UINT        g_rtvStride      = 0;
UINT        g_rtvCount       = 0;
UINT        g_width          = 0;
UINT        g_height         = 0;
DXGI_FORMAT g_format         = DXGI_FORMAT_UNKNOWN;
UINT        g_sampleCount    = 1;
bool        g_usesOwnQueue   = false;
bool        g_ready          = false;
unsigned    g_queueWaitFrames = 0;
unsigned    g_queueWaited     = 0;

// One-shot latches so a broken state (or a per-frame event) does not spam the
// log at 240 Hz.
bool g_loggedNotD3D12 = false;
bool g_loggedQueue    = false;
bool g_loggedQueueWait = false;
bool g_loggedDraw     = false;
bool g_loggedReason   = false;
bool g_loggedReason2  = false;
bool g_loggedReason3  = false;
bool g_skipDraws      = false;   // OV_NO_DRAWS: bisect the submit path

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

// ============================================================================
// PHASE 1 / ov-series — UI staging + 5x7 font + writers (T2)
// ============================================================================

// One queued quad / line.  PushQuad/PushLine/PushTextA fill these between
// frames; Render() consumes them and resets the counts, so nothing survives a
// frame and the mapped vertex buffer is only ever touched after WaitForGpu().
struct StageQuad {
    float x0, y0, x1, y1;
    DWORD color;
};

struct StageLine {
    float x0, y0, x1, y1;
    DWORD color;
};

StageQuad  g_stageQuads[kMaxStageQuads];
UINT       g_stageQuadCount = 0;
StageLine g_stageLines[kMaxStageLines];
UINT      g_stageLineCount = 0;

// T5: per-frame Present/render counter.  InterlockedIncrement64 in Render(),
// logged through Logf every kPresentLogEvery frames (payload log path).
volatile LONG64 g_presentCount = 0;
const UINT64    kPresentLogEvery = 600;

// ---------------------------------------------------------------------------
// 5x7 bitmap font: 64 glyphs for 0x20..0x5F, five column bytes each, bit k
// of a column byte = row k (top row = bit 0).  Byte constants in code on
// purpose (T2): no font files, no GDI/DirectWrite, no new imports — the
// payload IAT stays {KERNEL32, USER32}.
// ---------------------------------------------------------------------------
const BYTE kFont5x7[64][5] = {
    {0x00,0x00,0x00,0x00,0x00}, {0x00,0x00,0x5F,0x00,0x00}, {0x00,0x07,0x00,0x07,0x00},
    {0x14,0x7F,0x14,0x7F,0x14}, {0x24,0x2A,0x7F,0x2A,0x12}, {0x23,0x13,0x08,0x64,0x62},
    {0x36,0x49,0x55,0x22,0x50}, {0x00,0x05,0x03,0x00,0x00}, {0x00,0x1C,0x22,0x41,0x00},
    {0x00,0x41,0x22,0x1C,0x00}, {0x14,0x08,0x3E,0x08,0x14}, {0x08,0x08,0x3E,0x08,0x08},
    {0x00,0x50,0x30,0x00,0x00}, {0x08,0x08,0x08,0x08,0x08}, {0x00,0x60,0x60,0x00,0x00},
    {0x20,0x10,0x08,0x04,0x02}, {0x3E,0x51,0x49,0x45,0x3E}, {0x00,0x42,0x7F,0x40,0x00},
    {0x42,0x61,0x51,0x49,0x46}, {0x21,0x41,0x45,0x4B,0x31}, {0x18,0x14,0x12,0x7F,0x10},
    {0x27,0x45,0x45,0x45,0x39}, {0x3C,0x4A,0x49,0x49,0x30}, {0x01,0x71,0x09,0x05,0x03},
    {0x36,0x49,0x49,0x49,0x36}, {0x06,0x49,0x49,0x29,0x1E}, {0x00,0x36,0x36,0x00,0x00},
    {0x00,0x56,0x36,0x00,0x00}, {0x00,0x08,0x14,0x22,0x41}, {0x14,0x14,0x14,0x14,0x14},
    {0x41,0x22,0x14,0x08,0x00}, {0x02,0x01,0x51,0x09,0x06}, {0x32,0x49,0x79,0x41,0x3E},
    {0x7E,0x11,0x11,0x11,0x7E}, {0x7F,0x49,0x49,0x49,0x36}, {0x3E,0x41,0x41,0x41,0x22},
    {0x7F,0x41,0x41,0x22,0x1C}, {0x7F,0x49,0x49,0x49,0x41}, {0x7F,0x09,0x09,0x09,0x01},
    {0x3E,0x41,0x49,0x49,0x7A}, {0x7F,0x08,0x08,0x08,0x7F}, {0x00,0x41,0x7F,0x41,0x00},
    {0x20,0x40,0x41,0x3F,0x01}, {0x7F,0x08,0x14,0x22,0x41}, {0x7F,0x40,0x40,0x40,0x40},
    {0x7F,0x02,0x0C,0x02,0x7F}, {0x7F,0x04,0x08,0x10,0x7F}, {0x3E,0x41,0x41,0x41,0x3E},
    {0x7F,0x09,0x09,0x09,0x06}, {0x3E,0x41,0x51,0x21,0x5E}, {0x7F,0x09,0x19,0x29,0x46},
    {0x46,0x49,0x49,0x49,0x31}, {0x01,0x01,0x7F,0x01,0x01}, {0x3F,0x40,0x40,0x40,0x3F},
    {0x1F,0x20,0x40,0x20,0x1F}, {0x3F,0x40,0x38,0x40,0x3F}, {0x63,0x14,0x08,0x14,0x63},
    {0x03,0x07,0x78,0x07,0x03}, {0x61,0x51,0x49,0x45,0x43}, {0x00,0x7F,0x41,0x41,0x00},
    {0x02,0x04,0x08,0x10,0x20}, {0x00,0x41,0x41,0x7F,0x00}, {0x04,0x02,0x01,0x02,0x04},
    {0x40,0x40,0x40,0x40,0x40}
};

// ---------------------------------------------------------------------------
// Vertex writers used during the per-frame build.  Positions arrive in pixels
// and are converted to NDC here (pixels: y grows down; NDC: y grows up).
// Both writers just bump a count; caps drop overflow, but the drop is counted
// and logged once per frame (R3: a truncated UI must not pass silently), so a
// full buffer degrades the UI instead of corrupting the draw.
// ---------------------------------------------------------------------------
struct TriWriter {
    OverlayVertex* base;
    UINT  count;
    UINT  cap;
    UINT  dropped;        // quads that did not fit (0 = everything drawn)
    float invW;
    float invH;

    void Quad(float x0, float y0, float x1, float y1, DWORD color) {
        if (count + 6u > cap) { ++dropped; return; }

        const float r = static_cast<float>((color >> 16) & 0xFF) / 255.0f;
        const float g = static_cast<float>((color >>  8) & 0xFF) / 255.0f;
        const float b = static_cast<float>( color        & 0xFF) / 255.0f;
        const float a = static_cast<float>((color >> 24) & 0xFF) / 255.0f;

        const float nx0 = x0 * 2.0f * invW - 1.0f;
        const float nx1 = x1 * 2.0f * invW - 1.0f;
        const float ny0 = 1.0f - y0 * 2.0f * invH;
        const float ny1 = 1.0f - y1 * 2.0f * invH;

        OverlayVertex* v = base + count;
        // Two triangles: (x0,y0)-(x1,y0)-(x1,y1) and (x0,y0)-(x1,y1)-(x0,y1).
        v[0].x = nx0; v[0].y = ny0;
        v[1].x = nx1; v[1].y = ny0;
        v[2].x = nx1; v[2].y = ny1;
        v[3].x = nx0; v[3].y = ny0;
        v[4].x = nx1; v[4].y = ny1;
        v[5].x = nx0; v[5].y = ny1;
        for (int i = 0; i < 6; ++i) {
            v[i].r = r; v[i].g = g; v[i].b = b; v[i].a = a;
        }
        count += 6u;
    }
};

struct LineWriter {
    OverlayVertex* base;
    UINT  count;
    UINT  cap;
    UINT  dropped;        // line segments that did not fit
    float invW;
    float invH;

    void Line(float x0, float y0, float x1, float y1, DWORD color) {
        if (count + 2u > cap) { ++dropped; return; }

        const float r = static_cast<float>((color >> 16) & 0xFF) / 255.0f;
        const float g = static_cast<float>((color >>  8) & 0xFF) / 255.0f;
        const float b = static_cast<float>( color        & 0xFF) / 255.0f;
        const float a = static_cast<float>((color >> 24) & 0xFF) / 255.0f;

        OverlayVertex* v = base + count;
        v[0].x = x0 * 2.0f * invW - 1.0f; v[0].y = 1.0f - y0 * 2.0f * invH;
        v[1].x = x1 * 2.0f * invW - 1.0f; v[1].y = 1.0f - y1 * 2.0f * invH;
        v[0].r = r; v[0].g = g; v[0].b = b; v[0].a = a;
        v[1].r = r; v[1].g = g; v[1].b = b; v[1].a = a;
        count += 2u;
    }
};

// Emits `text` with the 5x7 font as `scale`-sized pixel quads.  Lowercase maps
// to uppercase; unknown characters render as a space.
void EmitText(TriWriter& w, const char* text, float x, float y, float scale,
              DWORD color) {
    if (!text) return;
    for (const char* p = text; *p; ++p) {
        char c = *p;
        if (c >= 'a' && c <= 'z') {
            c = static_cast<char>(c - 'a' + 'A');
        }
        if (c < ' ' || c > '_') c = ' ';

        const BYTE* glyph = kFont5x7[c - ' '];
        for (int col = 0; col < 5; ++col) {
            const BYTE bits = glyph[col];
            if (!bits) continue;
            for (int row = 0; row < 7; ++row) {
                if (bits & (1u << row)) {
                    w.Quad(x + static_cast<float>(col) * scale,
                           y + static_cast<float>(row) * scale,
                           x + static_cast<float>(col + 1) * scale,
                           y + static_cast<float>(row + 1) * scale, color);
                }
            }
        }
        x += 6.0f * scale;
    }
}

// Pixel advance of a text run (6*scale per character) — for right alignment.
float TextAdvance(const char* text, float scale) {
    if (!text) return 0.0f;
    float width = 0.0f;
    for (const char* p = text; *p; ++p) width += 6.0f * scale;
    return width;
}

// ---------------------------------------------------------------------------
// Menu model (T2/T3): a category strip over two section panels, real widgets
// per row (checkbox / slider / dropdown / button).
//
// ONE table set drives both the renderer and the key handler: a row index is
// resolved by walking the same tables the renderer walks, so the selected row
// can never drift from the row that is drawn or toggled.
//
// Wiring: rows whose id names a CheatFeatures feature read and write the LIVE
// feature state (EnableFeature / the ESP sub-flag setters) and flush the seven
// toggles to apexcheat.ini, exactly like the original seven-row menu did (T4).
// Every other id is a menu value persisted through SharedMenuConfig() under an
// "m_*" key, so a slider or a dropdown survives a restart.
// ---------------------------------------------------------------------------
enum MenuKind {
    MK_CHECK,       // checkbox
    MK_SLIDER,      // track + knob + value text
    MK_CHOICE,      // dropdown pill (cycles through a name table)
    MK_BUTTON,      // button pill carrying an action id
    MK_PILL         // read-only value pill (no action)
};

// Setting ids.  The MS_* ids that have a live feature behind them read/write
// CheatFeatures; the rest are menu values (float for sliders, int for choices,
// bool for the menu-only checkboxes).
enum MenuSetting {
    MS_AIMBOT = 0, MS_HITBOX, MS_AIM_SMOOTH, MS_AIM_FOV,
    MS_TRIGGER, MS_TRIG_HITBOX, MS_TRIG_DELAY,
    MS_RECOIL, MS_RCS_V, MS_RCS_H,
    MS_ESP, MS_ESP_BOXES, MS_ESP_NAMES, MS_ESP_LINES, MS_ESP_DIST,
    MS_GLOW, MS_GLOW_INT, MS_TEAMCHECK,
    MS_RADAR, MS_RADAR_ZOOM, MS_RADAR_ROTATE, MS_SHOW_TEAM,
    MS_STREAM, MS_STREAM_KEY, MS_HIDE_TABBED,
    MS_LOOT, MS_LOOT_DIST, MS_SHOW_TIER, MS_TIER, MS_CATEGORY,
    MS_ONLY_WEAPONS,
    MS_AUTO_RELOAD, MS_TACTICAL_RELOAD, MS_SKYNADES, MS_MEM_WRITES,
    MS_FPS, MS_CFG_SLOT
};

// Button actions.  Menu-only: they log through the payload log path; nothing
// here touches kernel, driver or file state beyond the ini the menu owns.
enum MenuAction {
    MA_LOAD = 500, MA_SAVE, MA_UNLOAD
};

struct MenuItemDef {
    const char* label;
    int         kind;      // MenuKind
    int         id;        // MenuSetting or MenuAction
};

struct MenuPanelDef {
    const char*        title;
    const MenuItemDef* items;
    int                count;
};

struct MenuPageDef {
    const char*         title;      // category strip label
    const MenuPanelDef* panels;
    int                 panelCount;
};

// ---- tables -----------------------------------------------------------------
// Row order inside a page is panel order (left panel first), which is the same
// walk MenuResolveRow() uses for the selection.
const MenuItemDef kAimbotItems[] = {
    { "ENABLED",   MK_CHECK,  MS_AIMBOT     },
    { "HITBOX",    MK_CHOICE, MS_HITBOX     },
    { "SMOOTHING", MK_SLIDER, MS_AIM_SMOOTH },
    { "FOV",       MK_SLIDER, MS_AIM_FOV    }
};
const MenuItemDef kTriggerItems[] = {
    { "ENABLED",  MK_CHECK,  MS_TRIGGER      },
    { "HITBOX",   MK_CHOICE, MS_TRIG_HITBOX  },
    { "DELAY MS", MK_SLIDER, MS_TRIG_DELAY   }
};
const MenuItemDef kRecoilItems[] = {
    { "ENABLED",    MK_CHECK,  MS_RECOIL },
    { "VERTICAL",   MK_SLIDER, MS_RCS_V  },
    { "HORIZONTAL", MK_SLIDER, MS_RCS_H  }
};
const MenuItemDef kEspItems[] = {
    { "ENABLED",      MK_CHECK,  MS_ESP       },
    { "BOXES",        MK_CHECK,  MS_ESP_BOXES },
    { "NAMES",        MK_CHECK,  MS_ESP_NAMES },
    { "LINES",        MK_CHECK,  MS_ESP_LINES },
    { "MAX DISTANCE", MK_SLIDER, MS_ESP_DIST  }
};
const MenuItemDef kGlowItems[] = {
    { "ENABLED",    MK_CHECK,  MS_GLOW      },
    { "INTENSITY",  MK_SLIDER, MS_GLOW_INT  },
    { "TEAM CHECK", MK_CHECK,  MS_TEAMCHECK }
};
const MenuItemDef kRadarItems[] = {
    { "ENABLED",   MK_CHECK,  MS_RADAR        },
    { "ZOOM",      MK_SLIDER, MS_RADAR_ZOOM   },
    { "ROTATE",    MK_CHECK,  MS_RADAR_ROTATE },
    { "SHOW TEAM", MK_CHECK,  MS_SHOW_TEAM    }
};
const MenuItemDef kStreamItems[] = {
    { "ENABLED",          MK_CHECK, MS_STREAM      },
    { "KEYBIND",          MK_PILL,  MS_STREAM_KEY  },
    { "HIDE WHEN TABBED", MK_CHECK, MS_HIDE_TABBED }
};
const MenuItemDef kLootItems[] = {
    { "ENABLED",      MK_CHECK,  MS_LOOT      },
    { "MAX DISTANCE", MK_SLIDER, MS_LOOT_DIST },
    { "SHOW TIER",    MK_CHECK,  MS_SHOW_TIER }
};
const MenuItemDef kFilterItems[] = {
    { "TIER",         MK_CHOICE, MS_TIER         },
    { "CATEGORY",     MK_CHOICE, MS_CATEGORY     },
    { "ONLY WEAPONS", MK_CHECK,  MS_ONLY_WEAPONS }
};
const MenuItemDef kMiscItems[] = {
    { "AUTO RELOAD",         MK_CHECK,  MS_AUTO_RELOAD     },
    { "TACTICAL RELOAD",     MK_CHECK,  MS_TACTICAL_RELOAD },
    { "SKYNADES",            MK_CHECK,  MS_SKYNADES        },
    { "ALLOW MEMORY WRITES", MK_CHECK,  MS_MEM_WRITES      },
    { "MAX OVERLAY FPS",     MK_SLIDER, MS_FPS             }
};
const MenuItemDef kConfigItems[] = {
    { "CURRENT CONFIG", MK_CHOICE, MS_CFG_SLOT },
    { "LOAD CONFIG",    MK_BUTTON, MA_LOAD     },
    { "SAVE CONFIG",    MK_BUTTON, MA_SAVE     },
    { "UNLOAD CHEAT",   MK_BUTTON, MA_UNLOAD   }
};

const MenuPanelDef kAimbotPanels[] = {
    { "AIMBOT",         kAimbotItems,
      static_cast<int>(_countof(kAimbotItems)) },
    { "TRIGGERBOT",     kTriggerItems,
      static_cast<int>(_countof(kTriggerItems)) },
    { "RECOIL CONTROL", kRecoilItems,
      static_cast<int>(_countof(kRecoilItems)) }
};
const MenuPanelDef kVisualsPanels[] = {
    { "ESP",  kEspItems,  static_cast<int>(_countof(kEspItems))  },
    { "GLOW", kGlowItems, static_cast<int>(_countof(kGlowItems)) }
};
const MenuPanelDef kPlayersPanels[] = {
    { "RADAR",        kRadarItems,  static_cast<int>(_countof(kRadarItems))  },
    { "STREAM PROOF", kStreamItems, static_cast<int>(_countof(kStreamItems)) }
};
const MenuPanelDef kLootPanels[] = {
    { "LOOT ESP", kLootItems,   static_cast<int>(_countof(kLootItems))   },
    { "FILTERS",  kFilterItems, static_cast<int>(_countof(kFilterItems)) }
};
const MenuPanelDef kMiscPanels[] = {
    { "MISC",   kMiscItems,   static_cast<int>(_countof(kMiscItems))   },
    { "CONFIG", kConfigItems, static_cast<int>(_countof(kConfigItems)) }
};

const MenuPageDef kMenuPages[] = {
    { "AIMBOT",  kAimbotPanels,  static_cast<int>(_countof(kAimbotPanels))  },
    { "VISUALS", kVisualsPanels, static_cast<int>(_countof(kVisualsPanels)) },
    { "PLAYERS", kPlayersPanels, static_cast<int>(_countof(kPlayersPanels)) },
    { "LOOT",    kLootPanels,    static_cast<int>(_countof(kLootPanels))    },
    { "MISC",    kMiscPanels,    static_cast<int>(_countof(kMiscPanels))    }
};

const int kMenuPageCount = static_cast<int>(_countof(kMenuPages));

// 6x6 category icons (bit (5-col) = column col, index 0 = top row).  Byte
// constants in code, same rule as the font: no files, no new imports.
const BYTE kMenuIcon[5][6] = {
    { 0x0C, 0x0C, 0x33, 0x33, 0x0C, 0x0C },   // AIMBOT   crosshair
    { 0x00, 0x0C, 0x12, 0x12, 0x0C, 0x00 },   // VISUALS  eye
    { 0x0C, 0x0C, 0x1E, 0x3F, 0x3F, 0x3F },   // PLAYERS  person
    { 0x3F, 0x21, 0x21, 0x3F, 0x00, 0x00 },   // LOOT     crate
    { 0x21, 0x3F, 0x00, 0x21, 0x3F, 0x00 }    // MISC     sliders
};

D3D12Overlay::MenuState g_menuState = {
    false, 0,
    static_cast<int>(_countof(kAimbotItems)) + static_cast<int>(_countof(kRecoilItems)),
    0
};

// ---- menu values (persisted; see the file header) ---------------------------
struct MenuValues {
    float aimFov, aimSmooth, rcsV, rcsH, espDist, glowInt, radarZoom,
          lootDist, fps, trigDelay;
    int   hitbox, tier, category, cfgSlot, trigHitbox;
    bool  teamCheck, radarRotate, showTeam, hideTabbed, showTier,
          onlyWeapons, autoReload, tacticalReload, skynades, memWrites;
    bool  radarOn, streamOn, lootOn, triggerOn;

    MenuValues()
        : aimFov(24.0f), aimSmooth(4.0f), rcsV(60.0f), rcsH(40.0f),
          espDist(300.0f), glowInt(70.0f), radarZoom(50.0f), lootDist(250.0f),
          fps(240.0f), trigDelay(60.0f),
          hitbox(0), tier(0), category(0), cfgSlot(0), trigHitbox(0),
          teamCheck(false), radarRotate(true), showTeam(true),
          hideTabbed(false), showTier(true), onlyWeapons(false),
          autoReload(false), tacticalReload(false), skynades(false),
          memWrites(true), triggerOn(false),
          radarOn(false), streamOn(false), lootOn(true) {}
};

MenuValues g_menuValues;
bool       g_menuValuesLoaded = false;

void LoadMenuValues() {
    if (g_menuValuesLoaded) return;
    g_menuValuesLoaded = true;

    ConfigManager* config = SharedMenuConfig();
    MenuValues& v = g_menuValues;
    v.aimFov    = config->GetFloatValue("m_aim_fov",    v.aimFov);
    v.aimSmooth = config->GetFloatValue("m_aim_smooth", v.aimSmooth);
    v.rcsV      = config->GetFloatValue("m_rcs_v",      v.rcsV);
    v.rcsH      = config->GetFloatValue("m_rcs_h",      v.rcsH);
    v.espDist   = config->GetFloatValue("m_esp_dist",   v.espDist);
    v.glowInt   = config->GetFloatValue("m_glow_int",   v.glowInt);
    v.radarZoom = config->GetFloatValue("m_radar_zoom", v.radarZoom);
    v.lootDist  = config->GetFloatValue("m_loot_dist",  v.lootDist);
    v.fps       = config->GetFloatValue("m_max_fps",    v.fps);
    v.hitbox    = config->GetIntValue("m_hitbox",       v.hitbox);
    v.tier      = config->GetIntValue("m_tier",         v.tier);
    v.category  = config->GetIntValue("m_category",     v.category);
    v.cfgSlot   = config->GetIntValue("m_cfg_slot",     v.cfgSlot);
    v.teamCheck      = config->GetBoolValue("m_team_check",     v.teamCheck);
    v.radarOn        = config->GetBoolValue("m_radar",          v.radarOn);
    v.radarRotate    = config->GetBoolValue("m_radar_rotate",   v.radarRotate);
    v.showTeam       = config->GetBoolValue("m_show_team",      v.showTeam);
    v.streamOn       = config->GetBoolValue("m_stream",         v.streamOn);
    v.hideTabbed     = config->GetBoolValue("m_hide_tabbed",    v.hideTabbed);
    v.lootOn         = config->GetBoolValue("m_loot",           v.lootOn);
    v.showTier       = config->GetBoolValue("m_show_tier",      v.showTier);
    v.onlyWeapons    = config->GetBoolValue("m_only_weapons",   v.onlyWeapons);
    v.autoReload     = config->GetBoolValue("m_auto_reload",    v.autoReload);
    v.tacticalReload = config->GetBoolValue("m_tactical_reload", v.tacticalReload);
    v.skynades       = config->GetBoolValue("m_skynades",       v.skynades);
    v.memWrites      = config->GetBoolValue("m_mem_writes",     v.memWrites);

    // The smoothing slider drives the live aimbot value, not a copy of it.
    if (g_pCheatFeatures) {
        v.aimSmooth = g_pCheatFeatures->AimbotSmoothness();
    }
}

MenuValues& Vals() {
    LoadMenuValues();
    return g_menuValues;
}

// ---- slider geometry --------------------------------------------------------
// Every slider is (min, max, step).  Steps are chosen so the value text stays
// short: integers everywhere, one decimal for smoothing.
float SliderMin(int id) {
    switch (id) {
        case MS_AIM_SMOOTH: return 1.0f;
        case MS_AIM_FOV:    return 0.0f;
        case MS_ESP_DIST:   return 25.0f;
        case MS_RADAR_ZOOM: return 10.0f;
        case MS_LOOT_DIST:  return 25.0f;
        case MS_FPS:        return 60.0f;
        case MS_TRIG_DELAY: return 0.0f;
        default:            return 0.0f;   // recoil vertical/horizontal, glow
    }
}

float SliderMax(int id) {
    switch (id) {
        case MS_AIM_SMOOTH: return 10.0f;
        case MS_AIM_FOV:    return 90.0f;
        case MS_ESP_DIST:   return 1000.0f;
        case MS_RADAR_ZOOM: return 200.0f;
        case MS_LOOT_DIST:  return 1000.0f;
        case MS_FPS:        return 400.0f;
        case MS_TRIG_DELAY: return 500.0f;
        default:            return 100.0f;
    }
}

float SliderStep(int id) {
    switch (id) {
        case MS_AIM_SMOOTH: return 0.5f;
        case MS_AIM_FOV:    return 5.0f;
        case MS_ESP_DIST:   return 25.0f;
        case MS_RADAR_ZOOM: return 10.0f;
        case MS_LOOT_DIST:  return 25.0f;
        case MS_FPS:        return 20.0f;
        case MS_TRIG_DELAY: return 5.0f;
        default:            return 5.0f;
    }
}

float* SliderSlot(int id) {
    MenuValues& v = Vals();
    switch (id) {
        case MS_AIM_SMOOTH: return &v.aimSmooth;
        case MS_AIM_FOV:    return &v.aimFov;
        case MS_RCS_V:      return &v.rcsV;
        case MS_RCS_H:      return &v.rcsH;
        case MS_ESP_DIST:   return &v.espDist;
        case MS_GLOW_INT:   return &v.glowInt;
        case MS_RADAR_ZOOM: return &v.radarZoom;
        case MS_LOOT_DIST:  return &v.lootDist;
        case MS_FPS:        return &v.fps;
        case MS_TRIG_DELAY: return &v.trigDelay;
        default:            return nullptr;
    }
}

// Ini key for a persisted menu value; nullptr for rows that are not settings.
const char* SettingKey(int id) {
    switch (id) {
        case MS_AIM_SMOOTH:     return "m_aim_smooth";
        case MS_AIM_FOV:        return "m_aim_fov";
        case MS_RCS_V:          return "m_rcs_v";
        case MS_RCS_H:          return "m_rcs_h";
        case MS_ESP_DIST:       return "m_esp_dist";
        case MS_GLOW_INT:       return "m_glow_int";
        case MS_RADAR_ZOOM:     return "m_radar_zoom";
        case MS_LOOT_DIST:      return "m_loot_dist";
        case MS_FPS:            return "m_max_fps";
        case MS_HITBOX:         return "m_hitbox";
        case MS_TRIGGER:        return "m_trigger";
        case MS_TRIG_HITBOX:    return "m_trig_hitbox";
        case MS_TRIG_DELAY:     return "m_trig_delay";
        case MS_TIER:           return "m_tier";
        case MS_CATEGORY:       return "m_category";
        case MS_CFG_SLOT:       return "m_cfg_slot";
        case MS_TEAMCHECK:      return "m_team_check";
        case MS_RADAR:          return "m_radar";
        case MS_RADAR_ROTATE:   return "m_radar_rotate";
        case MS_SHOW_TEAM:      return "m_show_team";
        case MS_STREAM:         return "m_stream";
        case MS_HIDE_TABBED:    return "m_hide_tabbed";
        case MS_LOOT:           return "m_loot";
        case MS_SHOW_TIER:      return "m_show_tier";
        case MS_ONLY_WEAPONS:   return "m_only_weapons";
        case MS_AUTO_RELOAD:    return "m_auto_reload";
        case MS_TACTICAL_RELOAD: return "m_tactical_reload";
        case MS_SKYNADES:       return "m_skynades";
        case MS_MEM_WRITES:     return "m_mem_writes";
        default:                return nullptr;
    }
}

// Floating-point printer for the value text.  Values are bounded and
// non-negative, so integer/one-decimal split needs no CRT float formatting
// (and no locale).
void FormatValue(char* out, size_t outLen, float value, int decimals) {
    if (!out || outLen == 0) return;
    if (value < 0.0f) value = 0.0f;

    const int scale = (decimals > 0) ? 10 : 1;
    int rounded = static_cast<int>(value * static_cast<float>(scale) + 0.5f);
    if (rounded < 0) rounded = 0;

    const int whole = rounded / scale;
    const int frac  = rounded - whole * scale;

    char buf[12];
    int  n = 0;
    if (whole >= 100) buf[n++] = static_cast<char>('0' + (whole / 100) % 10);
    if (whole >= 10)  buf[n++] = static_cast<char>('0' + (whole / 10) % 10);
    buf[n++] = static_cast<char>('0' + whole % 10);
    if (decimals > 0) {
        buf[n++] = '.';
        buf[n++] = static_cast<char>('0' + frac);
    }
    buf[n] = '\0';

    size_t i = 0;
    while (buf[i] && (i + 1) < outLen) {
        out[i] = buf[i];
        ++i;
    }
    out[i] = '\0';
}

// ---- widget state ----------------------------------------------------------
// True when the id is backed by a live CheatFeatures flag (those rows flush the
// seven ini toggles on change, exactly like the original menu did).
bool IsFeatureSetting(int id) {
    switch (id) {
        case MS_AIMBOT: case MS_ESP: case MS_ESP_BOXES: case MS_ESP_NAMES:
        case MS_ESP_LINES: case MS_GLOW: case MS_RECOIL:
            return true;
        default:
            return false;
    }
}

bool CheckState(int id) {
    CheatFeatures* f = g_pCheatFeatures;
    switch (id) {
        case MS_AIMBOT:    return f && f->IsFeatureEnabled(FEATURE_AIMBOT);
        case MS_ESP:       return f && f->IsFeatureEnabled(FEATURE_ESP);
        case MS_ESP_BOXES: return f && f->IsDrawBoxes();
        case MS_ESP_NAMES: return f && f->IsDrawNames();
        case MS_ESP_LINES: return f && f->IsDrawLines();
        case MS_GLOW:      return f && f->IsFeatureEnabled(FEATURE_GLOW);
        case MS_RECOIL:    return f && f->IsFeatureEnabled(FEATURE_RECOIL);
        default:           break;
    }

    const MenuValues& v = Vals();
    switch (id) {
        case MS_TRIGGER:        return v.triggerOn;
        case MS_TEAMCHECK:      return v.teamCheck;
        case MS_RADAR:          return v.radarOn;
        case MS_RADAR_ROTATE:   return v.radarRotate;
        case MS_SHOW_TEAM:      return v.showTeam;
        case MS_STREAM:         return v.streamOn;
        case MS_HIDE_TABBED:    return v.hideTabbed;
        case MS_LOOT:           return v.lootOn;
        case MS_SHOW_TIER:      return v.showTier;
        case MS_ONLY_WEAPONS:   return v.onlyWeapons;
        case MS_AUTO_RELOAD:    return v.autoReload;
        case MS_TACTICAL_RELOAD: return v.tacticalReload;
        case MS_SKYNADES:       return v.skynades;
        case MS_MEM_WRITES:     return v.memWrites;
        default:                return false;
    }
}

// Flushes the seven feature toggles.  Verdict comes from the write result, not
// from the call having been made (R3): a failed flush is logged as FAILED.
void FlushMenuFeatures() {
    if (!g_pCheatFeatures) return;
    const bool flushed = SharedMenuConfig()->FlushFeatureToggles(
        g_pCheatFeatures->IsFeatureEnabled(FEATURE_AIMBOT),
        g_pCheatFeatures->IsFeatureEnabled(FEATURE_ESP),
        g_pCheatFeatures->IsFeatureEnabled(FEATURE_GLOW),
        g_pCheatFeatures->IsFeatureEnabled(FEATURE_RECOIL),
        g_pCheatFeatures->IsDrawBoxes(),
        g_pCheatFeatures->IsDrawNames(),
        g_pCheatFeatures->IsDrawLines());
    if (!flushed) Logf("[-] menu: ini flush FAILED");
}

void PersistBool(int id, bool value) {
    const char* key = SettingKey(id);
    if (!key) return;
    ConfigManager* config = SharedMenuConfig();
    config->SetBoolValue(key, value);
    if (!config->SaveConfig()) Logf("[-] menu: save %s FAILED", key);
}

// Applies one checkbox row: live feature first, then the owning store, then the
// matching write-back (ini flush for features, m_* key for menu values).
void CheckApply(const MenuItemDef& item, bool on) {
    CheatFeatures* f = g_pCheatFeatures;
    if (f) {
        switch (item.id) {
            case MS_AIMBOT:    f->EnableFeature(FEATURE_AIMBOT, on); break;
            case MS_ESP:       f->EnableFeature(FEATURE_ESP, on);    break;
            case MS_ESP_BOXES: f->SetDrawBoxes(on);                  break;
            case MS_ESP_NAMES: f->SetDrawNames(on);                  break;
            case MS_ESP_LINES: f->SetDrawLines(on);                  break;
            case MS_GLOW:      f->EnableFeature(FEATURE_GLOW, on);   break;
            case MS_RECOIL:    f->EnableFeature(FEATURE_RECOIL, on); break;
            default: break;
        }
    }

    MenuValues& v = Vals();
    switch (item.id) {
        case MS_TRIGGER:         v.triggerOn = on;      break;
        case MS_TEAMCHECK:       v.teamCheck = on;      break;
        case MS_RADAR:           v.radarOn = on;        break;
        case MS_RADAR_ROTATE:    v.radarRotate = on;    break;
        case MS_SHOW_TEAM:       v.showTeam = on;       break;
        case MS_STREAM:          v.streamOn = on;       break;
        case MS_HIDE_TABBED:     v.hideTabbed = on;     break;
        case MS_LOOT:            v.lootOn = on;         break;
        case MS_SHOW_TIER:       v.showTier = on;       break;
        case MS_ONLY_WEAPONS:    v.onlyWeapons = on;    break;
        case MS_AUTO_RELOAD:     v.autoReload = on;     break;
        case MS_TACTICAL_RELOAD: v.tacticalReload = on; break;
        case MS_SKYNADES:        v.skynades = on;       break;
        case MS_MEM_WRITES:      v.memWrites = on;      break;
        default: break;
    }

    if (IsFeatureSetting(item.id)) {
        FlushMenuFeatures();
    } else {
        PersistBool(item.id, on);
    }
    Logf("[*] menu: %s -> %s", item.label, on ? "ON" : "OFF");
}

// ---- choices ---------------------------------------------------------------
const char* const kHitboxNames[]   = { "HEAD", "NECK", "CHEST", "ALL" };
const char* const kTrigHitboxNames[] = { "HEAD", "TORSO", "ARMS", "BODY" };
const char* const kTierNames[]     = { "ALL", "1", "2", "3", "4" };
const char* const kCategoryNames[] = { "ALL", "WEAPON", "AMMO", "HEAL", "ARMOR" };
const char* const kSlotNames[]     = { "DEFAULT", "SLOT 1", "SLOT 2" };

const char* const* ChoiceNames(int id, int* count) {
    if (count) *count = 0;
    switch (id) {
        case MS_HITBOX:
            if (count) *count = static_cast<int>(_countof(kHitboxNames));
            return kHitboxNames;
        case MS_TRIG_HITBOX:
            if (count) *count = static_cast<int>(_countof(kTrigHitboxNames));
            return kTrigHitboxNames;
        case MS_TIER:
            if (count) *count = static_cast<int>(_countof(kTierNames));
            return kTierNames;
        case MS_CATEGORY:
            if (count) *count = static_cast<int>(_countof(kCategoryNames));
            return kCategoryNames;
        case MS_CFG_SLOT:
            if (count) *count = static_cast<int>(_countof(kSlotNames));
            return kSlotNames;
        default:
            return nullptr;
    }
}

int* ChoiceSlot(int id) {
    MenuValues& v = Vals();
    switch (id) {
        case MS_HITBOX:   return &v.hitbox;
        case MS_TRIG_HITBOX: return &v.trigHitbox;
        case MS_TIER:     return &v.tier;
        case MS_CATEGORY: return &v.category;
        case MS_CFG_SLOT: return &v.cfgSlot;
        default:          return nullptr;
    }
}

// Current text of a dropdown row ("ALL" when the id has no name table).
const char* ChoiceText(int id) {
    int count = 0;
    const char* const* names = ChoiceNames(id, &count);
    const int* slot = ChoiceSlot(id);
    if (!names || !slot || *slot < 0 || *slot >= count) return "-";
    return names[*slot];
}

void ChoiceCycle(const MenuItemDef& item, int dir) {
    int count = 0;
    const char* const* names = ChoiceNames(item.id, &count);
    int* slot = ChoiceSlot(item.id);
    if (!names || !slot || count <= 0) return;

    int next = (*slot + dir) % count;
    if (next < 0) next += count;
    *slot = next;

    const char* key = SettingKey(item.id);
    if (key) {
        ConfigManager* config = SharedMenuConfig();
        config->SetIntValue(key, next);
        if (!config->SaveConfig()) Logf("[-] menu: save %s FAILED", key);
    }
    Logf("[*] menu: %s -> %s", item.label, names[next]);
}

// ---- sliders ---------------------------------------------------------------
void SliderNudge(const MenuItemDef& item, int dir) {
    float* slot = SliderSlot(item.id);
    if (!slot) return;

    const float minValue = SliderMin(item.id);
    const float maxValue = SliderMax(item.id);
    const float step     = SliderStep(item.id);

    float value = *slot + static_cast<float>(dir) * step;
    if (value < minValue) value = minValue;
    if (value > maxValue) value = maxValue;
    *slot = value;

    // Smoothing is the live aimbot value, so the widget is not decorative.
    if (item.id == MS_AIM_SMOOTH && g_pCheatFeatures) {
        g_pCheatFeatures->SetAimbotSmoothness(value);
    }

    const char* key = SettingKey(item.id);
    if (key) {
        ConfigManager* config = SharedMenuConfig();
        config->SetFloatValue(key, value);
        if (!config->SaveConfig()) Logf("[-] menu: save %s FAILED", key);
    }

    char text[12];
    FormatValue(text, sizeof(text), value, item.id == MS_AIM_SMOOTH ? 1 : 0);
    Logf("[*] menu: %s = %s", item.label, text);
}

// ---- buttons ---------------------------------------------------------------
// Menu-only actions: LOAD re-reads apexcheat.ini, SAVE writes it, UNLOAD closes
// the menu and asks the injector to eject (the overlay itself only logs here, it
// owns no eject path - see the file header).
void ButtonPress(const MenuItemDef& item) {
    ConfigManager* config = SharedMenuConfig();
    switch (item.id) {
        case MA_LOAD:
            if (config->LoadConfig()) {
                g_menuValuesLoaded = false;   // force a re-read on the next draw
                LoadMenuValues();
                Logf("[*] menu: config reloaded");
            } else {
                Logf("[-] menu: config reload FAILED");
            }
            break;
        case MA_SAVE:
            Logf("[*] menu: config save %s", config->SaveConfig() ? "ok" : "FAILED");
            break;
        case MA_UNLOAD:
            g_menuState.open = false;
            Logf("[*] menu: unload cheat -> menu closed (eject handled outside)");
            break;
        default:
            break;
    }
}

// ---- row resolution and activation -----------------------------------------
// Walks the tables of the ACTIVE page in panel order (left panel first) and
// returns the panel/item a row index refers to.  The renderer uses the same
// walk with its own counter, so draw and input cannot disagree.
bool MenuResolveRow(int row, const MenuPanelDef** panel,
                    const MenuItemDef** item) {
    int tab = g_menuState.tab;
    if (tab < 0) tab = 0;
    if (tab >= kMenuPageCount) tab = kMenuPageCount - 1;
    const MenuPageDef& page = kMenuPages[tab];

    int index = row;
    for (int p = 0; p < page.panelCount; ++p) {
        const MenuPanelDef& current = page.panels[p];
        if (index < current.count) {
            if (panel) *panel = &current;
            if (item)  *item  = &current.items[index];
            return true;
        }
        index -= current.count;
    }
    return false;
}

int MenuRowCount(int tab) {
    if (tab < 0) tab = 0;
    if (tab >= kMenuPageCount) tab = kMenuPageCount - 1;
    const MenuPageDef& page = kMenuPages[tab];
    int total = 0;
    for (int p = 0; p < page.panelCount; ++p) total += page.panels[p].count;
    return total;
}

// Switches category, wraps, and re-clamps the selection: selIndex and rowCount
// always describe the ACTIVE page, which is what the test asserts on.
void MenuSetTab(int tab) {
    static_assert(kMenuPageCount > 0, "menu needs at least one category");
    int next = tab % kMenuPageCount;
    if (next < 0) next += kMenuPageCount;

    g_menuState.tab = next;
    g_menuState.rowCount = MenuRowCount(next);
    if (g_menuState.selIndex >= g_menuState.rowCount) {
        g_menuState.selIndex = g_menuState.rowCount > 0 ? g_menuState.rowCount - 1 : 0;
    }
    if (g_menuState.selIndex < 0) g_menuState.selIndex = 0;
    Logf("[*] menu: category %s (%d rows)", kMenuPages[next].title,
         g_menuState.rowCount);
}

// One activation step on a row.  dir = +1 for RIGHT/ENTER, -1 for LEFT.
void MenuActivateRow(int row, int dir) {
    const MenuPanelDef* panel = nullptr;
    const MenuItemDef*  item  = nullptr;
    if (!MenuResolveRow(row, &panel, &item) || !item) return;
    (void)panel;

    switch (item->kind) {
        case MK_CHECK:
            CheckApply(*item, !CheckState(item->id));
            break;
        case MK_SLIDER:
            SliderNudge(*item, dir >= 0 ? 1 : -1);
            break;
        case MK_CHOICE:
            ChoiceCycle(*item, dir >= 0 ? 1 : -1);
            break;
        case MK_BUTTON:
            if (dir >= 0) ButtonPress(*item);
            break;
        case MK_PILL:
        default:
            break;
    }
}

// True when the row's widget is a slider (the only kind that honours auto
// repeat on LEFT/RIGHT).
bool MenuRowIsSlider(int row) {
    const MenuPanelDef* panel = nullptr;
    const MenuItemDef*  item  = nullptr;
    if (!MenuResolveRow(row, &panel, &item) || !item) return false;
    (void)panel;
    return item->kind == MK_SLIDER;
}


// ---------------------------------------------------------------------------
// Menu rendering (T2): reference-derived surfaces and widgets.
//
// Palette: near-black surfaces with one violet accent and a grey text ramp -
// the same scheme the reference menus use.  Everything is quads (fills) or
// 1px lines (borders/separators); no sprites, no textures, no new imports,
// which is what keeps this drawable from a manually-mapped payload.
// ---------------------------------------------------------------------------
const DWORD kMenuBg         = 0xFF0F0F16;   // window body
const DWORD kMenuStrip      = 0xFF15151D;   // category strip
const DWORD kMenuPanel      = 0xFF171720;   // section panel
const DWORD kMenuBorder     = 0xFF2C2C38;   // hairlines / panel border
const DWORD kMenuBorderHi   = 0xFF3D3D4E;   // border of the focused panel
const DWORD kMenuAccent     = 0xFF8B5CF6;   // violet accent
const DWORD kMenuAccentSoft = 0x338B5CF6;   // selected row / hover fill
const DWORD kMenuTextHi     = 0xFFF3F1F8;   // titles, active category
const DWORD kMenuText       = 0xFFC6C3D2;   // row labels
const DWORD kMenuTextDim    = 0xFF7C7889;   // inactive category, OFF, hint
const DWORD kMenuTrack      = 0xFF24242E;   // slider track / pill body
const DWORD kMenuOn         = 0xFF4ADE80;   // ON

const float kMenuRowH     = 32.0f;    // one row, widget baseline included
const float kMenuTextScale = 2.4f;    // 12x17 px glyphs: legible and OCR-able

// 1px rectangle outline drawn with four quads (the line pipeline is 1px and
// would alias away on high-DPI back buffers).
void EmitFrame(TriWriter& tris, float x0, float y0, float x1, float y1,
               float thickness, DWORD color) {
    tris.Quad(x0, y0, x1, y0 + thickness, color);
    tris.Quad(x0, y1 - thickness, x1, y1, color);
    tris.Quad(x0, y0 + thickness, x0 + thickness, y1 - thickness, color);
    tris.Quad(x1 - thickness, y0 + thickness, x1, y1 - thickness, color);
}

// 6x6 category icon scaled to `px` per icon pixel.
void EmitIcon(TriWriter& tris, const BYTE* rows, float x, float y, float px,
              DWORD color) {
    for (int row = 0; row < 6; ++row) {
        const BYTE bits = rows[row];
        if (!bits) continue;
        for (int col = 0; col < 6; ++col) {
            if (bits & (1u << (5 - col))) {
                tris.Quad(x + static_cast<float>(col) * px,
                          y + static_cast<float>(row) * px,
                          x + static_cast<float>(col + 1) * px,
                          y + static_cast<float>(row + 1) * px, color);
            }
        }
    }
}

// Checkbox: filled accent box with a white core when ON, outline when OFF,
// with the state spelled out to the left (the test OCRs that word).
void EmitCheckbox(TriWriter& tris, float xRight, float y, bool on,
                  bool selected) {
    const float box = 16.0f;
    const float bx0 = xRight - box;
    const float by0 = y + (kMenuRowH - box) * 0.5f;

    if (on) {
        tris.Quad(bx0, by0, bx0 + box, by0 + box, kMenuAccent);
        tris.Quad(bx0 + 5.0f, by0 + 5.0f, bx0 + box - 5.0f, by0 + box - 5.0f,
                  0xFFFFFFFF);
    } else {
        EmitFrame(tris, bx0, by0, bx0 + box, by0 + box, 1.5f,
                  selected ? kMenuBorderHi : kMenuBorder);
    }

    const char* text = on ? "ON" : "OFF";
    const DWORD color = on ? kMenuOn : kMenuTextDim;
    EmitText(tris, text, bx0 - 10.0f - TextAdvance(text, 2.0f),
             y + (kMenuRowH - 14.0f) * 0.5f, 2.0f, color);
}

// Slider: right-aligned value text, then a 120px track with the filled part
// and the knob in accent.  Same geometry the key handler steps.
void EmitSlider(TriWriter& tris, const MenuItemDef& item, float xRight,
                float y, bool selected) {
    const float valueW  = 74.0f;
    const float trackW  = 120.0f;
    const float trackH  = 5.0f;
    const float gap     = 16.0f;

    const float trackX1 = xRight - valueW - gap;
    const float trackX0 = trackX1 - trackW;
    const float trackY  = y + (kMenuRowH - trackH) * 0.5f;

    const float minValue = SliderMin(item.id);
    const float maxValue = SliderMax(item.id);
    const float* slot    = SliderSlot(item.id);
    const float value    = slot ? *slot : minValue;
    const float span     = (maxValue > minValue) ? (maxValue - minValue) : 1.0f;
    float t = (value - minValue) / span;
    if (t < 0.0f) t = 0.0f;
    if (t > 1.0f) t = 1.0f;

    const float knobX = trackX0 + trackW * t;

    tris.Quad(trackX0, trackY, trackX1, trackY + trackH,
              selected ? kMenuBorderHi : kMenuTrack);          // unfilled
    if (knobX > trackX0) {
        tris.Quad(trackX0, trackY, knobX, trackY + trackH, kMenuAccent);
    }
    tris.Quad(knobX - 2.5f, trackY - 6.0f, knobX + 2.5f, trackY + trackH + 6.0f,
              kMenuAccent);                                     // knob

    char text[12];
    FormatValue(text, sizeof(text), value,
                item.id == MS_AIM_SMOOTH ? 1 : 0);
    EmitText(tris, text, xRight - TextAdvance(text, kMenuTextScale),
             y + (kMenuRowH - 17.0f) * 0.5f, kMenuTextScale,
             selected ? kMenuTextHi : kMenuText);
}

// Appends `text` to `out` (bounded).  Used for the "SEL n/m" footer label so
// the draw path needs no formatted-output call.
void AppendText(char* out, size_t outLen, const char* text) {
    if (!out || outLen == 0) return;
    size_t pos = 0;
    while (pos < outLen && out[pos]) ++pos;
    for (const char* c = text; c && *c && (pos + 1) < outLen; ++c) {
        out[pos++] = *c;
    }
    out[pos] = '\0';
}

// Dropdown / button pill: right-aligned, dark body, accent border.  `primary`
// is used by buttons (violet body); dropdowns stay neutral.
void EmitPill(TriWriter& tris, const char* text, float xRight, float y,
              bool selected, bool primary) {
    const float scale = 2.0f;
    const float pillH = 22.0f;
    const float px1   = xRight;
    const float px0   = px1 - TextAdvance(text, scale) - 24.0f;
    const float py0   = y + (kMenuRowH - pillH) * 0.5f;

    DWORD body = kMenuTrack;
    if (primary) {
        body = selected ? 0x808B5CF6 : kMenuAccentSoft;
    } else if (selected) {
        body = kMenuAccentSoft;
    }

    tris.Quad(px0, py0, px1, py0 + pillH, body);
    EmitFrame(tris, px0, py0, px1, py0 + pillH, 1.0f,
              selected ? kMenuAccent : kMenuBorder);
    EmitText(tris, text, px0 + 12.0f, py0 + (pillH - 14.0f) * 0.5f + 1.0f,
             scale, selected ? kMenuTextHi : kMenuText);
}

// One menu row: selection fill, label, right-aligned widget for the kind.
void EmitRow(TriWriter& tris, const MenuItemDef& item, float x, float y,
             float rowW, bool selected) {
    if (selected) {
        tris.Quad(x + 1.0f, y, x + rowW - 1.0f, y + kMenuRowH, kMenuAccentSoft);
        tris.Quad(x + 1.0f, y, x + 4.0f, y + kMenuRowH, kMenuAccent);
    }

    EmitText(tris, item.label, x + 16.0f, y + (kMenuRowH - 17.0f) * 0.5f,
             kMenuTextScale, selected ? kMenuTextHi : kMenuText);

    const float xRight = x + rowW - 16.0f;
    switch (item.kind) {
        case MK_CHECK:
            EmitCheckbox(tris, xRight, y, CheckState(item.id), selected);
            break;
        case MK_SLIDER:
            EmitSlider(tris, item, xRight, y, selected);
            break;
        case MK_CHOICE:
            EmitPill(tris, ChoiceText(item.id), xRight, y, selected, false);
            break;
        case MK_BUTTON:
            EmitPill(tris, "RUN", xRight, y, selected, true);
            break;
        case MK_PILL:
        default: {
            const char* text = (item.id == MS_STREAM_KEY) ? "INSERT" : "-";
            EmitText(tris, text, xRight - TextAdvance(text, 2.0f),
                     y + (kMenuRowH - 14.0f) * 0.5f, 2.0f, kMenuTextDim);
            break;
        }
    }
}

// Section panel: body, border (brighter when the selection lives inside),
// violet title and a hairline under the title.
void EmitPanel(TriWriter& tris, LineWriter& lines, float x, float y, float w,
               float h, const char* title, bool focused) {
    tris.Quad(x, y, x + w, y + h, kMenuPanel);
    EmitFrame(tris, x, y, x + w, y + h, 1.0f,
              focused ? kMenuBorderHi : kMenuBorder);
    EmitText(tris, title, x + 16.0f, y + 11.0f, 2.0f, kMenuAccent);
    lines.Line(x + 16.0f, y + 33.0f, x + w - 16.0f, y + 33.0f, kMenuBorder);
}

// One category in the top strip: icon + name, violet underline when active.
void EmitNavItem(TriWriter& tris, float x, float y, float stripBottom, int tab,
                 bool active) {
    const char* label = kMenuPages[tab].title;
    EmitIcon(tris, kMenuIcon[tab], x, y + 2.0f, 2.0f,
             active ? kMenuAccent : kMenuTextDim);
    EmitText(tris, label, x + 20.0f, y, kMenuTextScale,
             active ? kMenuTextHi : kMenuTextDim);
    if (active) {
        tris.Quad(x + 20.0f, stripBottom - 3.0f,
                  x + 20.0f + TextAdvance(label, kMenuTextScale),
                  stripBottom - 1.0f, kMenuAccent);
    }
}

// Draws the menu: fixed-size window, category strip, two bordered section
// panels, one widget per row.  Geometry is descriptive only - nothing is
// hit-tested; the key handler walks the same tables.
void EmitMenu(TriWriter& tris, LineWriter& lines) {
    const float screenW = (tris.invW > 0.0f) ? (1.0f / tris.invW) : 1280.0f;
    const float screenH = (tris.invH > 0.0f) ? (1.0f / tris.invH) : 720.0f;

    int tab = g_menuState.tab;
    if (tab < 0) tab = 0;
    if (tab >= kMenuPageCount) tab = kMenuPageCount - 1;
    const MenuPageDef& page = kMenuPages[tab];

    // Same window for every category: the tallest panel across all pages sets
    // the panel height, so switching categories never resizes or jumps.
    int windowRows = 1;
    for (int i = 0; i < kMenuPageCount; ++i) {
        for (int p = 0; p < kMenuPages[i].panelCount; ++p) {
            if (kMenuPages[i].panels[p].count > windowRows) {
                windowRows = kMenuPages[i].panels[p].count;
            }
        }
    }

    const float stripH = 54.0f;
    const float padX   = 22.0f;
    const float gutter = 18.0f;
    const float width  = 1180.0f;
    const float panelH = 40.0f + static_cast<float>(windowRows) * kMenuRowH + 14.0f;
    const float height = stripH + 22.0f + panelH + 52.0f;

    const float x0 = (screenW - width) * 0.5f;
    const float y0 = (screenH - height) * 0.5f;
    const float x1 = x0 + width;
    const float y1 = y0 + height;
    const float colW = (width - padX * 2.0f - gutter) * 0.5f;
    const float contentY = y0 + stripH + 22.0f;

    // Window: body, hairline border, accent top edge, category strip.
    tris.Quad(x0, y0, x1, y1, kMenuBg);
    EmitFrame(tris, x0, y0, x1, y1, 1.0f, kMenuBorder);
    tris.Quad(x0, y0, x1, y0 + stripH, kMenuStrip);
    tris.Quad(x0, y0, x1, y0 + 2.0f, kMenuAccent);
    lines.Line(x0, y0 + stripH, x1, y0 + stripH, kMenuBorder);

    // Brand: white wordmark, violet suffix.
    const float brandScale = 3.0f;
    const float brandY     = y0 + (stripH - 21.0f) * 0.5f;
    EmitText(tris, "QWENKERN", x0 + padX, brandY, brandScale, kMenuTextHi);
    EmitText(tris, ".PREMIUM",
             x0 + padX + TextAdvance("QWENKERN", brandScale), brandY,
             brandScale, kMenuAccent);

    // Category strip: icons + names, active one underlined.
    float navX = x0 + 336.0f;
    for (int i = 0; i < kMenuPageCount; ++i) {
        EmitNavItem(tris, navX, y0 + 19.0f, y0 + stripH, i, i == tab);
        navX += TextAdvance(kMenuPages[i].title, kMenuTextScale) + 46.0f;
    }
    EmitText(tris, "V2.0", x1 - padX - TextAdvance("V2.0", 2.0f), y0 + 21.0f,
             2.0f, kMenuTextDim);

    // Which panel owns the selection (its border is the bright one).
    int focusPanel = 0;
    {
        int index = g_menuState.selIndex;
        for (int p = 0; p < page.panelCount; ++p) {
            if (index < page.panels[p].count) {
                focusPanel = p;
                break;
            }
            index -= page.panels[p].count;
        }
    }

    // Panel bodies first, rows second: a row must never draw beneath the
    // neighbouring panel's body.
    for (int p = 0; p < page.panelCount && p < 2; ++p) {
        const float px = x0 + padX + static_cast<float>(p) * (colW + gutter);
        EmitPanel(tris, lines, px, contentY, colW, panelH,
                  page.panels[p].title, p == focusPanel);
    }

    int index = 0;
    for (int p = 0; p < page.panelCount && p < 2; ++p) {
        const MenuPanelDef& panel = page.panels[p];
        const float px = x0 + padX + static_cast<float>(p) * (colW + gutter);
        float ry = contentY + 38.0f;
        for (int i = 0; i < panel.count; ++i, ++index) {
            EmitRow(tris, panel.items[i], px, ry, colW,
                    index == g_menuState.selIndex);
            ry += kMenuRowH;
        }
    }

    // Footer: key legend left, selection counter right.
    lines.Line(x0 + padX, y1 - 40.0f, x1 - padX, y1 - 40.0f, kMenuBorder);
    EmitText(tris, "INS CLOSE   UP/DOWN ROW   LEFT/RIGHT ADJUST   ENTER APPLY",
             x0 + padX, y1 - 29.0f, 2.0f, kMenuTextDim);

    char side[32];
    char number[12];
    char total[12];
    side[0] = '\0';
    FormatValue(number, sizeof(number),
                static_cast<float>(g_menuState.selIndex + 1), 0);
    FormatValue(total, sizeof(total), static_cast<float>(MenuRowCount(tab)), 0);
    AppendText(side, sizeof(side), "SEL ");
    AppendText(side, sizeof(side), number);
    AppendText(side, sizeof(side), "/");
    AppendText(side, sizeof(side), total);
    EmitText(tris, side, x1 - padX - TextAdvance(side, 2.0f), y1 - 29.0f, 2.0f,
             kMenuTextDim);
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

bool CreatePipelineState(D3D12_PRIMITIVE_TOPOLOGY_TYPE topology,
                        ID3D12PipelineState** out) {
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
    desc.PrimitiveTopologyType = topology;
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
        reinterpret_cast<void**>(out));

    vsBlob->Release();
    psBlob->Release();

    if (FAILED(hr)) {
        Logf("[-] d3d12: CreateGraphicsPipelineState(%s) failed hr=0x%08X",
             topology == D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE ? "tri" : "line", hr);
        return false;
    }
    return true;
}

// Both PSOs share the root signature, shaders and blend state; only the
// topology type differs (LINELIST for ESP boxes/lines, TRIANGLELIST for the
// filled quads and the 5x7 font).  Both are rebuilt together whenever the RTV
// format changes.
bool CreatePipelineStates() {
    if (!CreatePipelineState(D3D12_PRIMITIVE_TOPOLOGY_TYPE_LINE, &g_pipelineState)) {
        return false;
    }
    if (!CreatePipelineState(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE, &g_pipelineStateTri)) {
        SafeRelease(g_pipelineState);
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
    // It is also REQUIRED: the layer rejects back-buffer writes on any other
    // queue ("may only be executed on the command queue associated with that
    // buffer", id 907) and removes the device.
    ID3D12CommandQueue* queue = nullptr;
    if (g_queueOverride) {
        g_queue = g_queueOverride;
        g_queue->AddRef();
        g_usesOwnQueue = false;
    } else if (SUCCEEDED(pSwapChain->GetDevice(__uuidof(ID3D12CommandQueue),
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
    if (!CreatePipelineStates()) return false;
    if (!CreateUploadBuffer())  return false;
    if (!CreateRenderTargets(pSwapChain, desc.BufferCount)) return false;

    char envBuf[8] = {};
    g_skipDraws = GetEnvironmentVariableA("OV_NO_DRAWS", envBuf, sizeof(envBuf)) > 0;

    g_ready = true;
    Logf("[+] d3d12: overlay ready (%ux%u fmt=%u samples=%u buffers=%u queue=%s)",
         g_width, g_height, static_cast<unsigned>(g_format), g_sampleCount,
         desc.BufferCount, g_usesOwnQueue ? "private" : "game");
    return true;
}

} // namespace

namespace D3D12Overlay {

bool SetCommandQueue(ID3D12CommandQueue* pQueue) {
    if (!pQueue) return false;
    if (pQueue == g_queueOverride) return true;             // already known

    // Only a DIRECT queue can own a flip-model swap chain; a copy or compute
    // queue would fail the "executed on the associated queue" rule just like a
    // private one.
    if (pQueue->GetDesc().Type != D3D12_COMMAND_LIST_TYPE_DIRECT) return false;

    // A queue of a different device (second adapter in-process) is useless here.
    if (g_device) {
        ID3D12Device* queueDevice = nullptr;
        if (SUCCEEDED(pQueue->GetDevice(__uuidof(ID3D12Device),
                                        reinterpret_cast<void**>(&queueDevice))) &&
            queueDevice) {
            const bool sameDevice = (queueDevice == g_device);
            queueDevice->Release();
            if (!sameDevice) return false;
        }
    }

    pQueue->AddRef();
    if (g_queueOverride) g_queueOverride->Release();
    g_queueOverride = pQueue;

    // Built already on the private queue: swap it in, the next frame uses it.
    if (g_ready && g_usesOwnQueue && g_queue != pQueue) {
        g_queue->AddRef();
        SafeRelease(g_queue);
        g_queue         = pQueue;
        g_usesOwnQueue  = false;
        Logf("[+] d3d12: switched from the private queue to the game's queue %p",
             pQueue);
    }
    return true;
}

void SetQueueWaitFrames(unsigned frames) {
    g_queueWaitFrames = frames;
}

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

bool UsesOwnQueue() {
    return g_usesOwnQueue;
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

    // T5: per-frame Present/render counter (cheap: one interlocked increment
    // and a compare; the log line fires every 600 frames through Logf, i.e.
    // the existing payload log path).
    const unsigned long long frameNo = static_cast<unsigned long long>(
        InterlockedIncrement64(&g_presentCount));
    if (frameNo == 1) {
        Logf("[+] d3d12: present counter started (T5: a line every %llu frames)",
             static_cast<unsigned long long>(kPresentLogEvery));
    } else if ((frameNo % kPresentLogEvery) == 0) {
        Logf("[*] d3d12: present counter = %llu", frameNo);
    }

    // ov-diagnostic: is the device already gone before we touch it, or does our
    // own submission kill it?  One line each, first frame only.
    if (!g_loggedReason) {
        g_loggedReason = true;
        Logf("[i] d3d12: removedReason before 1st render = 0x%08X",
             static_cast<unsigned>(g_device->GetDeviceRemovedReason()));
    }

    // Still on the private queue although a game queue is expected: hold the
    // frame instead of submitting on a queue that will remove the device.  The
    // hold is bounded (SetQueueWaitFrames) so a title without a DIRECT queue
    // still gets drawn eventually.  The present counter above has already run,
    // so a held frame still counts as a frame (in game the game presents it
    // normally, it just has no overlay on it).
    if (g_usesOwnQueue && g_queueWaitFrames) {
        if (g_queueWaited < g_queueWaitFrames) {
            if (g_queueWaited++ == 0) {
                Logf("[i] d3d12: game queue not captured yet - holding frames "
                     "(budget %u)", g_queueWaitFrames);
            }
            return true;
        }
        if (!g_loggedQueueWait) {
            g_loggedQueueWait = true;
            Logf("[*] d3d12: no game queue after %u frames - falling back to the "
                 "private queue", g_queueWaitFrames);
        }
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
            SafeRelease(g_pipelineStateTri);
            g_format      = desc.BufferDesc.Format;
            g_sampleCount = desc.SampleDesc.Count ? desc.SampleDesc.Count : 1;
            if (!CreatePipelineStates()) return true;
        }
        if (!CreateRenderTargets(pSwapChain, desc.BufferCount)) return true;
        g_width  = desc.BufferDesc.Width;
        g_height = desc.BufferDesc.Height;
    }

    g_ScreenWidth  = static_cast<int>(g_width);
    g_ScreenHeight = static_cast<int>(g_height);

    const LONG boxCount = g_EspBoxCount;
    // With the menu / pushed text there is UI to draw even without boxes; only
    // bail out when BOTH the box ring and the UI queues are empty.
    const bool wantUi = g_menuState.open || g_stageQuadCount != 0 ||
                        g_stageLineCount != 0;
    if (boxCount <= 0 && !wantUi) return true;  // nothing to draw, touch no state

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

    // The previous frame's list may still be reading the mapped vertex buffer,
    // so the GPU has to finish before it is overwritten.  This is the same
    // fence that makes the command-allocator Reset() below legal.
    WaitForGpu();

    // ---- build the frame (pixels -> NDC, colour -> float4) -------------------
    // Layout: [tri region: pushed quads/text + menu][line region: pushed
    // lines, then the historical ESP box slots].  Both writers only touch the
    // mapped memory after WaitForGpu() above, and their caps drop overflow
    // instead of corrupting the other region.
    const float invW = 1.0f / static_cast<float>(g_width  ? g_width  : 1);
    const float invH = 1.0f / static_cast<float>(g_height ? g_height : 1);
    const LONG  limit = (boxCount < MAX_ESP_BOXES) ? boxCount : MAX_ESP_BOXES;

    TriWriter tris;
    tris.base  = g_vertexMapped;
    tris.count = 0;
    tris.cap   = kMaxUiTris;
    tris.dropped = 0;
    tris.invW  = invW;
    tris.invH  = invH;

    LineWriter linesW;
    linesW.base  = g_vertexMapped + kLineBase;
    linesW.count = 0;
    linesW.cap   = kMaxLineVerts;
    linesW.dropped = 0;
    linesW.invW  = invW;
    linesW.invH  = invH;

    for (UINT i = 0; i < g_stageQuadCount; ++i) {
        const StageQuad& q = g_stageQuads[i];
        tris.Quad(q.x0, q.y0, q.x1, q.y1, q.color);
    }
    for (UINT i = 0; i < g_stageLineCount; ++i) {
        const StageLine& l = g_stageLines[i];
        linesW.Line(l.x0, l.y0, l.x1, l.y1, l.color);
    }
    if (g_menuState.open) EmitMenu(tris, linesW);

    // A truncated menu would still look "drawn"; make the truncation loud.
    if (tris.dropped || linesW.dropped) {
        Logf("[!] d3d12: vertex buffer full (%u quad(s), %u line(s) dropped) "
             "- raise kMaxStageQuads/kMaxStageLines", tris.dropped,
             linesW.dropped);
    }

    // The queues live exactly one frame.
    g_stageQuadCount = 0;
    g_stageLineCount = 0;

    // ESP boxes: 4 lines => 8 vertices (LINELIST): top, bottom, left, right.
    for (LONG i = 0; i < limit; ++i) {
        const ESPBox& box = g_EspBoxes[i];
        if (box.right <= box.left || box.bottom <= box.top) continue;

        linesW.Line(box.left,  box.top,    box.right, box.top,    box.color);
        linesW.Line(box.left,  box.bottom, box.right, box.bottom, box.color);
        linesW.Line(box.left,  box.top,    box.left,  box.bottom, box.color);
        linesW.Line(box.right, box.top,    box.right, box.bottom, box.color);
    }

    const UINT triCount  = tris.count;
    const UINT lineCount = linesW.count;
    if (triCount == 0 && lineCount == 0) return true;

    // ---- record and submit ------------------------------------------------
    // The frame is recorded into EVERY back buffer, not just
    // GetCurrentBackBufferIndex(): on this box any buffer index other than 0
    // removed the device (DEVICE_REMOVED / removedReason DXGI_ERROR_ACCESS_DENIED
    // - "write to a shared resource with read-only access"), so this way Present
    // gets a fresh image whichever buffer it decides to show.  Costs one extra
    // pass per buffer on a handful of vertices.
    const D3D12_VIEWPORT viewport = {
        0.0f, 0.0f, static_cast<float>(g_width), static_cast<float>(g_height),
        0.0f, 1.0f
    };
    const D3D12_RECT scissor = {
        0, 0, static_cast<LONG>(g_width), static_cast<LONG>(g_height)
    };
    const D3D12_VERTEX_BUFFER_VIEW vbv = {
        g_vertexBuffer->GetGPUVirtualAddress(), kVbBytes,
        static_cast<UINT>(sizeof(OverlayVertex))
    };
    const float kBg[4] = { 0.125f, 0.157f, 0.188f, 1.0f };   // 0x202830

    const UINT passes = 1;                    // current back buffer only
    for (UINT p = 0; p < passes; ++p) {
        const UINT pass = bufferIndex;        // (pass loop kept for the 2-pass case)
        ID3D12Resource* backBuffer = nullptr;
        if (FAILED(pSwapChain->GetBuffer(pass, __uuidof(ID3D12Resource),
                                         reinterpret_cast<void**>(&backBuffer))) ||
            !backBuffer) {
            if (!g_loggedNotD3D12) {
                g_loggedNotD3D12 = true;
                Logf("[-] d3d12: GetBuffer(%u) failed in Render", pass);
            }
            continue;
        }

        // WaitForGpu() above already covered the previous frame; the wait here
        // is what makes the allocator Reset() legal for the second pass.
        if (FAILED(g_allocator->Reset()) ||
            FAILED(g_commandList->Reset(g_allocator, g_pipelineState))) {
            backBuffer->Release();
            break;
        }

        D3D12_RESOURCE_BARRIER barrier =
            TransitionBarrier(backBuffer, D3D12_RESOURCE_STATE_PRESENT,
                              D3D12_RESOURCE_STATE_RENDER_TARGET);
        g_commandList->ResourceBarrier(1, &barrier);

        D3D12_CPU_DESCRIPTOR_HANDLE rtv =
            g_rtvHeap->GetCPUDescriptorHandleForHeapStart();
        rtv.ptr += static_cast<SIZE_T>(pass) * g_rtvStride;
        g_commandList->OMSetRenderTargets(1, &rtv, FALSE, nullptr);
        g_commandList->ClearRenderTargetView(rtv, kBg, 0, nullptr);

        g_commandList->RSSetViewports(1, &viewport);
        g_commandList->RSSetScissorRects(1, &scissor);
        g_commandList->SetGraphicsRootSignature(g_rootSignature);
        g_commandList->IASetVertexBuffers(0, 1, &vbv);

        // Two draw calls, one per topology: the UI triangles at vertex 0, the
        // lines (pushed + ESP boxes) at kLineBase.  Same vertex buffer, same
        // shaders, same blend state — only the PSO and topology differ.
        if (!g_skipDraws && triCount > 0) {
            g_commandList->SetPipelineState(g_pipelineStateTri);
            g_commandList->IASetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
            g_commandList->DrawInstanced(triCount, 1, 0, 0);
        }
        if (!g_skipDraws && lineCount > 0) {
            g_commandList->SetPipelineState(g_pipelineState);
            g_commandList->IASetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_LINELIST);
            g_commandList->DrawInstanced(lineCount, 1, kLineBase, 0);
        }

        barrier = TransitionBarrier(backBuffer, D3D12_RESOURCE_STATE_RENDER_TARGET,
                                    D3D12_RESOURCE_STATE_PRESENT);
        g_commandList->ResourceBarrier(1, &barrier);

        const HRESULT closeHr = g_commandList->Close();
        if (FAILED(closeHr)) {
            Logf("[-] d3d12: command list Close failed hr=0x%08X removed=0x%08X",
                 static_cast<unsigned>(closeHr),
                 static_cast<unsigned>(g_device->GetDeviceRemovedReason()));
            backBuffer->Release();
            break;
        }

        ID3D12CommandList* lists[] = { g_commandList };
        g_queue->ExecuteCommandLists(1, lists);

        if (!g_loggedReason2) {
            g_loggedReason2 = true;
            Logf("[i] d3d12: removedReason right after 1st execute = 0x%08X",
                 static_cast<unsigned>(g_device->GetDeviceRemovedReason()));
        }
        if (!g_loggedDraw) {
            g_loggedDraw = true;
            Logf("[+] d3d12: first overlay draw submitted (%u tri verts, %u line "
                 "verts, %lld box(es), %u buffer pass(es), current %u/%u)",
                 triCount, lineCount, static_cast<long long>(limit), passes,
                 bufferIndex, g_rtvCount);
        }

        // Signal and wait: the next pass resets the same allocator, and the next
        // frame reuses the mapped vertex buffer.
        if (g_fence && SUCCEEDED(g_queue->Signal(g_fence, ++g_fenceValue))) {
            WaitForGpu();
        } else {
            g_fenceValue = 0;      // no fence: WaitForGpu() becomes a no-op
        }

        // The RTV keeps the resource alive; our reference must go or the game's
        // ResizeBuffers() fails with DXGI_ERROR_INVALID_CALL.
        backBuffer->Release();
    }
    return true;
}



void Release() {
    // The GPU may still be reading the vertex buffer we are about to free.
    WaitForGpu();

    SafeRelease(g_vertexBuffer);
    g_vertexMapped = nullptr;

    SafeRelease(g_pipelineState);
    SafeRelease(g_pipelineStateTri);
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
    g_queueWaited     = 0;
    g_loggedQueueWait = false;
}

// ============================================================================
// PHASE 1 / ov-series — public staging API (T2) + menu keys (T3) + the
// present-counter accessor (T5).  The internals above live in the anonymous
// namespace; these are the entry points shared by hooks.cpp (the payload) and
// overlay_test.cpp (the offline test target):
//   * PushQuad/PushLine/PushTextA queue pixels for THIS frame; Render()
//     consumes the queues and resets them, so nothing survives a frame.
//   * MenuHandleKey is the single key router WndProcHook forwards to; it
//     returns true when the key was consumed (the caller returns 1 to
//     swallow it before the game sees it).
// ============================================================================

MenuState* Menu() {
    return &g_menuState;
}

bool MenuIsOpen() {
    return g_menuState.open;
}

int MenuTabCount() {
    return kMenuPageCount;
}

const char* MenuTabName(int tab) {
    if (tab < 0) tab = 0;
    if (tab >= kMenuPageCount) tab = kMenuPageCount - 1;
    return kMenuPages[tab].title;
}

int MenuTabRowCount(int tab) {
    return MenuRowCount(tab);
}

void PushQuad(float x0, float y0, float x1, float y1, DWORD color) {
    if (g_stageQuadCount >= kMaxStageQuads) return;
    StageQuad& q = g_stageQuads[g_stageQuadCount++];
    q.x0 = x0; q.y0 = y0; q.x1 = x1; q.y1 = y1; q.color = color;
}

void PushLine(float x0, float y0, float x1, float y1, DWORD color) {
    if (g_stageLineCount >= kMaxStageLines) return;
    StageLine& l = g_stageLines[g_stageLineCount++];
    l.x0 = x0; l.y0 = y0; l.x1 = x1; l.y1 = y1; l.color = color;
}

void PushTextA(const char* text, float x, float y, float scale, DWORD color) {
    // Same 5x7 glyph walk as EmitText, but the lit pixels are queued as
    // stage quads so the caller owns when they appear (test: every frame).
    if (!text) return;
    for (const char* p = text; *p; ++p) {
        char c = *p;
        if (c >= 'a' && c <= 'z') {
            c = static_cast<char>(c - 'a' + 'A');
        }
        if (c < ' ' || c > '_') c = ' ';

        const BYTE* glyph = kFont5x7[c - ' '];
        for (int col = 0; col < 5; ++col) {
            const BYTE bits = glyph[col];
            if (!bits) continue;
            for (int row = 0; row < 7; ++row) {
                if (bits & (1u << row)) {
                    PushQuad(x + static_cast<float>(col) * scale,
                            y + static_cast<float>(row) * scale,
                            x + static_cast<float>(col + 1) * scale,
                            y + static_cast<float>(row + 1) * scale,
                            color);
                }
            }
        }
        x += 6.0f * scale;
    }
}

float TextWidthA(const char* text, float scale) {
    return TextAdvance(text, scale);
}

bool MenuHandleKey(WPARAM vk, bool repeat) {
    // INSERT opens/closes the menu and is always swallowed (repeats included).
    if (vk == VK_INSERT) {
        if (!repeat) {
            g_menuState.open = !g_menuState.open;
            if (g_menuState.open) {
                // Opening re-derives rowCount from the active category and
                // re-clamps selIndex, so the two always describe the page that
                // is about to be drawn.
                MenuSetTab(g_menuState.tab);
            }
            Logf("[*] menu %s (%s row %d/%d)",
                 g_menuState.open ? "opened" : "closed",
                 MenuTabName(g_menuState.tab), g_menuState.selIndex + 1,
                 g_menuState.rowCount);
        }
        return true;
    }
    if (!g_menuState.open) return false;

    // While the menu is open the navigation keys are consumed here.  Every
    // widget write goes through MenuActivateRow() - the same table walk the
    // renderer uses - so the drawn row and the row that changed cannot drift.
    switch (vk) {
        case VK_UP:
            if (g_menuState.selIndex > 0) --g_menuState.selIndex;
            return true;                          // repeats honour navigation
        case VK_DOWN:
            if (g_menuState.selIndex + 1 < g_menuState.rowCount) {
                ++g_menuState.selIndex;
            }
            return true;
        case VK_TAB:
            if (!repeat) MenuSetTab(g_menuState.tab + 1);   // wrap-around
            return true;
        case VK_RETURN:
            if (!repeat) MenuActivateRow(g_menuState.selIndex, 1);
            return true;
        case VK_RIGHT:
            // Sliders step on every repeat (holding to spin a value up is the
            // point); checks, choices and buttons act once per press.
            if (!repeat || MenuRowIsSlider(g_menuState.selIndex)) {
                MenuActivateRow(g_menuState.selIndex, 1);
            }
            return true;
        case VK_LEFT:
            if (!repeat || MenuRowIsSlider(g_menuState.selIndex)) {
                MenuActivateRow(g_menuState.selIndex, -1);
            }
            return true;
        case VK_BACK:
            if (!repeat) {
                g_menuState.open = false;
                Logf("[*] menu closed (backspace)");
            }
            return true;
        default:
            return false;   // not ours: the key reaches the game
    }
}

unsigned long long PresentCount() {
    return static_cast<unsigned long long>(g_presentCount);
}

} // namespace D3D12Overlay

