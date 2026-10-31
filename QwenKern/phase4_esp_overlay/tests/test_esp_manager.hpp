#pragma once
#ifndef TEST_ESP_MANAGER_HPP
#define TEST_ESP_MANAGER_HPP

#include <Windows.h>
#include <cstdint>
#include <vector>
#include <string>
#include <functional>
#include <iostream>

// Forward declarations
class ESPManager;
struct ESPConfig;

// Test result structure
struct TestResult {
    std::string name;
    bool passed;
    std::string message;
    uint32_t assertions;
    uint32_t failures;
};

// ESP manager test suite
class TestESPManager {
public:
    TestESPManager();
    ~TestESPManager();
    
    // Run all tests
    std::vector<TestResult> RunAllTests();
    
    // Individual test methods
    TestResult TestInitialization();
    TestResult TestConfigurationLoading();
    TestResult TestFeatureToggles();
    TestResult TestPresetManagement();
    TestResult TestRenderLoop();
    TestResult TestTeamColorIntegration();
    TestResult TestHumanizedConfigIntegration();
    TestResult TestLoggingSystem();

private:
    ESPManager* manager_ = nullptr;
    
    // Helper methods
    void Log(const std::string& message, bool is_error = false);
    void Assert(bool condition, const std::string& description, 
                TestResult& result);
};

#endif // TEST_ESP_MANAGER_HPP
