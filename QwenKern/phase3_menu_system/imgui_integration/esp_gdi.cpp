// esp_gdi.cpp -- external-memory ESP rendered with GDI onto the overlay.
//
// Reuses the Phase 4 EntityExtractor to read Apex Legends player data from
// process memory and draws boxes / health bars / distance / snaplines / names
// onto the existing GDI overlay window.  No D3D dependency.

#include <Windows.h>
#include <cmath>
#include <cstdio>
#include <cstdarg>

#include "esp_gdi.hpp"
#include "menu_core.hpp"
#include "menu_renderer.hpp"
#include "../../phase4_esp_overlay/entity_extractor.hpp"

// ---------------------------------------------------------------------------
//  Static state
// ---------------------------------------------------------------------------

static EntityExtractor g_extractor;
static HFONT g_espFont = NULL;
static bool g_ready = false;

// Debug diagnostics -- append a line to esp_debug.log next to the exe so we
// can see where the ESP pipeline bails without needing the screen.
static void EspLog(const char* fmt, ...)
{
    FILE* f = NULL;
    if (fopen_s(&f, "esp_debug.log", "a") != 0 || !f) return;
    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

// World-to-screen constants (Apex external convention).
static const float EYE_HEIGHT   = 60.0f;   // camera height above feet origin
static const float PLAYER_HEIGHT = 72.0f;  // full player model height
static const float PI = 3.14159265358979323846f;

// ---------------------------------------------------------------------------
//  GDI drawing helpers (double-buffered memory DC)
// ---------------------------------------------------------------------------

static void FillC(HDC dc, int x, int y, int w, int h, COLORREF color)
{
    HBRUSH br = CreateSolidBrush(color);
    HGDIOBJ old = SelectObject(dc, br);
    RECT r = { x, y, x + w, y + h };
    FillRect(dc, &r, br);
    SelectObject(dc, old);
    DeleteObject(br);
}

static void FrameC(HDC dc, int x, int y, int w, int h, int thick, COLORREF color)
{
    HPEN pen = CreatePen(PS_SOLID, thick, color);
    HGDIOBJ oldPen = SelectObject(dc, pen);
    HGDIOBJ oldBr = SelectObject(dc, GetStockObject(NULL_BRUSH));
    Rectangle(dc, x, y, x + w, y + h);
    SelectObject(dc, oldBr);
    SelectObject(dc, oldPen);
    DeleteObject(pen);
}

static void LineC(HDC dc, int x1, int y1, int x2, int y2, int thick, COLORREF color)
{
    HPEN pen = CreatePen(PS_SOLID, thick, color);
    HGDIOBJ oldPen = SelectObject(dc, pen);
    MoveToEx(dc, x1, y1, NULL);
    LineTo(dc, x2, y2);
    SelectObject(dc, oldPen);
    DeleteObject(pen);
}

static void TextC(HDC dc, int x, int y, COLORREF color, const char* text)
{
    SetTextColor(dc, color);
    SetBkMode(dc, TRANSPARENT);
    TextOutA(dc, x, y, text, (int)strlen(text));
}

// ---------------------------------------------------------------------------
//  World-to-screen projection (Apex external convention)
//
//  Transforms a world position into overlay screen coordinates using the local
//  player's camera (eye position + view angles + FOV).  Returns false if the
//  target is behind the camera.
// ---------------------------------------------------------------------------

static bool WorldToScreen(const DirectX::XMFLOAT3& world,
                          const DirectX::XMFLOAT3& cam_pos,
                          const DirectX::XMFLOAT3& cam_angles,
                          float fov, int cw, int ch,
                          float& out_x, float& out_y)
{
    // Vector from camera to target.
    float dx = world.x - cam_pos.x;
    float dy = world.y - cam_pos.y;
    float dz = world.z - cam_pos.z;

    // Rotate by -yaw around Z so that +X is forward.
    float cy = cosf(-cam_angles.y * PI / 180.0f);
    float sy = sinf(-cam_angles.y * PI / 180.0f);
    float rx = dx * cy - dy * sy;
    float ry = dx * sy + dy * cy;
    float rz = dz;

    // Rotate by -pitch around Y.
    float cp = cosf(-cam_angles.x * PI / 180.0f);
    float sp = sinf(-cam_angles.x * PI / 180.0f);
    float fx = rx * cp + rz * sp;
    float fy = ry;
    float fz = -rx * sp + rz * cp;

    if (fx < 0.01f) return false;   // behind camera

    float fov_scale = (cw / 2.0f) / tanf((fov * 0.5f) * PI / 180.0f);
    float scx = (cw / 2.0f) + (fy / fx) * fov_scale;
    float scy = (ch / 2.0f) - (fz / fx) * fov_scale;

    out_x = scx;
    out_y = scy;
    return true;
}

// ---------------------------------------------------------------------------
//  ESP lifecycle
// ---------------------------------------------------------------------------

bool ESP_Initialize()
{
    if (g_ready) return true;

    if (!g_extractor.Initialize()) {
        EspLog("[ESP] EntityExtractor::Initialize() FAILED (err=%lu)", GetLastError());
        return false;
    }
    EspLog("[ESP] EntityExtractor::Initialize() OK");

    g_espFont = CreateFontA(-12, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                            CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                            DEFAULT_PITCH, "Tahoma");
    if (!g_espFont) {
        EspLog("[ESP] CreateFontA FAILED");
        return false;
    }

    g_ready = true;
    EspLog("[ESP] ready");
    return true;
}

void ESP_Shutdown()
{
    if (g_espFont) {
        DeleteObject(g_espFont);
        g_espFont = NULL;
    }
    g_ready = false;
}

// ---------------------------------------------------------------------------
//  Per-frame render
// ---------------------------------------------------------------------------

void ESP_Render(HDC dc, int cw, int ch)
{
    if (cw <= 0 || ch <= 0) return;

    // Lazy initialise on first frame (Apex may not be running yet).
    if (!g_ready) {
        if (!ESP_Initialize()) return;
    }

    if (!g_espConfig.Enabled || !g_sharedMenuData.ESPEnabled) {
        EspLog("[ESP] bailed: not enabled (cfg=%d menu=%d)",
               (int)g_espConfig.Enabled, (int)g_sharedMenuData.ESPEnabled);
        return;
    }

    EntityList list = g_extractor.ExtractEntities();
    if (list.players.empty()) {
        EspLog("[ESP] bailed: ExtractEntities() returned 0 players");
        return;
    }

    // Use the local player as the camera.
    const PlayerEntity* cam = nullptr;
    for (const auto& p : list.players) {
        if (p.is_local_player) { cam = &p; break; }
    }
    if (!cam) {
        EspLog("[ESP] bailed: no local player in entity list (%zu total)",
               list.players.size());
        return;
    }

    DirectX::XMFLOAT3 cam_pos = cam->position;
    cam_pos.z += EYE_HEIGHT;
    float fov = (cam->FOV > 1.0f) ? cam->FOV : g_sharedMenuData.FOV;

    HGDIOBJ oldFont = SelectObject(dc, g_espFont);
    int oldBkMode = SetBkMode(dc, TRANSPARENT);

    for (const auto& p : list.players) {
        if (&p == cam) continue;
        if (!p.is_alive) continue;

        // World position at the player's feet.
        DirectX::XMFLOAT3 feet = p.position;

        // Project feet and head (feet + PLAYER_HEIGHT) to screen.
        float fx, fy, hx, hy;
        if (!WorldToScreen(feet, cam_pos, cam->view_angles, fov, cw, ch, fx, fy)) continue;
        if (!WorldToScreen(DirectX::XMFLOAT3{feet.x, feet.y, feet.z + PLAYER_HEIGHT},
                           cam_pos, cam->view_angles, fov, cw, ch, hx, hy)) continue;

        float box_h = fabsf(fy - hy);
        if (box_h < 4.0f) box_h = 4.0f;
        float box_w = box_h * 0.55f;
        if (box_w < 4.0f) box_w = 4.0f;
        int bx = (int)(fx - box_w * 0.5f);
        int by = (int)hy;

        // Colour: teammates vs enemies vs downed.
        COLORREF color = g_espConfig.Colors.EnemyColor;
        if (p.is_teammate) color = g_espConfig.Colors.TeamColor;
        if (p.state == PlayerState::DYING || p.state == PlayerState::DEAD) {
            color = g_espConfig.Colors.DownedColor;
        }

        // Box.
        if (g_espConfig.ShowBoxes) {
            int thick = (int)(g_espConfig.BoxThickness + 0.5f);
            if (thick < 1) thick = 1;
            if (g_espConfig.Style == ESPConfig::Filled) {
                FillC(dc, bx, by, (int)box_w, (int)box_h, color);
            } else if (g_espConfig.Style == ESPConfig::Corner) {
                int c = (int)(box_w * 0.3f);
                LineC(dc, bx, by, bx + c, by, thick, color);
                LineC(dc, bx + (int)box_w - c, by, bx + (int)box_w, by, thick, color);
                LineC(dc, bx, by, bx, by + c, thick, color);
                LineC(dc, bx, by + (int)box_h, bx + c, by + (int)box_h, thick, color);
                LineC(dc, bx + (int)box_w - c, by + (int)box_h, bx + (int)box_w, by + (int)box_h, thick, color);
                LineC(dc, bx + (int)box_w, by, bx + (int)box_w, by + c, thick, color);
                LineC(dc, bx + (int)box_w, by + (int)box_h, bx + (int)box_w, by + (int)box_h - c, thick, color);
            } else {
                FrameC(dc, bx, by, (int)box_w, (int)box_h, thick, color);
            }
        }

        // Health bar (top of box).
        if (g_espConfig.ShowHealthBars && p.max_health > 0) {
            int hw = (int)box_w;
            int hh = 3;
            float ratio = (float)p.health / (float)p.max_health;
            if (ratio < 0.0f) ratio = 0.0f;
            if (ratio > 1.0f) ratio = 1.0f;
            FillC(dc, bx, by - hh - 1, hw, hh, RGB(30, 30, 30));
            FillC(dc, bx, by - hh - 1, (int)(hw * ratio), hh, RGB(0, 220, 0));
        }

        // Distance text below the box.
        if (g_espConfig.ShowDistance) {
            char buf[64];
            snprintf(buf, sizeof(buf), "%.0fm", p.distance_to_player);
            TextC(dc, bx, by + (int)box_h + 2, RGB(255, 255, 255), buf);
        }

        // Name above the box.
        if (!p.player_name.empty()) {
            TextC(dc, bx, by - 14, color, p.player_name.c_str());
        }

        // Snapline from the bottom-centre of the screen to the player.
        if (g_espConfig.ShowSnaplines) {
            LineC(dc, cw / 2, ch, bx + (int)(box_w * 0.5f), by + (int)box_h, 1, color);
        }
    }

    SetBkMode(dc, oldBkMode);
    SelectObject(dc, oldFont);
}
