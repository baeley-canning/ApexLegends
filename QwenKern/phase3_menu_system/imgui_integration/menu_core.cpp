// ---------------------------------------------------------------------------
//  menu_core.cpp -- self-contained overlay menu implementation
//
//  This replaces the previous DirectX-12 + Dear ImGui stub, which could never
//  build (the ImGui library was not vendored) and would have crashed instantly
//  because the D3D12 device was never created.
//
//  This implementation has NO third-party dependencies.  It links only against
//  user32.lib and gdi32.lib, so it builds with nothing but the Windows SDK.
//
//  The menu is rendered with GDI onto a WS_EX_LAYERED window using a colour
//  key for transparency.  Colour-keyed pixels are also transparent for hit
//  testing, which gives us automatic click-through outside the menu panel.
// ---------------------------------------------------------------------------
#include "menu_core.hpp"
#include "esp_gdi.hpp"

#include <windowsx.h>
#include <cstdio>
#include <vector>

// ---------------------------------------------------------------------------
//  Overlay state
// ---------------------------------------------------------------------------
static HWND      g_hwndOverlay = NULL;
static HFONT     g_fontText    = NULL;
static HFONT     g_fontBold    = NULL;
static HFONT     g_fontSmall   = NULL;

static int       g_activeTab   = 0;
static int       g_hoverTab    = -1;
static int       g_dragWidget  = -1;
static UINT_PTR  g_timerId     = 0;

static ULONGLONG g_frames      = 0;    // frames drawn in the current second
static ULONGLONG g_totalFrames = 0;    // frames drawn since startup
static ULONGLONG g_fpsTick     = 0;
static float     g_fps         = 0.0f;

// Colour used as the transparency key.  Deliberately an unlikely colour so
// nothing drawn on the menu accidentally becomes see-through.
static const COLORREF KEY_COLOR = RGB(255, 0, 254);

static const wchar_t* kTabNames[4]   = { L"Aimbot", L"Visuals", L"Misc", L"Colors" };
static const wchar_t* kBoneNames[4]  = { L"Head", L"Neck", L"Chest", L"Upper Chest" };
static const wchar_t* kStyleNames[3] = { L"Outline", L"Filled", L"Corner" };

enum { PANEL_W = 620, PANEL_H = 520, PAD = 14, ROW_H = 24 };

// ---------------------------------------------------------------------------
//  Widgets -- rebuilt on every paint, consumed by the mouse handlers
// ---------------------------------------------------------------------------
enum WidgetKind { W_Tab, W_Check, W_FloatSlider, W_IntSlider, W_Color, W_Enum };

struct Widget {
    WidgetKind kind;
    RECT       rect;
    void*      value;
    float      minv;
    float      maxv;
    int        index;
};

static std::vector<Widget> g_widgets;

static void AddWidget(WidgetKind kind, const RECT& r, void* value,
                      float minv = 0.0f, float maxv = 0.0f, int index = 0)
{
    Widget w;
    w.kind  = kind;
    w.rect  = r;
    w.value = value;
    w.minv  = minv;
    w.maxv  = maxv;
    w.index = index;
    g_widgets.push_back(w);
}

// ---------------------------------------------------------------------------
//  GDI helpers
// ---------------------------------------------------------------------------
static void FillC(HDC dc, const RECT& r, COLORREF c)
{
    HBRUSH b = CreateSolidBrush(c);
    FillRect(dc, &r, b);
    DeleteObject(b);
}

static void FrameC(HDC dc, const RECT& r, COLORREF c)
{
    HBRUSH b = CreateSolidBrush(c);
    FrameRect(dc, &r, b);
    DeleteObject(b);
}

static void TextC(HDC dc, HFONT f, COLORREF c, const RECT& r,
                  const wchar_t* t, UINT fmt)
{
    HFONT    oldF  = (HFONT)SelectObject(dc, f);
    int      oldBk = SetBkMode(dc, TRANSPARENT);
    COLORREF oldC  = SetTextColor(dc, c);
    RECT     rc    = r;
    DrawTextW(dc, t, -1, &rc, fmt);
    SetTextColor(dc, oldC);
    SetBkMode(dc, oldBk);
    SelectObject(dc, oldF);
}

