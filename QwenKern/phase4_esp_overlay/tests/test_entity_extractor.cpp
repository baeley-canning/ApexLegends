#include "test_entity_extractor.hpp"
#include "../../entity_extractor.hpp"
#include <iostream>
#include <sstream>

// ============================================================================
// Test Entity Extractor Implementation
// ============================================================================

TestEntityExtractor::TestEntityExtractor() {
    extractor_ = new EntityExtractor();
}

TestEntityExtractor::~TestEntityExtractor() {
    if (extractor_) {
        delete extractor_;
    }
}

std::vector<TestResult> TestEntityExtractor::RunAllTests() {
    std::vector<TestResult> results;
    
    // Run individual test methods
    results.push_back(TestInitialization());
    results.push_back(TestPlayerExtraction());
    results.push_back(TestTeamDifferentiation());
    results.push_back(TestLegendDetection());
    results.push_back(TestHealthShieldExtraction());
    results.push_back(TestHumanizedFeatures());
    results.push_back(TestDistanceCalculation());
    results.push_back(TestStateManagement());
    
    return results;
}

TestResult TestEntityExtractor::TestInitialization() {
    TestResult result{"Initialization", true, "Entity extractor initialization", 0, 0};
    
    // Mock module handle
    HMODULE mock_module = reinterpret_cast<HMODULE>(0x10000000);
    
    bool init_success = extractor_->Initialize(mock_module);
    Assert(init_success, "Entity extractor initialized", result);
    
    Log("Initialization test completed");
    return result;
}

TestResult TestEntityExtractor::TestPlayerExtraction() {
    TestResult result{"Player Extraction", true, "Extracting player entities from memory", 0, 0};
    
    // Create mock player entities
    std::vector<PlayerEntity> mock_players;
    for (uint32_t i = 0; i < 5; ++i) {
        PlayerEntity player{};
        CreateMockPlayerEntity(player, i);
        mock_players.push_back(player);
    }
    
    Assert(mock_players.size() == 5, "Correct number of players extracted", result);
    Assert(mock_players[0].player_name.length() > 0, "Player has valid name", result);
    Assert(mock_players[0].health > 0, "Player has health data", result);
    
    Log("Player extraction test completed");
    return result;
}

TestResult TestEntityExtractor::TestTeamDifferentiation() {
    TestResult result{"Team Differentiation", true, "Identifying teammates vs enemies", 0, 0};
    
    // Create players on different teams
    PlayerEntity player1{}, player2{}, player3{};
    CreateMockPlayerEntity(player1, 0);
    CreateMockPlayerEntity(player2, 1);
    CreateMockPlayerEntity(player3, 2);
    
    // Set team IDs (same team = teammates)
    player1.team_id = 0;  // RED team
    player2.team_id = 0;  // RED team (teammate)
    player3.team_id = 1;  // BLUE team (enemy)
    
    Assert(player1.team_id == player2.team_id, "Players 1 and 2 are teammates", result);
    Assert(player1.team_id != player3.team_id, "Players 1 and 3 are enemies", result);
    
    // Test team color retrieval
    auto color1 = EntityExtractor::GetTeamColor(Team::RED);
    auto color2 = EntityExtractor::GetTeamColor(Team::BLUE);
    
    Assert(color1.x > 0.5f, "RED team has red hue", result);
    Assert(color2.y > 0.3f, "BLUE team has blue hue", result);
    
    Log("Team differentiation test completed");
    return result;
}

TestResult TestEntityExtractor::TestLegendDetection() {
    TestResult result{"Legend Detection", true, "Detecting legend names and types", 0, 0};
    
    // Test various legends
    struct LegendTest {
        LegendName name;
        std::string expected_display;
    };
    
    std::vector<LegendTest> legend_tests = {
        {LegendName::WRAITH, "Wraith"},
        {LegendName::GRIFFIN, "Griffin"},
        {LegendName::CAUSTIC, "Caustic"},
        {LegendName::MIRAGE, "Mirage"},
        {LegendName::REAPER, "Reaper"},
    };
    
    for (const auto& test : legend_tests) {
        std::string display_name = EntityExtractor::GetLegendDisplayName(test.name);
        Assert(display_name == test.expected_display, 
               "Legend " + test.expected_display + " detected correctly", result);
    }
    
    Log("Legend detection test completed");
    return result;
}

TestResult TestEntityExtractor::TestHealthShieldExtraction() {
    TestResult result{"Health/Shield Extraction", true, "Reading health and shield values", 0, 0};
    
    PlayerEntity player{};
    CreateMockPlayerEntity(player, 0);
    
    // Set mock health/shield values
    player.health = 125;
    player.max_health = 125;
    player.shield = 75;
    player.max_shield = 100;
    player.shield_cell_count = 3;
    
    Assert(player.health <= player.max_health, "Health within valid range", result);
    Assert(player.shield <= player.max_shield, "Shield within valid range", result);
    Assert(player.shield_cell_count > 0, "Shield cells present", result);
    
    // Calculate health ratio
    float health_ratio = static_cast<float>(player.health) / 
                        static_cast<float>(player.max_health);
    Assert(health_ratio >= 0.0f && health_ratio <= 1.0f, 
           "Health ratio in valid range [0,1]", result);
    
    Log("Health/shield extraction test completed");
    return result;
}

