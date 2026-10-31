#pragma once

#include <Windows.h>

// ---------------------------------------------------------------------------
//  esp_gdi.hpp -- external-memory ESP rendered with GDI onto the overlay.
//
//  Reads Apex Legends player data from process memory (reusing the Phase 4
//  EntityExtractor) and draws boxes / health bars / distance / snaplines /
//  names onto the existing GDI overlay window.  No D3D dependency.
//
//  Behaviour is driven by the global g_espConfig / g_sharedMenuData that the
//  menu edits, so the Visuals and Colors tabs control what is drawn.
// ---------------------------------------------------------------------------

// Initialise the ESP: locate Apex, open a read handle and scan for the entity
// list / local player pointers.  Returns false if Apex is not running yet.
bool ESP_Initialize();

// Release the process handle and any GDI resources.
void ESP_Shutdown();

// Draw the ESP for the current frame onto the overlay's memory DC.
//   dc - the (double-buffered) memory DC that is blitted to the window
//   cw, ch - overlay client width/height in pixels
void ESP_Render(HDC dc, int cw, int ch);
