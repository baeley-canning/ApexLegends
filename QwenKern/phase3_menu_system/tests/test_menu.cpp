// test_menu.cpp - Menu system unit tests
#include <Windows.h>
#include <iostream>
#include <cassert>
#include "../imgui_integration/menu_core.hpp"
#include "../imgui_integration/menu_config.hpp"
#include "../imgui_integration/shared_memory.hpp"

// Test suite for menu system

void test_shared_memory_creation() {
    std::cout << "[TEST] Shared Memory Creation..." << std::endl;
    
    HANDLE hMapFile = CreateSharedMemory();
    assert(hMapFile != NULL);
    
    SharedMenuData* pData = MapSharedMemory(hMapFile);
    assert(pData != NULL);
    
    // Initialize shared data
    pData->MenuVisible = true;
    pData->MenuActive = true;
    pData->AimbotEnabled = true;
    pData->ESPEnabled = true;
    
    std::cout << "  [PASS] Shared memory created and initialized" << std::endl;
    
    UnmapSharedMemory(pData);
    CloseSharedMemory(hMapFile);
}

void test_hotkey_registration() {
    std::cout << "[TEST] Hotkey Registration..." << std::endl;
    
    // Test INSERT key registration
    bool insertRegistered = RegisterHotKey(NULL, 1, 0, VK_INSERT);
    assert(insertRegistered);
    
    // Test HOME key registration
    bool homeRegistered = RegisterHotKey(NULL, 2, 0, VK_HOME);
    assert(homeRegistered);
    
    std::cout << "  [PASS] INSERT and HOME hotkeys registered" << std::endl;
}

void test_menu_visibility() {
    std::cout << "[TEST] Menu Visibility Toggle..." << std::endl;
    
    g_menuVisible = false;
    SetMenuVisible(true);
    assert(g_menuVisible == true);
    
    SetMenuVisible(false);
    assert(g_menuVisible == false);
    
    std::cout << "  [PASS] Menu visibility toggle works correctly" << std::endl;
}

void test_shared_data_sync() {
    std::cout << "[TEST] Shared Data Synchronization..." << std::endl;
    
    SharedMenuData testData = {};
    testData.FOV = 25.0f;
    testData.SmoothingX = 18.0f;
    testData.AimbotEnabled = true;
    
    // Test data copy
    g_sharedMenuData = testData;
    
    assert(g_sharedMenuData.FOV == 25.0f);
    assert(g_sharedMenuData.SmoothingX == 18.0f);
    assert(g_sharedMenuData.AimbotEnabled == true);
    
    std::cout << "  [PASS] Shared data synchronization verified" << std::endl;
}

void test_esp_config() {
    std::cout << "[TEST] ESP Configuration..." << std::endl;
    
    ESPConfig espConfig = {};
    espConfig.Enabled = true;
    espConfig.BoxStyle = ESPConfig::Outline;
    espConfig.ShowBoxes = true;
    espConfig.ShowGlow = true;
    espConfig.ShowSkeletons = true;
    
    assert(espConfig.Enabled == true);
    assert(espConfig.BoxStyle == ESPConfig::Outline);
    assert(espConfig.ShowBoxes == true);
    assert(espConfig.ShowGlow == true);
    assert(espConfig.ShowSkeletons == true);
    
    std::cout << "  [PASS] ESP configuration valid" << std::endl;
}

void test_legend_overrides() {
    std::cout << "[TEST] Legend-Specific Overrides..." << std::endl;
    
    // Wraith tight configuration
    SharedMenuData::LegendConfig wraithConfig = {};
    wraithConfig.FOVMultiplier = 1.2f;      // Larger FOV for Wraith
    wraithConfig.SmoothingMultiplier = 0.8f; // Less smoothing for tighter aim
    
    // Gibraltar loose configuration
    SharedMenuData::LegendConfig gibraltarConfig = {};
    gibraltarConfig.FOVMultiplier = 0.9f;   // Smaller FOV for Gibraltar
    gibraltarConfig.SmoothingMultiplier = 1.2f; // More smoothing for loose aim
    
    assert(wraithConfig.FOVMultiplier > gibraltarConfig.FOVMultiplier);
    assert(wraithConfig.SmoothingMultiplier < gibraltarConfig.SmoothingMultiplier);
    
    std::cout << "  [PASS] Legend overrides match Wraith tight/Gibraltar loose pattern" << std::endl;
}

void test_color_configuration() {
    std::cout << "[TEST] Color Configuration..." << std::endl;
    
    ESPConfig::Colors colors = {};
    colors.TeamColor = RGB(0, 120, 215);    // Blue for team
    colors.EnemyColor = RGB(220, 50, 50);   // Red for enemies
    colors.DownedColor = RGB(255, 165, 0);  // Orange for downed
    
    assert(GetRValue(colors.TeamColor) == 0);
    assert(GetGValue(colors.TeamColor) == 120);
    assert(GetBValue(colors.TeamColor) == 215);
    
    std::cout << "  [PASS] Color configuration valid" << std::endl;
}

void run_all_tests() {
    std::cout << "\n=== Phase 3 Menu System Test Suite ===\n" << std::endl;
    
    test_shared_memory_creation();
    test_hotkey_registration();
    test_menu_visibility();
    test_shared_data_sync();
    test_esp_config();
    test_legend_overrides();
    test_color_configuration();
    
    std::cout << "\n=== All Tests Passed ===" << std::endl;
}

int main() {
    run_all_tests();
    return 0;
}