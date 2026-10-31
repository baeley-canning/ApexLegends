#!/usr/bin/env python3
"""
Test script for Apex Pack Duplicator
"""

import sys
sys.path.insert(0, r"C:\Users\New User\OneDrive\Desktop\Qwen Knowledge base\phase4_apex_cheat")

from apex_pack_duplicator import PackDuplicator, PackState


def test_basic_duplication():
    """Test basic pack duplication functionality"""
    print("Testing basic pack duplication...")
    
    duplicator = PackDuplicator()
    duplicator.start()
    
    # Simulate opening a pack
    pack_address = 0x10000000
    duplicates = duplicator.duplicate_pack_from_memory(pack_address, count=3)
    
    assert len(duplicates) == 3, f"Expected 3 duplicates, got {len(duplicates)}"
    assert all(d.pack_type == 'Rare' for d in duplicates), "All should be Rare packs"
    
    print(f"✓ Created {len(duplicates)} duplicates")
    print(f"✓ Pack IDs: {[d.pack_id for d in duplicates]}")
    
    duplicator.stop()
    return True


def test_multiple_pack_types():
    """Test duplication with different pack types"""
    print("\nTesting multiple pack types...")
    
    duplicator = PackDuplicator()
    duplicator.start()
    
    # Use addresses that will trigger different pack types
    # Pack type is determined by: (address >> 8) & 0x0F
    # Rare: 0-4, Epic: 5-8, Legendary: 9-12, Heirloom: 13-15
    
    pack_addresses = [
        (0x10000000, 'Rare'),   # type_byte = 0x0
        (0x10005000, 'Epic'),   # type_byte = 0x5 -> Epic
        (0x10009000, 'Legendary'),  # type_byte = 0x9 -> Legendary
        (0x1000D000, 'Heirloom'),   # type_byte = 0xD -> Heirloom
    ]
    
    for address, expected_type in pack_addresses:
        state = duplicator.capture_pack_from_memory(address)
        if state:
            assert state.pack_type == expected_type, f"Expected {expected_type}, got {state.pack_type}"
            print(f"✓ Captured {state.pack_type} pack at {hex(address)}")
    
    duplicator.stop()
    return True


def test_signature_verification():
    """Test that pack signatures can be computed for dupe verification"""
    print("\nTesting signature verification...")
    
    state1 = PackState(
        pack_id="ABC123",
        pack_type="Epic",
        player_context={'slots': 10, 'owned': 50},
        server_seed="SEED0001"
    )
    
    state2 = PackState(
        pack_id="ABC123",  # Same pack ID
        pack_type="Epic",
        player_context={'slots': 10, 'owned': 50},
        server_seed="SEED0001"
    )
    
    sig1 = state1.compute_signature()
    sig2 = state2.compute_signature()
    
    assert sig1 == sig2, f"Signatures should match: {sig1} vs {sig2}"
    print(f"✓ identical packs have matching signatures: {sig1}")
    
    # Different pack should have different signature
    state3 = PackState(
        pack_id="XYZ789",
        pack_type="Legendary",
        player_context={'slots': 15, 'owned': 60},
        server_seed="SEED0002"
    )
    
    sig3 = state3.compute_signature()
    assert sig3 != sig1, "Different packs should have different signatures"
    print(f"✓ different pack signature: {sig3}")
    
    return True


def test_duplicate_grouping():
    """Test that duplicate packs are grouped correctly"""
    print("\nTesting duplicate grouping...")
    
    duplicator = PackDuplicator()
    duplicator.start()
    
    # Create some duplicate groups
    for i in range(2):
        duplicates = duplicator.duplicate_pack_from_memory(0x10000000 + i*0x1000, count=3)
        print(f"✓ Group {i+1}: {[d.pack_id for d in duplicates]}")
    
    # Group duplicates
    groups = duplicator.interceptor.group_duplicates(threshold_seconds=5.0)
    print(f"✓ Found {len(groups)} duplicate group(s)")
    
    duplicator.stop()
    return True


def main():
    """Run all tests"""
    print("="*60)
    print("APEX PACK DUPLICATION TEST SUITE")
    print("="*60)
    
    tests = [
        ("Basic Duplication", test_basic_duplication),
        ("Multiple Pack Types", test_multiple_pack_types),
        ("Signature Verification", test_signature_verification),
        ("Duplicate Grouping", test_duplicate_grouping),
    ]
    
    passed = 0
    failed = 0
    
    for name, test_func in tests:
        try:
            if test_func():
                passed += 1
                print(f"\n✓ {name} PASSED")
        except Exception as e:
            failed += 1
            print(f"\n✗ {name} FAILED: {e}")
    
    print("\n" + "="*60)
    print(f"RESULTS: {passed} passed, {failed} failed")
    print("="*60)
    
    return failed == 0


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
