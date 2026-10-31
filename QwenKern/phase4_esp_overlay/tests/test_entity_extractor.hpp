#pragma once
#ifndef TEST_ENTITY_EXTRACTOR_HPP
#define TEST_ENTITY_EXTRACTOR_HPP

#include <Windows.h>
#include <cstdint>
#include <vector>
#include <string>
#include <functional>
#include <iostream>

// Forward declarations
class EntityExtractor;
struct PlayerEntity;

// Test result structure
struct TestResult {
    std::string name;
    bool passed;
    std::string message;
    uint32_t assertions;
    uint32_t failures;
};

// Entity extractor test suite
class TestEntityExtractor {
public:
    TestEntityExtractor();
    ~TestEntityExtractor();
    
    // Run all tests
    std::vector<TestResult> RunAllTests();
    
    // Individual test methods
    TestResult TestInitialization();
    TestResult TestPlayerExtraction();
    TestResult TestTeamDifferentiation();
    TestResult TestLegendDetection();
    TestResult TestHealthShieldExtraction();
    TestResult TestHumanizedFeatures();
    TestResult TestDistanceCalculation();
    TestResult TestStateManagement();

private:
    EntityExtractor* extractor_ = nullptr;
    
    // Helper methods
    void Log(const std::string& message, bool is_error = false);
    void Assert(bool condition, const std::string& description, 
                TestResult& result);
    
    // Test fixtures
    void CreateMockPlayerEntity(PlayerEntity& player, uint32_t index);
    DirectX::XMFLOAT3 CreateMockPosition(float x, float y, float z);
};

#endif // TEST_ENTITY_EXTRACTOR_HPP
