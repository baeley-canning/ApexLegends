#pragma once

// ----------------------------------------------------------------------------
// Forwarding header.
//
// This file used to contain a SECOND, conflicting definition of class
// Application (with "std::atomic<bool> m_bRunning" instead of the canonical
// "bool bIsRunning").  Because quoted includes resolve relative to the
// including file first, every src\*.cpp that did #include "application.h"
// picked up THIS file instead of include\application.h, which produced
// "class Application redefined" / "m_bRunning is not a member" errors.
//
// include\application.h is now the single source of truth.  This forwarding
// header keeps existing "application.h" includes inside src\ working.
// ----------------------------------------------------------------------------
#include "../include/application.h"
