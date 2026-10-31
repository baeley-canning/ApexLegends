#pragma once
#ifndef TEST_ESP_RENDERER_HPP
#define TEST_ESP_RENDERER_HPP

#include <Windows.h>
#include <cstdint>
#include <vector>
#include <string>
#include <functional>
#include <iostream>

// Forward declarations
class ESPRenderer;
struct ESPConfig;
struct PlayerEntity;

// Test result structure
struct TestResult {
    std::string name;
    bool passed;
    std::string message;
    uint32_t assertions;
    uint32_t failures;
};

// ESP renderer test suite
class TestESPRenderer {
public:
    TestESPRenderer();
    ~TestESPRenderer();
    
    // Run all tests
    std::vector<TestResult> RunAllTests();
    
    // Individual test methods
    TestResult TestInitialization();
    TestResult TestBoxRendering();
    TestResult TestGlowEffects();
    TestResult TestSkeletonRendering();
    TestResult TestHealthBarDisplay();
    TestResult TestDistanceIndicators();
    TestResult TestSnaplines();
    TestResult TestFeatureToggles();

private:
    ESPRenderer* renderer_ = nullptr;
    ESPConfig config_;
    
    // Helper methods
    void Log(const std::string& message, bool is_error = false);
    void Assert(bool condition, const std::string& description, 
                TestResult& result);
    
    // Test fixtures
    PlayerEntity CreateMockPlayer(uint32_t index);
    DirectX::XMFLOAT3 CreateMockPosition(float x, float y, float z);
};

#endif // TEST_ESP_RENDERER_HPP
