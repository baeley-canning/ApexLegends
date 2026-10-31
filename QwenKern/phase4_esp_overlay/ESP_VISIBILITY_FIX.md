# ESP Overlay Visibility Fix - Changes Summary

## Problem
The external ESP overlay was not visible through walls/RT (ray-traced geometry) in Apex Legends. The root cause was that the overlay window was being created incorrectly — it was rendering INTO the game window instead of as an independent topmost layer.

## Root Cause Analysis

### Issue 1: Overlay Window Not Independent
**Before:** `ESPRenderer::Initialize()` created a D3D11 swap chain with `OutputWindow = game_hwnd`. This meant the ESP was rendered directly into the game window, which gets occluded by the game's D3D12 swap chain during ray tracing.

**After:** Created an independent overlay window using `CreateOverlayWindow()` that:
- Uses `WS_EX_TOPMOST` — always on top of all windows including fullscreen games
- Uses `WS_EX_LAYERED` — enables per-pixel alpha / colour-key transparency
- Uses `WS_EX_TRANSPARENT` — allows mouse events to pass through (click-through)
- Uses `WS_EX_TOOLWINDOW` — doesn't appear in taskbar or alt-tab
- Uses `SetLayeredWindowAttributes()` with colour key RGB(255, 0, 254) for transparency

### Issue 2: World-to-Screen Projection Too Simplistic
**Before:** `CalculateScreenPosition()` used raw world coordinates without accounting for camera rotation (yaw/pitch). This caused ESP elements to be drawn in incorrect positions when the camera was not at origin.

**After:** Added `CalculateScreenPositionWithCamera()` that properly projects 3D world positions onto the 2D screen using:
- Camera position as the origin point
- Forward/right/up vectors calculated from yaw/pitch angles
- Proper perspective projection with FOV scaling
- Back-face culling (returns center screen if target is behind camera)

### Issue 3: Screen Dimensions Not Updated on Resize
**Before:** Screen dimensions were captured once at initialization and never updated. If the game window resized, ESP would be drawn in wrong positions.

**After:** `UpdateOverlayPosition()` dynamically tracks the game window position/size and moves/resizes the overlay accordingly.

## Files Modified

### 1. `phase4_esp_overlay/esp_renderer.hpp`
- Added `overlay_window_` member variable (HWND)
- Added `use_overlay_window_` member variable (bool)
- Added `CreateOverlayWindow()` static method declaration
- Added `UpdateOverlayPosition()` method declaration
- Added `CalculateScreenPositionWithCamera()` method declaration

### 2. `phase4_esp_overlay/esp_renderer.cpp`
Added:
- `kOverlayClassName` — Window class name constant
- `OverlayWndProc()` — Window procedure for the overlay (handles transparency)
- `CreateOverlayWindow()` — Creates independent topmost layered window
- `UpdateOverlayPosition()` — Tracks game window position/size

Modified:
- `Initialize()` — Now creates overlay window first, uses it as D3D11 output target
- `Shutdown()` — Now cleans up overlay window before releasing D3D resources
- `CalculateScreenPosition()` — Updated comment to clarify it's a fallback
- Added `CalculateScreenPositionWithCamera()` — Proper W2S with camera angles

## Key Technical Details

### Window Creation Pattern (Apex Legends Compatible)
```cpp
HWND overlay = CreateWindowExW(
    WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW,
    kOverlayClassName,
    L"Apex ESP Overlay",
    WS_POPUP,
    rc.left, rc.top,   // Position matches game window
    width, height,      // Size matches game window
    game_hwnd,          // Owner = game window
    nullptr,
    GetModuleHandleW(nullptr),
    nullptr
);

// Colour-key transparency: RGB(255, 0, 254) becomes transparent
SetLayeredWindowAttributes(overlay, RGB(255, 0, 254), 0, LWA_COLORKEY);
ShowWindow(overlay, SW_SHOWNOACTIVATE);
```

### World-to-Screen Math (Camera-Aware)
```cpp
// Calculate forward vector from yaw/pitch
float cos_yaw = cosf(cam_angles.x);
float sin_yaw = sinf(cam_angles.x);
float cos_pitch = cosf(cam_angles.y);
float sin_pitch = sinf(cam_angles.y);

DirectX::XMFLOAT3 forward{sin_yaw * cos_pitch, sin_pitch, cos_yaw * cos_pitch};

// Calculate right vector (cross product of forward and up)
DirectX::XMFLOAT3 right;
right.x = forward.z;
right.y = 0.0f;
right.z = -forward.x;

// Project onto camera axes
float x = delta.x * right.x + delta.y * right.y + delta.z * right.z;
float y = delta.x * up.x + delta.y * up.y + delta.z * up.z;
float z = delta.x * forward.x + delta.y * forward.y + delta.z * forward.z;

// Check if target is in front of camera
if (z <= 0.1f) return {screen_width / 2, screen_height / 2};

// Calculate screen position
float fov_scale = screen_width / (2.0f * tanf(fov * XM_PI / 180.0f / 2.0f));
float sx = screen_width / 2.0f + x * fov_scale / z;
float sy = screen_height / 2.0f - y * fov_scale / z;
```

## Testing Recommendations
1. Launch Apex Legends (r5apex_dx12.exe)
2. Run the ESP overlay executable
3. Verify ESP boxes appear on enemies through walls
4. Test in both windowed and fullscreen modes
5. Test with ray tracing enabled/disabled
6. Verify mouse clicks pass through transparent areas

## Known Limitations
- The W2S function assumes Apex uses standard DirectX coordinate system (Y-up)
- Entity offsets may need updating for game patches
- D3D12 device creation is optional — falls back to D3D11 only if it fails
