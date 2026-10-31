#pragma once

#include <Windows.h>

#include "menu_config.hpp"

// ---------------------------------------------------------------------------
// Shared memory bridge for menu <-> driver communication.
//
// SharedMenuData is defined exactly once, in menu_config.hpp.  (Previously the
// struct was duplicated here with a different member layout, which made the
// menu system impossible to compile.)
// ---------------------------------------------------------------------------

static const wchar_t* SHARED_MEMORY_NAME = L"Global\\ApexCheatMenuData";
static const wchar_t* MENU_EVENT_NAME    = L"Global\\ApexCheatMenuEvent";
static const wchar_t* ESP_EVENT_NAME     = L"Global\\ApexCheatESPEvent";

// Function to create/open shared memory
inline HANDLE CreateSharedMemory()
{
    // Create file mapping for shared data
    HANDLE hMapFile = CreateFileMapping(
        INVALID_HANDLE_VALUE,   // Use paging file
        NULL,                   // Default security
        PAGE_READWRITE,         // Read/write access
        0,                      // Maximum object size (high-order DWORD)
        sizeof(SharedMenuData), // Maximum object size (low-order DWORD)
        SHARED_MEMORY_NAME      // Name of mapping object
    );

    if (!hMapFile || GetLastError() == ERROR_ALREADY_EXISTS)
    {
        // Open existing mapping
        hMapFile = OpenFileMapping(
            FILE_MAP_ALL_ACCESS,
            FALSE,
            SHARED_MEMORY_NAME
        );
    }

    return hMapFile;
}

// Function to map shared memory view
inline SharedMenuData* MapSharedMemory(HANDLE hMapFile)
{
    return (SharedMenuData*)MapViewOfFile(
        hMapFile,            // Handle to mapping object
        FILE_MAP_ALL_ACCESS, // Read/write permission
        0,
        0,
        sizeof(SharedMenuData)
    );
}

// Function to unmap shared memory
inline void UnmapSharedMemory(SharedMenuData* pData)
{
    if (pData)
        UnmapViewOfFile(pData);
}

// Function to close shared memory handle
inline void CloseSharedMemory(HANDLE hMapFile)
{
    if (hMapFile)
        CloseHandle(hMapFile);
}

// Event signaling for menu state changes
inline HANDLE CreateMenuEvent()
{
    return CreateEvent(
        NULL,   // Default security
        FALSE,  // Auto-reset
        FALSE,  // Initial state
        MENU_EVENT_NAME
    );
}

inline void SignalMenuEvent(HANDLE hEvent)
{
    if (hEvent)
        SetEvent(hEvent);
}

// Event signaling for ESP state changes
inline HANDLE CreateESPEvent()
{
    return CreateEvent(
        NULL,   // Default security
        FALSE,  // Auto-reset
        TRUE,   // Initial state (ESP enabled)
        ESP_EVENT_NAME
    );
}

inline void SignalESPEvent(HANDLE hEvent)
{
    if (hEvent)
        SetEvent(hEvent);
}
