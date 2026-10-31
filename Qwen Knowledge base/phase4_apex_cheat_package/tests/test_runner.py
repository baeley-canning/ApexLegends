#!/usr/bin/env python3
"""
Phase 4: Comprehensive Test Runner

Runs all Phase 4 tests for menu integration and ESP overlay.
"""

import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from test_menu_integration import run_all_tests as run_menu_tests
from test_esp_overlay import run_all_tests as run_esp_tests


def run_phase4_tests():
    """Run all Phase 4 tests."""
    print("=" * 60)
    print("Phase 4 Comprehensive Test Suite")
    print("=" * 60)
    
    # Run menu integration tests
    print("\n" + "=" * 60)
    print("MENU INTEGRATION TESTS")
    print("=" * 60)
    menu_results = run_menu_tests()
    
    # Run ESP overlay tests
    print("\n" + "=" * 60)
    print("ESP OVERLAY TESTS")
    print("=" * 60)
    esp_results = run_esp_tests()
    
    # Combined summary
    print("\n" + "=" * 60)
    print("PHASE 4 TEST SUMMARY")
    print("=" * 60)
    
    menu_passed = sum(1 for _, r in menu_results if r)
    menu_total = len(menu_results)
    
    esp_passed = sum(1 for _, r in esp_results if r)
    esp_total = len(esp_results)
    
    total_passed = menu_passed + esp_passed
    total_tests = menu_total + esp_total
    
    print(f"\nMenu Integration Tests: {menu_passed}/{menu_total} passed")
    print(f"ESP Overlay Tests:        {esp_passed}/{esp_total} passed")
    print(f"Total:                    {total_passed}/{total_tests} passed")
    
    # Pass/fail decision
    if total_passed == total_tests:
        print("\n✅ All Phase 4 tests passed!")
        return True
    else:
        print(f"\n⚠️  {total_tests - total_passed} test(s) failed")
        return False


if __name__ == "__main__":
    success = run_phase4_tests()
    sys.exit(0 if success else 1)
