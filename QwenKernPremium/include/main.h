#pragma once
// ============================================================================
// include\main.h - entry-point contract for apexcheat.dll
//
// PHASE 0.1 (2026-10-26): the old "class QwenKernPremium" + "extern g_pCheat"
// that used to live here were DEAD CODE.  Nothing ever included this header and
// nothing instantiated the class, yet it duplicated half of Application's API,
// so the tree had two competing "main objects" and two would-be init paths.
//
// Application (include\application.h, implemented in src\application.cpp) is now
// the single entry object.  This header is its umbrella: a translation unit
// that "wants the cheat" includes one file instead of four.  src\main.cpp
// includes this header, and it is the ONLY include a new entry path needs.
//
// Invariants encoded here (docs\ROADMAP_TO_PREMIUM_PRODUCT.txt, PHASE 0 / GATE 0):
//   * exactly ONE global entry object: Application, published as g_pApplication
//     (declared in include\application.h, defined in src\main.cpp)
//   * DllMain only creates that object and spawns the worker thread; all heavy
//     init (temporary D3D11 device, hook install, memory reader) runs on the
//     worker thread, never under the loader lock
//   * no new global and no new singleton: adding one here needs a reason
// ============================================================================

#include "application.h"        // Application + extern Application* g_pApplication
