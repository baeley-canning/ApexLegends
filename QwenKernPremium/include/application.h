#pragma once
#include <windows.h>

// Forward declarations
class MemoryReader;
class GameHooks;
class CheatFeatures;
class ConfigManager;

class Application {
private:
    bool bIsRunning;
    
    // Core components
    MemoryReader* memoryReader;
    GameHooks* gameHooks;
    CheatFeatures* cheatFeatures;
    ConfigManager* configManager;
    
public:
    Application();
    ~Application();
    
    // Initialize the application
    bool Initialize();
    
    // Main loop
    void Run();
    
    // Cleanup
    void Shutdown();
    
    // Update game state
    void Update();
    
private:
    // Internal helper functions
    bool CreateCoreComponents();
    void DestroyCoreComponents();
    bool LoadConfiguration();
};

// Global application instance
extern Application* g_pApplication;