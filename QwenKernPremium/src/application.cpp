#include "application.h"     // -> src\application.h -> include\application.h
#include "hooks.h"
#include "memory.h"
#include "config.h"
#include "features.h"
#include "log.h"
#include "offset_validator.h"

// The global instance itself lives in main.cpp (declared extern in the header).

namespace {

// Run every documented offset probe and print a readable report.  A failing
// probe disables nothing by itself (each feature degrades on its own), but the
// log tells the operator immediately whether this build matches this patch.
void ReportOffsetValidation(MemoryReader& reader) {
    // Accepts r5apex_dx12.exe as well as r5apex.exe; the documented RVAs apply
    // to whichever game image is loaded.
    const DWORD64 moduleBase = reader.GetGameModuleBase();
    if (moduleBase == 0) {
        Logf("[!] game module base not found (r5apex_dx12.exe / r5apex.exe), "
             "skipping validation");
        return;
    }
    Logf("[*] game module base = 0x%llX",
         static_cast<unsigned long long>(moduleBase));

    HANDLE self = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ,
                              FALSE, GetCurrentProcessId());
    if (!self) {
        Logf("[!] Could not open own process for validation");
        return;
    }

    OffsetValidator validator;
    if (validator.Initialize(self, moduleBase)) {
        const std::vector<ValidationResult> results = validator.ValidateAll();
        size_t matched = 0;
        for (size_t i = 0; i < results.size(); ++i) {
            const ValidationResult& result = results[i];
            if (result.valid) ++matched;
            // %llX + an explicit cast keeps this portable between MSVC and
            // clang-cl (DWORD64 is unsigned __int64 on both).
            const unsigned long long value =
                static_cast<unsigned long long>(result.actualValue);
            if (result.errorMessage.empty()) {
                Logf("%s %s = 0x%llX", result.valid ? "[+]" : "[-]",
                     result.name.c_str(), value);
            } else {
                Logf("%s %s = 0x%llX  (%s)", result.valid ? "[+]" : "[-]",
                     result.name.c_str(), value, result.errorMessage.c_str());
            }
        }
        Logf("[*] offset validation: %llu/%llu probes matched",
             static_cast<unsigned long long>(matched),
             static_cast<unsigned long long>(results.size()));
    } else {
        Logf("[-] OffsetValidator::Initialize failed (bad module base)");
    }

    CloseHandle(self);
}

} // namespace

Application::Application()
    : bIsRunning(false),
      memoryReader(nullptr),
      gameHooks(nullptr),
      cheatFeatures(nullptr),
      configManager(nullptr)
{
}

Application::~Application() {
    Shutdown();
}

bool Application::CreateCoreComponents() {
    memoryReader  = new MemoryReader();
    configManager = new ConfigManager("apexcheat.ini");
    cheatFeatures = new CheatFeatures();
    gameHooks     = new GameHooks();

    // Publish the globals the renderer / feature code reaches for.
    g_pCheatFeatures = cheatFeatures;
    g_pGameHooks     = gameHooks;

    return memoryReader != nullptr && configManager != nullptr &&
           cheatFeatures != nullptr && gameHooks != nullptr;
}

void Application::DestroyCoreComponents() {
    if (gameHooks) {
        gameHooks->UninstallHooks();
        delete gameHooks;
        gameHooks = nullptr;
        g_pGameHooks = nullptr;
    }
    if (cheatFeatures) {
        delete cheatFeatures;
        cheatFeatures = nullptr;
        g_pCheatFeatures = nullptr;
    }
    if (configManager) {
        delete configManager;
        configManager = nullptr;
    }
    if (memoryReader) {
        memoryReader->Cleanup();
        delete memoryReader;
        memoryReader = nullptr;
    }
}

bool Application::LoadConfiguration() {
    if (!configManager || !cheatFeatures) return false;

    if (!configManager->LoadConfig()) {
        // First run: LoadConfig() has written a default file; the defaults in
        // CheatFeatures (all disabled) remain in effect.
        Logf("[*] No config found, using defaults (apexcheat.ini created)");
    }

    cheatFeatures->EnableFeature(FEATURE_AIMBOT,  configManager->GetBoolValue("aimbot",  false));
    cheatFeatures->EnableFeature(FEATURE_ESP,     configManager->GetBoolValue("esp",     false));
    cheatFeatures->EnableFeature(FEATURE_GLOW,    configManager->GetBoolValue("glow",    false));
    cheatFeatures->EnableFeature(FEATURE_RECOIL,  configManager->GetBoolValue("recoil",  false));

    // One line that says what this session will actually do: a missing or
    // unparsable ini otherwise looks exactly like "the ESP is broken".
    Logf("[*] features: aimbot=%d esp=%d glow=%d recoil=%d",
         cheatFeatures->IsFeatureEnabled(FEATURE_AIMBOT) ? 1 : 0,
         cheatFeatures->IsFeatureEnabled(FEATURE_ESP)    ? 1 : 0,
         cheatFeatures->IsFeatureEnabled(FEATURE_GLOW)   ? 1 : 0,
         cheatFeatures->IsFeatureEnabled(FEATURE_RECOIL) ? 1 : 0);

    return true;
}

bool Application::Initialize() {
    // First thing: open the log.  r5apex_dx12.exe is a /SUBSYSTEM:WINDOWS
    // process, so every std::cout this file used to write went nowhere.  From
    // here on, failures are visible in %LOCALAPPDATA%\QwenKern\<tag>_<pid>.log.
    LogInit(L"payload");
    Logf("[+] Initializing QwenKern Premium (pid=%lu log=%ls)",
         static_cast<unsigned long>(GetCurrentProcessId()), LogPath());

    if (!CreateCoreComponents()) {
        Logf("[-] Failed to create core components");
        return false;
    }

    LoadConfiguration();

    // We are already inside r5apex.exe, so the "target process" is our own:
    // no OpenProcess handle for the anti-cheat to notice.
    if (!memoryReader->Initialize(GetCurrentProcessId())) {
        Logf("[-] MemoryReader::Initialize failed");
        DestroyCoreComponents();
        return false;
    }

    Logf("[*] module base: r5apex_dx12.exe / r5apex.exe = 0x%llX",
         static_cast<unsigned long long>(memoryReader->GetGameModuleBase()));

    ReportOffsetValidation(*memoryReader);

    if (!gameHooks->InstallHooks(memoryReader)) {
        Logf("[-] Failed to install render hooks");
        DestroyCoreComponents();
        return false;
    }

    Logf("[+] Application initialized successfully");
    return true;
}

void Application::Update() {
    if (!cheatFeatures || !memoryReader) return;

    cheatFeatures->UpdateAimbot(memoryReader);
    cheatFeatures->UpdateESP(memoryReader);
    cheatFeatures->UpdateGlow(memoryReader);
    cheatFeatures->UpdateRecoilCompensation(memoryReader);
}

void Application::Run() {
    bIsRunning = true;
    Logf("[*] main loop started (~100 Hz state refresh, drawing happens in Present)");

    while (bIsRunning) {
        Update();
        Sleep(10);   // ~100 Hz state refresh; rendering happens in Present
    }
}

void Application::Shutdown() {
    if (bIsRunning) {
        Logf("[*] shutting down application...");
    }

    bIsRunning = false;
    DestroyCoreComponents();

    // Last statement on purpose: DestroyCoreComponents() -> UninstallHooks()
    // still has D3D12/D3D11 overlay teardown to report.
    Logf("[*] shutdown complete");
    LogClose();
}