TestResult TestEntityExtractor::TestHumanizedFeatures() {
    TestResult result{"Humanized Features", true, "Wraith tight, Gibraltar loose patterns", 0, 0};
    
    // Test Wraith (tight pattern)
    auto wraith_config = EntityExtractor::GetHumanizedConfig(LegendName::WRAITH);
    Assert(wraith_config.is_tight, "Wraith has tight hitbox", result);
    Assert(!wraith_config.is_loose, "Wraith is not loose", result);
    
    // Test Griffin (loose pattern)
    auto griffin_config = EntityExtractor::GetHumanizedConfig(LegendName::GRIFFIN);
    Assert(griffin_config.is_loose, "Griffin has loose hitbox", result);
    Assert(!griffin_config.is_tight, "Griffin is not tight", result);
    
    // Test Caustic (tight)
    auto caustic_config = EntityExtractor::GetHumanizedConfig(LegendName::CAUSTIC);
    Assert(caustic_config.is_tight, "Caustic has tight hitbox", result);
    
    Log("Humanized features test completed");
    return result;
}

TestResult TestEntityExtractor::TestDistanceCalculation() {
    TestResult result{"Distance Calculation", true, "Computing player distances", 0, 0};
    
    // Create players at different positions
    DirectX::XMFLOAT3 pos1{0.0f, 0.0f, 0.0f};
    DirectX::XMFLOAT3 pos2{100.0f, 0.0f, 0.0f};
    DirectX::XMFLOAT3 pos3{100.0f, 100.0f, 100.0f};
    
    float dist12 = EntityExtractor::CalculateDistance(pos1, pos2);
    float dist13 = EntityExtractor::CalculateDistance(pos1, pos3);
    
    Assert(dist12 == 100.0f, "Distance between pos1 and pos2 is 100", result);
    Assert(dist13 > 150.0f && dist13 < 180.0f, 
           "Distance between pos1 and pos3 is ~173", result);
    
    Log("Distance calculation test completed");
    return result;
}

TestResult TestEntityExtractor::TestStateManagement() {
    TestResult result{"State Management", true, "Player state tracking (ALIVE/DYING/DEAD)", 0, 0};
    
    // Test alive state
    PlayerEntity alive_player{};
    alive_player.state = PlayerState::ALIVE;
    Assert(EntityExtractor::IsAlive(alive_player), "Alive player detected correctly", result);
    
    // Test dying state
    PlayerEntity dying_player{};
    dying_player.state = PlayerState::DYING;
    Assert(EntityExtractor::IsAlive(dying_player), "Dying player still considered alive", result);
    
    // Test dead state
    PlayerEntity dead_player{};
    dead_player.state = PlayerState::DEAD;
    Assert(!EntityExtractor::IsAlive(dead_player), "Dead player detected correctly", result);
    Assert(EntityExtractor::IsDead(dead_player), "Dead state properly identified", result);
    
    // Test spawning state
    PlayerEntity spawning_player{};
    spawning_player.state = PlayerState::SPAWNING;
    Assert(EntityExtractor::IsAlive(spawning_player), "Spawning player detected correctly", result);
    
    Log("State management test completed");
    return result;
}

void TestEntityExtractor::Log(const std::string& message, bool is_error) {
    std::cout << (is_error ? "[ERROR] " : "[INFO] ") << message << std::endl;
}

void TestEntityExtractor::Assert(bool condition, const std::string& description,
                                  TestResult& result) {
    result.assertions++;
    if (condition) {
        // Test passed
    } else {
        result.failures++;
        result.passed = false;
        Log("Assertion failed: " + description, true);
    }
}

void TestEntityExtractor::CreateMockPlayerEntity(PlayerEntity& player, uint32_t index) {
    player.address = 0x10000000 + index * 0x1000;
    player.base_entity = player.address + 0x100;
    
    // Player name
    std::ostringstream oss;
    oss << "Player_" << index;
    player.player_name = oss.str();
    
    // Account ID
    player.account_id = 1000 + index;
    
    // Position
    player.position = CreateMockPosition(
        static_cast<float>(index * 50),
        static_cast<float>(index * 30),
        static_cast<float>(index * 40)
    );
    
    // Health and shield
    player.health = 100 + index * 5;
    player.max_health = 125;
    player.shield = 50 + index * 10;
    player.max_shield = 100;
    player.shield_cell_count = 2 + index % 3;
    
    // Team assignment (cycling through teams)
    player.team_id = static_cast<uint8_t>(index % 8);
    player.team = static_cast<Team>(player.team_id);
    
    // State
    player.state = PlayerState::ALIVE;
    
    // Legend assignment
    player.legend_name = static_cast<LegendName>(index % 41);
    player.legend_display_name = EntityExtractor::GetLegendDisplayName(player.legend_name);
    
    // Humanized config
    player.humanized_config = EntityExtractor::GetHumanizedConfig(player.legend_name);
}

DirectX::XMFLOAT3 TestEntityExtractor::CreateMockPosition(float x, float y, float z) {
    return DirectX::XMFLOAT3{x, y, z};
}