// Vertical cursor used while laying out a tab.
struct Painter {
    HDC dc;
    int x;
    int y;
    int w;
};

// ---------------------------------------------------------------------------
//  Widget painters
// ---------------------------------------------------------------------------
static void P_Section(Painter& p, const wchar_t* title)
{
    p.y += 6;

    RECT r = { p.x, p.y, p.x + p.w, p.y + 18 };
    TextC(p.dc, g_fontBold, RGB(0, 170, 255), r, title,
          DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    p.y += 20;

    RECT line = { p.x, p.y, p.x + p.w, p.y + 1 };
    FillC(p.dc, line, RGB(48, 48, 58));
    p.y += 6;
}

static void P_Check(Painter& p, const wchar_t* label, bool* v)
{
    RECT box = { p.x, p.y + 4, p.x + 16, p.y + 20 };
    FillC(p.dc, box, *v ? RGB(0, 170, 90) : RGB(52, 52, 62));
    FrameC(p.dc, box, RGB(96, 96, 110));

    if (*v) {
        HPEN pen = CreatePen(PS_SOLID, 2, RGB(255, 255, 255));
        HPEN old = (HPEN)SelectObject(p.dc, pen);
        MoveToEx(p.dc, box.left + 3, box.top + 8, NULL);
        LineTo(p.dc, box.left + 7, box.top + 12);
        LineTo(p.dc, box.left + 13, box.top + 4);
        SelectObject(p.dc, old);
        DeleteObject(pen);
    }

    RECT tr = { p.x + 26, p.y, p.x + p.w, p.y + ROW_H };
    TextC(p.dc, g_fontText, RGB(226, 226, 234), tr, label,
          DT_LEFT | DT_VCENTER | DT_SINGLELINE);

    RECT hit = { p.x, p.y, p.x + p.w, p.y + ROW_H };
    AddWidget(W_Check, hit, v);
    p.y += ROW_H;
}

static void P_FloatSlider(Painter& p, const wchar_t* label, float* v,
                          float mn, float mx, const wchar_t* suffix = L"")
{
    wchar_t vb[64];
    swprintf_s(vb, L"%.1f%s", *v, suffix);

    RECT lr = { p.x, p.y, p.x + p.w / 2, p.y + ROW_H };
    RECT vr = { p.x + p.w / 2, p.y, p.x + p.w, p.y + ROW_H };
    TextC(p.dc, g_fontText, RGB(200, 200, 212), lr, label,
          DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    TextC(p.dc, g_fontText, RGB(0, 180, 255), vr, vb,
          DT_RIGHT | DT_VCENTER | DT_SINGLELINE);

    RECT track = { p.x, p.y + ROW_H - 5, p.x + p.w, p.y + ROW_H - 2 };
    FillC(p.dc, track, RGB(44, 44, 54));

    float t = (*v - mn) / (mx - mn);
    if (t < 0.0f) t = 0.0f;
    if (t > 1.0f) t = 1.0f;

    RECT fillr = track;
    fillr.right = track.left + (LONG)((track.right - track.left) * t);
    FillC(p.dc, fillr, RGB(0, 150, 255));

    RECT hit = { p.x, p.y, p.x + p.w, p.y + ROW_H };
    AddWidget(W_FloatSlider, hit, v, mn, mx);
    p.y += ROW_H + 6;
}

static void P_IntSlider(Painter& p, const wchar_t* label, int* v,
                        int mn, int mx, const wchar_t* suffix = L"")
{
    wchar_t vb[64];
    swprintf_s(vb, L"%d%s", *v, suffix);

    RECT lr = { p.x, p.y, p.x + p.w / 2, p.y + ROW_H };
    RECT vr = { p.x + p.w / 2, p.y, p.x + p.w, p.y + ROW_H };
    TextC(p.dc, g_fontText, RGB(200, 200, 212), lr, label,
          DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    TextC(p.dc, g_fontText, RGB(0, 180, 255), vr, vb,
          DT_RIGHT | DT_VCENTER | DT_SINGLELINE);

    RECT track = { p.x, p.y + ROW_H - 5, p.x + p.w, p.y + ROW_H - 2 };
    FillC(p.dc, track, RGB(44, 44, 54));

    float t = (float)(*v - mn) / (float)(mx - mn);
    if (t < 0.0f) t = 0.0f;
    if (t > 1.0f) t = 1.0f;

    RECT fillr = track;
    fillr.right = track.left + (LONG)((track.right - track.left) * t);
    FillC(p.dc, fillr, RGB(0, 150, 255));

    RECT hit = { p.x, p.y, p.x + p.w, p.y + ROW_H };
    AddWidget(W_IntSlider, hit, v, (float)mn, (float)mx);
    p.y += ROW_H + 6;
}

static void P_Enum(Painter& p, const wchar_t* label, int* v,
                   const wchar_t* const* names, int count)
{
    int idx = *v;
    if (idx < 0 || idx >= count) idx = 0;

    RECT lr = { p.x, p.y, p.x + p.w / 2, p.y + ROW_H };
    TextC(p.dc, g_fontText, RGB(200, 200, 212), lr, label,
          DT_LEFT | DT_VCENTER | DT_SINGLELINE);

    RECT box = { p.x + p.w / 2, p.y + 2, p.x + p.w, p.y + ROW_H - 2 };
    FillC(p.dc, box, RGB(40, 40, 50));
    FrameC(p.dc, box, RGB(80, 80, 96));
    TextC(p.dc, g_fontText, RGB(235, 235, 240), box, names[idx],
          DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    RECT hit = { p.x, p.y, p.x + p.w, p.y + ROW_H };
    AddWidget(W_Enum, hit, v, 0.0f, (float)count);
    p.y += ROW_H + 6;
}

static void P_Color(Painter& p, const wchar_t* label, COLORREF* c)
{
    RECT lr = { p.x, p.y, p.x + p.w / 2, p.y + ROW_H };
    TextC(p.dc, g_fontText, RGB(200, 200, 212), lr, label,
          DT_LEFT | DT_VCENTER | DT_SINGLELINE);

    RECT sw = { p.x + p.w - 96, p.y + 2, p.x + p.w, p.y + ROW_H - 2 };
    FillC(p.dc, sw, *c);
    FrameC(p.dc, sw, RGB(96, 96, 110));

    RECT hit = { p.x, p.y, p.x + p.w, p.y + ROW_H };
    AddWidget(W_Color, hit, c);
    p.y += ROW_H + 6;
}

// ---------------------------------------------------------------------------
//  Tab content
// ---------------------------------------------------------------------------
static void RenderTabContent(Painter& p)
{
    switch (g_activeTab)
    {
    case 0: // Aimbot
        P_Check(p, L"Enable Aimbot  (UNSAFE)", &g_sharedMenuData.AimbotEnabled);
        P_Enum (p, L"Aim Bone", &g_sharedMenuData.AimBone, kBoneNames, 4);

        P_Section(p, L"Aim Settings");
        P_FloatSlider(p, L"FOV Size",         &g_sharedMenuData.FOV,           1.0f,  180.0f);
        P_FloatSlider(p, L"Max Dynamic FOV",  &g_sharedMenuData.MaxDynamicFOV, 10.0f, 400.0f);
        P_FloatSlider(p, L"Smoothing X",      &g_sharedMenuData.SmoothingX,    1.0f,  30.0f);
        P_FloatSlider(p, L"Smoothing Y",      &g_sharedMenuData.SmoothingY,    1.0f,  30.0f);
        P_FloatSlider(p, L"Dead Zone",        &g_sharedMenuData.DeadZone,      0.0f,  25.0f);
        P_FloatSlider(p, L"Max Distance",     &g_sharedMenuData.MaxDistance,   10.0f, 1000.0f, L" m");

        P_Section(p, L"Behaviour");
        P_Check(p, L"Visibility Check",      &g_sharedMenuData.VisibilityCheck);
        P_Check(p, L"Prediction",            &g_sharedMenuData.PredictionEnabled);
        P_Check(p, L"Aim Key: Left Mouse",   &g_sharedMenuData.UseLeftMouse);
        P_Check(p, L"Aim Key: Left Control", &g_sharedMenuData.UseLeftControl);
        break;

    case 1: // Visuals
        P_Check(p, L"Enable ESP", &g_sharedMenuData.ESPEnabled);
        P_Check(p, L"Glow ESP",   &g_sharedMenuData.GlowEnabled);
        P_Check(p, L"Skeletons",  &g_sharedMenuData.SkeletonEnabled);

        P_Section(p, L"Render Options");
        P_Check(p, L"Show Boxes",       &g_espConfig.ShowBoxes);
        P_Check(p, L"Show Glow",        &g_espConfig.ShowGlow);
        P_Check(p, L"Show Skeletons",   &g_espConfig.ShowSkeletons);
        P_Check(p, L"Show Health Bars", &g_espConfig.ShowHealthBars);
        P_Check(p, L"Show Distance",    &g_espConfig.ShowDistance);
        P_Check(p, L"Show Snaplines",   &g_espConfig.ShowSnaplines);

        P_Section(p, L"Visual Intensity");
        P_Enum(p, L"Box Style",
               reinterpret_cast<int*>(&g_espConfig.Style), kStyleNames, 3);
        P_FloatSlider(p, L"Box Thickness",  &g_espConfig.BoxThickness,  1.0f, 5.0f);
        P_FloatSlider(p, L"Glow Intensity", &g_espConfig.GlowIntensity, 1.0f, 5.0f);
        break;

    case 2: // Misc
        P_Section(p, L"Hotkeys");
        {
            RECT h1 = { p.x, p.y, p.x + p.w, p.y + 18 };
            TextC(p.dc, g_fontText, RGB(200, 200, 212), h1,
                  L"INSERT   ->   toggle menu", DT_LEFT | DT_VCENTER | DT_SINGLELINE);
            p.y += 18;

            RECT h2 = { p.x, p.y, p.x + p.w, p.y + 18 };
            TextC(p.dc, g_fontText, RGB(200, 200, 212), h2,
                  L"HOME     ->   toggle ESP", DT_LEFT | DT_VCENTER | DT_SINGLELINE);
            p.y += 24;
        }

        P_Section(p, L"Performance");
        P_Check(p, L"Low Latency Mode", &g_sharedMenuData.LowLatencyMode);
        P_IntSlider(p, L"FPS Target", &g_sharedMenuData.FPSTarget, 30, 360, L" fps");

        P_Section(p, L"Anti-Detection");
        P_Check(p, L"Streamproof",       &g_sharedMenuData.Streamproof);
        P_Check(p, L"Watermark Control", &g_sharedMenuData.WatermarkControl);
        break;

    default: // Colors
        P_Section(p, L"Team");
        P_Color(p, L"Team Color", &g_espConfig.Colors.TeamColor);

        P_Section(p, L"Enemies");
        P_Color(p, L"Enemy Color",  &g_espConfig.Colors.EnemyColor);
        P_Color(p, L"Downed Color", &g_espConfig.Colors.DownedColor);

        P_Section(p, L"Effects");
        P_Color(p, L"Glow Color", &g_espConfig.Colors.GlowColor);
        break;
    }
}

// ---------------------------------------------------------------------------
//  Painting
// ---------------------------------------------------------------------------
static void PaintOverlay(HWND hwnd)
{
    PAINTSTRUCT ps;
    HDC dc = BeginPaint(hwnd, &ps);

    RECT client = { 0, 0, 0, 0 };
    GetClientRect(hwnd, &client);
    const int cw = client.right;
    const int ch = client.bottom;
    if (cw <= 0 || ch <= 0) {
        EndPaint(hwnd, &ps);
        return;
    }

    // Off-screen buffer to avoid flicker
    HDC     mem    = CreateCompatibleDC(dc);
    HBITMAP bmp    = CreateCompatibleBitmap(dc, cw, ch);
    HBITMAP oldBmp = (HBITMAP)SelectObject(mem, bmp);

    // Start with everything transparent (colour key)
    RECT full = { 0, 0, cw, ch };
    FillC(mem, full, KEY_COLOR);

    // Rebuild the hit-test list for the next mouse event
    g_widgets.clear();

    if (g_menuActive && g_menuVisible)
    {
        const int  px = 60, py = 60;
        const RECT panel = { px, py, px + PANEL_W, py + PANEL_H };

        RECT shadow = { panel.left + 6, panel.top + 6,
                        panel.right + 6, panel.bottom + 6 };
        FillC(mem, shadow, RGB(8, 8, 10));
        FillC(mem, panel,  RGB(20, 20, 24));
        FrameC(mem, panel, RGB(72, 72, 84));

        // ---- title bar -------------------------------------------------
        RECT title = { panel.left, panel.top, panel.right, panel.top + 34 };
        FillC(mem, title, RGB(30, 30, 36));
        {
            RECT tl = { title.left + 12, title.top, title.right - 220, title.bottom };
            TextC(mem, g_fontBold, RGB(238, 238, 244), tl,
                  L"Apex Legends   -   QwenKern",
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);

            RECT tr = { title.left + 220, title.top, title.right - 12, title.bottom };
            TextC(mem, g_fontSmall, RGB(150, 150, 164), tr,
                  L"INSERT = menu      HOME = ESP",
                  DT_RIGHT | DT_VCENTER | DT_SINGLELINE);
        }
        RECT accent = { panel.left, title.bottom - 2, panel.right, title.bottom };
        FillC(mem, accent, RGB(0, 150, 255));

        // ---- tab bar ---------------------------------------------------
        const int tabTop = title.bottom;
        const int tabH   = 30;
        const int tabW   = PANEL_W / 4;

        for (int i = 0; i < 4; ++i)
        {
            RECT tr = { panel.left + i * tabW, tabTop,
                        panel.left + (i + 1) * tabW, tabTop + tabH };

            COLORREF bg = (i == g_activeTab) ? RGB(48, 48, 58)
                        : (i == g_hoverTab  ? RGB(38, 38, 46) : RGB(26, 26, 30));
            FillC(mem, tr, bg);

            if (i == g_activeTab) {
                RECT u = { tr.left, tr.bottom - 2, tr.right, tr.bottom };
                FillC(mem, u, RGB(0, 150, 255));
            }

            TextC(mem, g_fontBold,
                  (i == g_activeTab) ? RGB(255, 255, 255) : RGB(168, 168, 180),
                  tr, kTabNames[i], DT_CENTER | DT_VCENTER | DT_SINGLELINE);

            AddWidget(W_Tab, tr, NULL, 0.0f, 0.0f, i);
        }

        // ---- tab body --------------------------------------------------
        Painter p;
        p.dc = mem;
        p.x  = panel.left + PAD;
        p.y  = tabTop + tabH + PAD;
        p.w  = PANEL_W - PAD * 2;
        RenderTabContent(p);

        // ---- footer ----------------------------------------------------
        wchar_t footer[128];
        swprintf_s(footer, L"%.0f FPS    |    frame %llu    |    overlay active",
                   g_fps, (unsigned long long)g_totalFrames);

        RECT fr = { panel.left + PAD, panel.bottom - 26,
                    panel.right - PAD, panel.bottom - 6 };
        TextC(mem, g_fontSmall, RGB(130, 130, 145), fr, footer,
              DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    }

    // External-memory ESP (drawn on top of the menu, independent of it)
    ESP_Render(mem, cw, ch);

    BitBlt(dc, 0, 0, cw, ch, mem, 0, 0, SRCCOPY);

    SelectObject(mem, oldBmp);
    DeleteObject(bmp);
    DeleteDC(mem);
    EndPaint(hwnd, &ps);

    // FPS accounting
    ++g_frames;
    ++g_totalFrames;
    const ULONGLONG now = GetTickCount64();
    if (now - g_fpsTick >= 1000) {
        g_fps     = (float)g_frames * 1000.0f / (float)(now - g_fpsTick);
        g_frames  = 0;
        g_fpsTick = now;
    }
}

// ---------------------------------------------------------------------------
//  Mouse handling
// ---------------------------------------------------------------------------
static void UpdateHover(int mx, int my)
{
    int hover = -1;
    for (size_t i = 0; i < g_widgets.size(); ++i)
    {
        const Widget& w = g_widgets[i];
        if (w.kind != W_Tab) continue;
        if (mx >= w.rect.left && mx < w.rect.right &&
            my >= w.rect.top  && my < w.rect.bottom)
        {
            hover = w.index;
            break;
        }
    }

    if (hover != g_hoverTab) {
        g_hoverTab = hover;
        if (g_hwndOverlay) InvalidateRect(g_hwndOverlay, NULL, FALSE);
    }
}

static void CycleColor(COLORREF* c)
{
    static const COLORREF presets[] = {
        RGB(0, 120, 215), RGB(220, 50, 50),  RGB(255, 165, 0),
        RGB(0, 200, 120), RGB(200, 60, 220), RGB(240, 240, 240)
    };
    const int n = (int)(sizeof(presets) / sizeof(presets[0]));

    int idx = 0;
    for (int i = 0; i < n; ++i)
        if (presets[i] == *c) { idx = i; break; }

    *c = presets[(idx + 1) % n];
}

static void HandleClick(int mx, int my)
{
    g_dragWidget = -1;

    for (size_t i = 0; i < g_widgets.size(); ++i)
    {
        const Widget& w = g_widgets[i];
        if (mx < w.rect.left || mx >= w.rect.right ||
            my < w.rect.top  || my >= w.rect.bottom) continue;

        switch (w.kind)
        {
        case W_Tab:
            g_activeTab = w.index;
            break;

        case W_Check:
            *(bool*)w.value = !*(bool*)w.value;
            break;

        case W_Color:
            CycleColor((COLORREF*)w.value);
            break;

        case W_Enum: {
            int* v = (int*)w.value;
            int  n = (int)w.maxv;
            if (n <= 0) n = 1;
            *v = (*v + 1) % n;
        } break;

        case W_FloatSlider: {
            g_dragWidget = (int)i;
            float t = (float)(mx - w.rect.left) / (float)(w.rect.right - w.rect.left);
            if (t < 0.0f) t = 0.0f;
            if (t > 1.0f) t = 1.0f;
            *(float*)w.value = w.minv + t * (w.maxv - w.minv);
        } break;

        case W_IntSlider: {
            g_dragWidget = (int)i;
            float t = (float)(mx - w.rect.left) / (float)(w.rect.right - w.rect.left);
            if (t < 0.0f) t = 0.0f;
            if (t > 1.0f) t = 1.0f;
            *(int*)w.value = (int)(w.minv + t * (w.maxv - w.minv) + 0.5f);
        } break;
        }
        break;
    }
}

static void HandleDrag(int mx)
{
    if (g_dragWidget < 0 || g_dragWidget >= (int)g_widgets.size()) return;

    const Widget& w = g_widgets[g_dragWidget];
    const int span = w.rect.right - w.rect.left;
    if (span <= 0) return;

    float t = (float)(mx - w.rect.left) / (float)span;
    if (t < 0.0f) t = 0.0f;
    if (t > 1.0f) t = 1.0f;

    if (w.kind == W_FloatSlider)
        *(float*)w.value = w.minv + t * (w.maxv - w.minv);
    else if (w.kind == W_IntSlider)
        *(int*)w.value = (int)(w.minv + t * (w.maxv - w.minv) + 0.5f);

    if (g_hwndOverlay) InvalidateRect(g_hwndOverlay, NULL, FALSE);
}

// ---------------------------------------------------------------------------
//  Attach the overlay to the game window
// ---------------------------------------------------------------------------
static HWND g_apexSearch = NULL;

static BOOL CALLBACK ApexEnumProc(HWND h, LPARAM)
{
    if (!IsWindowVisible(h)) return TRUE;

    wchar_t cls[256] = {};
    GetClassNameW(h, cls, 256);
    if (wcscmp(cls, L"Respawn001") == 0) { g_apexSearch = h; return FALSE; }

    wchar_t title[256] = {};
    GetWindowTextW(h, title, 256);
    if (wcsstr(title, L"Apex Legends")) { g_apexSearch = h; return FALSE; }

    return TRUE;
}

static HWND FindApexWindow()
{
    g_apexSearch = NULL;
    EnumWindows(ApexEnumProc, 0);
    return g_apexSearch;
}

static void UpdateOverlayPlacement()
{
    if (!g_hwndOverlay) return;

    RECT target = { 0, 0, 0, 0 };
    HWND apex = FindApexWindow();

    // Only cover the game when Apex is the actual foreground window (so the
    // full-screen overlay can render ESP). Otherwise -- on the desktop, or
    // alt-tabbed out of Apex -- size the window to just the menu panel so the
    // rest of the screen stays fully clickable (no window there to swallow
    // the mouse).
    if (apex && apex == GetForegroundWindow())
    {
        RECT cr = { 0, 0, 0, 0 };
        GetClientRect(apex, &cr);

        POINT tl = { 0, 0 };
        ClientToScreen(apex, &tl);

        target.left   = tl.x;
        target.top    = tl.y;
        target.right  = tl.x + cr.right;
        target.bottom = tl.y + cr.bottom;
    }
    else
    {
        // No game in the foreground -- cover exactly the menu panel.
        // The panel is drawn at client (60,60)..(60+PANEL_W,60+PANEL_H), so
        // size the window to that area and anchor it at (0,0).
        target.left   = 0;
        target.top    = 0;
        target.right  = 60 + PANEL_W;
        target.bottom = 60 + PANEL_H;
    }

    if (target.right - target.left < 100 || target.bottom - target.top < 100)
        return;

    SetWindowPos(g_hwndOverlay, HWND_TOPMOST,
                 target.left, target.top,
                 target.right - target.left, target.bottom - target.top,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

// ---------------------------------------------------------------------------
//  Window procedure
// ---------------------------------------------------------------------------
static LRESULT CALLBACK OverlayWndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    switch (msg)
    {
    case WM_HOTKEY:
        if (wParam == 1) { ToggleMenu(); return 0; }
        if (wParam == 2) { ToggleESP();  return 0; }
        break;

    case WM_TIMER:
        if (wParam == 1) {
            UpdateOverlayPlacement();
            InvalidateRect(hWnd, NULL, FALSE);
        }
        return 0;

    case WM_SIZE:
        InvalidateRect(hWnd, NULL, FALSE);
        return 0;

    case WM_ERASEBKGND:
        return 1;

    case WM_PAINT:
        PaintOverlay(hWnd);
        return 0;

    case WM_NCHITTEST: {
        // The overlay window covers the whole screen, so by default it would
        // swallow every click. Pass the hit through to the window underneath
        // (HTTRANSPARENT) everywhere except over the visible menu panel.
        if (!(g_menuActive && g_menuVisible))
            return HTTRANSPARENT;

        POINT pt = { GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) };
        ScreenToClient(hWnd, &pt);

        const RECT panel = { 60, 60, 60 + PANEL_W, 60 + PANEL_H };
        if (pt.x >= panel.left && pt.x < panel.right &&
            pt.y >= panel.top  && pt.y < panel.bottom)
            return HTCLIENT;

        return HTTRANSPARENT;
    }

    case WM_MOUSEMOVE: {
        const int mx = GET_X_LPARAM(lParam);
        const int my = GET_Y_LPARAM(lParam);
        UpdateHover(mx, my);
        HandleDrag(mx);
        return 0;
    }

    case WM_LBUTTONDOWN:
        HandleClick(GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam));
        InvalidateRect(hWnd, NULL, FALSE);
        return 0;

    case WM_LBUTTONUP:
        g_dragWidget = -1;
        return 0;

    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }

    return DefWindowProcW(hWnd, msg, wParam, lParam);
}

// ---------------------------------------------------------------------------
//  Lifecycle
// ---------------------------------------------------------------------------
static void UpdateWindowClickThrough();

bool InitializeOverlay(HINSTANCE hInstance, int nCmdShow)
{
    (void)nCmdShow;

    WNDCLASSEXW wc = {};
    wc.cbSize        = sizeof(wc);
    wc.style         = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc   = OverlayWndProc;
    wc.hInstance     = hInstance;
    wc.hCursor       = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = NULL;               // we paint everything ourselves
    wc.lpszClassName = L"ApexCheatMenu";

    if (!RegisterClassExW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return false;

    g_hwndOverlay = CreateWindowExW(
        WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        wc.lpszClassName,
        L"Apex Legends Cheat Menu",
        WS_POPUP,
        0, 0, 800, 600,
        NULL, NULL, hInstance, NULL);

    if (!g_hwndOverlay)
        return false;

    // Colour-key transparency (also gives us click-through on the key pixels)
    SetLayeredWindowAttributes(g_hwndOverlay, KEY_COLOR, 0, LWA_COLORKEY);

    g_fontText  = CreateFontW(-15, 0, 0, 0, FW_NORMAL,   FALSE, FALSE, FALSE,
                              DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                              CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY,
                              DEFAULT_PITCH, L"Segoe UI");
    g_fontBold  = CreateFontW(-16, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
                              DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                              CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY,
                              DEFAULT_PITCH, L"Segoe UI");
    g_fontSmall = CreateFontW(-12, 0, 0, 0, FW_NORMAL,   FALSE, FALSE, FALSE,
                              DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                              CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY,
                              DEFAULT_PITCH, L"Segoe UI");

    // Global hotkeys -- routed to OverlayWndProc as WM_HOTKEY
    RegisterHotKey(g_hwndOverlay, 1, MOD_NOREPEAT, VK_INSERT);
    RegisterHotKey(g_hwndOverlay, 2, MOD_NOREPEAT, VK_HOME);

    UpdateOverlayPlacement();
    ShowWindow(g_hwndOverlay, SW_SHOWNOACTIVATE);
    UpdateWindowClickThrough();

    g_timerId = SetTimer(g_hwndOverlay, 1, 33, NULL); // ~30 Hz
    g_fpsTick = GetTickCount64();

    InvalidateRect(g_hwndOverlay, NULL, FALSE);
    return true;
}

void ShutdownOverlay()
{
    if (g_hwndOverlay)
    {
        if (g_timerId) KillTimer(g_hwndOverlay, g_timerId);
        UnregisterHotKey(g_hwndOverlay, 1);
        UnregisterHotKey(g_hwndOverlay, 2);
        DestroyWindow(g_hwndOverlay);
        g_hwndOverlay = NULL;
        g_timerId = 0;
    }

    if (g_fontText)  { DeleteObject(g_fontText);  g_fontText  = NULL; }
    if (g_fontBold)  { DeleteObject(g_fontBold);  g_fontBold  = NULL; }
    if (g_fontSmall) { DeleteObject(g_fontSmall); g_fontSmall = NULL; }
}

HWND GetOverlayWindow()
{
    return g_hwndOverlay;
}

void RenderMenu()
{
    if (g_hwndOverlay) InvalidateRect(g_hwndOverlay, NULL, FALSE);
}

// When the menu is hidden, the overlay window must not swallow any clicks even
// though it may still be on screen (to keep rendering the ESP).  HTTRANSPARENT
// from WM_NCHITTEST alone is unreliable across threads, so we flip the
// WS_EX_TRANSPARENT style: set when hidden (fully click-through), clear when
// shown (WM_NCHITTEST then makes only the panel interactive).
static void UpdateWindowClickThrough()
{
    if (!g_hwndOverlay) return;
    LONG_PTR style = GetWindowLongPtrW(g_hwndOverlay, GWL_EXSTYLE);
    if (g_menuActive && g_menuVisible)
        style &= ~WS_EX_TRANSPARENT;
    else
        style |= WS_EX_TRANSPARENT;
    SetWindowLongPtrW(g_hwndOverlay, GWL_EXSTYLE, style);
}

void ToggleMenu()
{
    g_menuVisible = !g_menuVisible;
    UpdateWindowClickThrough();
    if (g_hwndOverlay) InvalidateRect(g_hwndOverlay, NULL, FALSE);
}

void ToggleESP()
{
    g_espConfig.Enabled         = !g_espConfig.Enabled;
    g_sharedMenuData.ESPEnabled = g_espConfig.Enabled;
    if (g_hwndOverlay) InvalidateRect(g_hwndOverlay, NULL, FALSE);
}
