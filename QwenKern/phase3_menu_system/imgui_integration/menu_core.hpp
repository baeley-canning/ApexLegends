#pragma once

#include <Windows.h>

#include "menu_config.hpp"
#include "menu_renderer.hpp"

// ---------------------------------------------------------------------------
// Global state -- defined once, in main.cpp
// ---------------------------------------------------------------------------
extern bool           g_menuVisible;
extern bool           g_menuActive;
extern SharedMenuData g_sharedMenuData;
extern ESPConfig      g_espConfig;

// ---------------------------------------------------------------------------
// Overlay lifecycle
// ---------------------------------------------------------------------------
bool InitializeOverlay(HINSTANCE hInstance, int nCmdShow);
void ShutdownOverlay();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
HWND GetOverlayWindow();
void RenderMenu();
void ToggleMenu();
void ToggleESP();
