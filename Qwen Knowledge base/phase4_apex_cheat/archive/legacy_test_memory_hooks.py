#!/usr/bin/env python3
"""
Test script for Real Apex Process Memory Hooks

Tests integration with live r5apex_dx12.exe process:
- Process attachment
- Pack entity discovery
- Server seed reading
- Pack duplication using real memory
"""

import sys
import time
from datetime import datetime

sys.path.insert(0, r"C:\Users\New User\OneDrive\Desktop\Qwen Knowledge base\phase4_apex_cheat")
sys.path.insert(0, r"C:\Users\New User\OneDrive\Desktop\Qwen Knowledge base\phase4_apex_cheat\cheat_core")

from apex_pack.memory_hooks import (
    ApexProcess,
    RealMemoryHook,
    PackEntityScanner,
    ServerSeedReader,
    get_apex_process,
    scan_current_packs,
)


def test_process_attachment():
    """Test attaching to live r5apex_dx12.exe process"""
    print("="*60)
    print("TEST 1: Process Attachment")
    print("="*60)

    try:
        process = ApexProcess()
        
        # Try to attach to live Apex
        success = process.attach(process_name="r5apex_dx12.exe")
        
        if success:
            print(f"✓ Successfully attached to r5apex_dx12.exe")
            print(f"  PID: {process.pid}")
            print(f"  Base Address: {hex(process.base_address)}")
            
            # Test basic memory operations
            test_addr = process.base_address + 0x1000
            test_value = 0xDEADBEEFCAFEBABE
            
            # Write and read test
            process.write_uint64(test_addr, test_value)
            read_value = process.read_uint64(test_addr)
            
            if read_value == test_value:
                print(f"✓ Memory read/write works (test: {hex(test_value)})")
            else:
                print(f"✗ Memory mismatch: wrote {hex(test_value)}, read {hex(read_value)}")
            
            process.detach()
            return True
        else:
            print("✗ Failed to attach to Apex process")
            return False
            
    except Exception as e:
        print(f"✗ Error: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_pack_entity_discovery():
    """Test scanning for pack entities in live process"""
    print("\n" + "="*60)
    print("TEST 2: Pack Entity Discovery")
    print("="*60)

    try:
        process = get_apex_process()
        
        # Scan for packs
        scanner = PackEntityScanner(process)
        packs = scanner.scan_for_packs(max_packs=10)
        
        print(f"✓ Found {len(packs)} pack entities")
        
        if packs:
            # Display first few packs
            for i, pack in enumerate(packs[:5]):
                print(f"\n  Pack {i+1}:")
                print(f"    Address: {hex(pack.address)}")
                print(f"    Pack ID: {pack.pack_id}")
                print(f"    Type: {pack.pack_type}")
                print(f"    Server Seed: {pack.server_seed}")
                print(f"    Player Context: {pack.player_context}")
        
        process.detach()
        return True
        
    except Exception as e:
        print(f"✗ Error: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_server_seed_reading():
    """Test real-time server seed reading"""
    print("\n" + "="*60)
    print("TEST 3: Server Seed Reading")
    print("="*60)

    try:
        process = get_apex_process()
        
        # Get some pack addresses
        scanner = PackEntityScanner(process)
        packs = scanner.scan_for_packs(max_packs=5)
        
        if not packs:
            print("✗ No packs found for seed reading test")
            return False
        
        # Test single seed read
        seed_reader = ServerSeedReader(process)
        
        for pack in packs[:3]:
            seed = seed_reader.read_seed_for_pack(pack.address)
            print(f"✓ Pack {hex(pack.address)}: seed = {seed}")
        
        # Test multiple seeds
        addresses = [p.address for p in packs]
        seeds = seed_reader.read_multiple_seeds(addresses)
        
        print(f"\n✓ Read {len(seeds)} seeds in batch")
        
        process.detach()
        return True
        
    except Exception as e:
        print(f"✗ Error: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_real_memory_hook_duplication():
    """Test pack duplication using real memory hooks"""
    print("\n" + "="*60)
    print("TEST 4: Real Memory Hook Duplication")
    print("="*60)

    try:
        process = get_apex_process()
        
        # Get initial packs
        scanner = PackEntityScanner(process)
        packs = scanner.scan_for_packs(max_packs=5)
        
        if not packs:
            print("✗ No packs found for duplication test")
            return False
        
        # Test duplication on first pack
        first_pack = packs[0]
        print(f"\nTesting duplication on pack at {hex(first_pack.address)}...")
        
        hook = RealMemoryHook(process)
        results = hook.duplicate_pack(first_pack.address, count=3)
        
        print(f"✓ Successfully duplicated pack")
        print(f"  Opened {len(results)} times with same seed")
        
        all_success = True
        for result in results:
            loot = result.get('loot', {})
            success = result.get('success', False)
            all_success = all_success and success
            
            print(f"\n  Dup {result['duplicate_index']}:")
            print(f"    Pack ID: {result['pack_id']}")
            print(f"    Seed: {result['seed']}")
            print(f"    Type: {loot.get('pack_type', 'Unknown')}")
            print(f"    Items: {loot.get('item_count', 0)}")
            print(f"    Heirloom Chance: {loot.get('is_heirloom_chance', False)}")
            print(f"    Success: {success}")
        
        process.detach()
        return all_success
        
    except Exception as e:
        print(f"✗ Error: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_hybrid_with_real_memory():
    """Test hybrid duplicator with real Apex memory"""
    print("\n" + "="*60)
    print("TEST 5: Hybrid Duplicator with Real Memory")
    print("="*60)

    try:
        from apex_pack_duplication_fixed import HybridPackDuplicator
        
        # Start duplicator
        duplicator = HybridPackDuplicator()
        duplicator.start()
        
        # Run hybrid duplication (memory + packet methods)
        result = duplicator.duplicate_pack(method='hybrid', count=3)
        
        print(f"✓ Hybrid duplication complete")
        print(f"  Method: {result['method']}")
        print(f"  Memory opens: {len(result['memory_results'])}")
        print(f"  Packet replays: {len(result['packet_results'])}")
        print(f"  Combined success: {result['combined_success']}")
        
        # Print memory results
        if result['memory_results']:
            print(f"\n  Memory Results:")
            for m in result['memory_results']:
                print(f"    Dup {m['duplicate_index']}: {m['loot']['pack_type']} "
                      f"({m['loot']['item_count']} items)")
        
        # Print packet results
        if result['packet_results']:
            print(f"\n  Packet Results:")
            for p in result['packet_results']:
                print(f"    Replay {p['replay_index']}: seed={p['modified_seed'][:8]}... "
                      f"success={p['success']}")
        
        duplicator.stop()
        return True
        
    except Exception as e:
        print(f"✗ Error: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_with_live_apex():
    """Test with live Apex process (requires Apex to be running)"""
    print("\n" + "="*60)
    print("TEST 6: Live Apex Integration")
    print("="*60)

    try:
        # Check if Apex is running
        process = ApexProcess()
        
        # Try multiple times if Apex not ready
        max_attempts = 3
        for attempt in range(1, max_attempts + 1):
            print(f"\nAttempt {attempt}/{max_attempts}...")
            
            success = process.attach(process_name="r5apex_dx12.exe")
            if success:
                break
            
            if attempt < max_attempts:
                print(f"  Apex not ready, waiting 3s...")
                time.sleep(3)
        
        if not success:
            print("✗ Could not attach to Apex after multiple attempts")
            print("  (Ensure r5apex_dx12.exe is running)")
            return False
        
        # Quick operations test
        test_addr = process.base_address + 0x2000
        
        # Write test data
        test_data = b'\x55\xAA\x55\xAA\x01\x02\x03\x04'
        process.write_bytes(test_addr, test_data)
        
        # Read back
        read_data = process.read_bytes(test_addr, len(test_data))
        
        if read_data == test_data:
            print(f"✓ Live Apex operations successful")
            print(f"  Test write/read at {hex(test_addr)}")
        else:
            print(f"✗ Data mismatch in live Apex")
        
        process.detach()
        return True
        
    except Exception as e:
        print(f"✗ Error: {e}")
        import traceback
        traceback.print_exc()
        return False


def main():
    """Run all tests"""
    print("\n" + "="*60)
    print("REAL APEX MEMORY HOOKS TEST SUITE")
    print("="*60)
    print(f"\nStarted: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("\nTest Summary:")
    print("  1. Process Attachment - Attach to r5apex_dx12.exe")
    print("  2. Pack Entity Discovery - Scan for pack entities")
    print("  3. Server Seed Reading - Real-time seed reading")
    print("  4. Real Memory Hook Duplication - Duplicate packs")
    print("  5. Hybrid Duplicator - Combine memory + packet methods")
    print("  6. Live Apex Integration - Full integration test")

    tests = [
        ("Process Attachment", test_process_attachment),
        ("Pack Entity Discovery", test_pack_entity_discovery),
        ("Server Seed Reading", test_server_seed_reading),
        ("Real Memory Hook Duplication", test_real_memory_hook_duplication),
        ("Hybrid Duplicator with Real Memory", test_hybrid_with_real_memory),
        ("Live Apex Integration", test_with_live_apex),
    ]

    passed = 0
    failed = 0
    results = []

    for name, test_func in tests:
        try:
            print(f"\n{'='*60}")
            print(f"RUNNING: {name}")
            print('='*60)
            
            if test_func():
                passed += 1
                results.append((name, "PASSED", None))
                print(f"\n✓ {name} PASSED")
            else:
                failed += 1
                results.append((name, "FAILED", None))
                print(f"\n✗ {name} FAILED")
                
        except Exception as e:
            failed += 1
            results.append((name, "ERROR", str(e)))
            print(f"\n✗ {name} ERROR: {e}")

    # Summary
    print("\n" + "="*60)
    print("TEST SUMMARY")
    print("="*60)
    
    print(f"\nTotal Tests: {len(tests)}")
    print(f"Passed: {passed}")
    print(f"Failed: {failed}")
    
    if results:
        print("\nResults:")
        for name, status, error in results:
            print(f"  [{status}] {name}" + (f" - {error}" if error else ""))
    
    # Final status
    print("\n" + "="*60)
    if failed == 0:
        print("ALL TESTS PASSED ✓")
    else:
        print(f"SOME TESTS FAILED ({failed} failures)")
    print("="*60)
    
    return failed == 0


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
