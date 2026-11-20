#!/usr/bin/env python3
"""Quick verification that the harness module works correctly."""
import sys
sys.path.insert(0, '.')

from harness import CheaterAPIHarness, GameSpec, EntityStruct

def test_imports():
    """Test that all classes can be imported."""
    print("=== Import Test ===")
    assert CheaterAPIHarness is not None
    assert GameSpec is not None
    assert EntityStruct is not None

def test_harness_init():
    """Test harness initialization."""
    print("\n=== Harness Init Test ===")
    h = CheaterAPIHarness(api_key='test-key', model='deepseek-chat')
    assert h.api_key == 'test-key'
    assert h.model == 'deepseek-chat'
    assert hasattr(h, 'base_url')
    print("PASS: Harness initialized correctly")

def test_spec_creation():
    """Test GameSpec and EntityStruct creation."""
    print("\n=== Spec Creation Test ===")
    entity = EntityStruct(name='Player', fields={'health': 0x100, 'position': 0x200})
    assert entity.name == 'Player'
    assert entity.fields['health'] == 0x100
    
    spec = GameSpec(
        name='TestGame',
        module_name='test.exe',
        entities=[entity],
        screen_res=(1920, 1080)
    )
    assert spec.name == 'TestGame'
    assert len(spec.entities) == 1
    print("PASS: Spec creation works correctly")

def test_methods_exist():
    """Test that all expected methods exist."""
    print("\n=== Method Existence Test ===")
    h = CheaterAPIHarness(api_key='test', model='deepseek-chat')
    
    methods = ['generate', 'generate_component', 'generate_all', '_parse_response', 
               '_call_api', '_build_minimal_history']
    for method in methods:
        assert hasattr(h, method), f"Missing method: {method}"
        print(f"  OK: {method}")
    
    print("PASS: All required methods present")

def test_parse_response():
    """Test the response parser."""
    print("\n=== Response Parser Test ===")
    h = CheaterAPIHarness(api_key='test', model='deepseek-chat')
    
    # Test with mock API response dict (what _parse_response expects)
    mock_response = {
        "choices": [{
            "message": {
                "content": '''Here's the implementation:

```python
class MemoryReader:
    def __init__(self):
        self.handle = None
    
    def read(self, addr):
        return self.handle.read(addr)
```

This is a simple memory reader class.'''
            }
        }]
    }
    
    result = h._parse_response(mock_response)
    assert 'code' in result, "Missing 'code' key"
    assert 'class MemoryReader' in result['code'], "Code not extracted properly"
    print(f"  Code length: {len(result['code'])} chars")
    print("PASS: Response parser works correctly")

def test_format_spec():
    """Test the spec formatter."""
    print("\n=== Spec Formatter Test ===")
    from harness.harness import _format_spec
    
    entity = EntityStruct(name='Player', fields={'health': 0x100})
    spec = GameSpec(
        name='TestGame',
        module_name='test.exe',
        local_player_offset=0x1234,
        entities=[entity],
        screen_res=(1920, 1080)
    )
    
    formatted = _format_spec(spec)
    assert 'TestGame' in formatted
    assert '0x1234' in formatted
    assert 'health' in formatted
    print(f"  Formatted length: {len(formatted)} chars")
    print("PASS: Spec formatter works correctly")

if __name__ == '__main__':
    tests = [test_imports, test_harness_init, test_spec_creation, 
             test_methods_exist, test_parse_response, test_format_spec]
    
    passed = 0
    failed = 0
    
    for test in tests:
        try:
            test()
            passed += 1
        except Exception as e:
            print(f"FAIL: {e}")
            failed += 1
    
    print(f"\n{'='*50}")
    print(f"Results: {passed} passed, {failed} failed")
    
    if failed == 0:
        print("ALL TESTS PASSED - Harness is working correctly!")
    else:
        print("SOME TESTS FAILED - Check output above")
        sys.exit(1)
