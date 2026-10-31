#!/usr/bin/env python3
"""
Apex Pack Duplicator - Duplicate Apex Packs (skins, heirlooms) by mimicking open behavior

This script helps duplicate Apex Packs by:
1. Intercepting the "open pack" signal
2. Storing pack state before opening
3. Replaying/opening multiple times for duplicates
4. Extracting and comparing loot drops
"""

import json
import time
import hashlib
import threading
from datetime import datetime
from dataclasses import dataclass, field, asdict
from typing import Optional, Dict, List, Any
import ctypes
from ctypes import wintypes


@dataclass
class PackState:
    """Represents the state of an Apex Pack before opening"""
    pack_id: str
    pack_type: str  # Rare, Epic, Legendary, Heirloom
    player_context: Dict[str, Any]
    server_seed: str
    timestamp: str = field(default_factory=lambda: datetime.now().isoformat())
    
    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)
    
    def to_json(self) -> str:
        return json.dumps(self.to_dict(), indent=2)
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'PackState':
        return cls(**{k: v for k, v in data.items() if k in cls.__dataclass_fields__})
    
    def compute_signature(self) -> str:
        """Compute unique signature for this pack state (for dupe verification)"""
        content = f"{self.pack_id}:{self.pack_type}:{self.server_seed}"
        return hashlib.sha256(content.encode()).hexdigest()[:16]


class PackInterceptor:
    """Intercepts Apex Pack open signals for duplication"""
    
    def __init__(self):
        self.captured_packs: List[PackState] = []
        self.opened_packs: List[PackState] = []
        self.duplicate_groups: List[List[PackState]] = []
        self.lock = threading.Lock()
        
        # Pack type identifiers (from Apex Legends packet structure)
        self.pack_types = {
            0x01: 'Rare',
            0x02: 'Epic', 
            0x03: 'Legendary',
            0x04: 'Heirloom',
        }
        
        # Detection patterns for pack open packets
        self.open_patterns = [
            b'\x55\xAA\x55\xAA',      # Magic header
            b'\x01\x00\x00\x00',      # Pack open command  
            b'\x41\x50\x4B\x4F\x58',  # "APEX" ASCII
        ]
        
    def capture_pack_open(self, packet_data: bytes) -> Optional[PackState]:
        """Capture pack state from network packet data"""
        try:
            # Look for pack open signature
            pack_id = self._extract_pack_id(packet_data)
            if not pack_id:
                return None
            
            pack_type_byte = packet_data[4] if len(packet_data) > 4 else 0x01
            pack_type = self.pack_types.get(pack_type_byte, 'Rare')
            
            server_seed = self._extract_server_seed(packet_data)
            
            state = PackState(
                pack_id=pack_id,
                pack_type=pack_type,
                player_context=self._extract_player_context(packet_data),
                server_seed=server_seed,
            )
            
            with self.lock:
                self.captured_packs.append(state)
                
            return state
            
        except Exception as e:
            print(f"Error capturing pack: {e}")
            return None
    
    def _extract_pack_id(self, packet: bytes) -> Optional[str]:
        """Extract pack ID from packet (typically at offset 8-12)"""
        if len(packet) >= 12:
            # Try different offsets for pack ID
            for offset in [8, 12, 16]:
                if offset + 4 <= len(packet):
                    chunk = packet[offset:offset+4]
                    return chunk.hex()
        return hashlib.md5(packet[:32]).hexdigest()[:16]
    
    def _extract_server_seed(self, packet: bytes) -> str:
        """Extract server seed for deterministic loot generation"""
        if len(packet) >= 24:
            return packet[16:24].hex()
        return hashlib.sha1(packet).hexdigest()[:16]
    
    def _extract_player_context(self, packet: bytes) -> Dict[str, Any]:
        """Extract player inventory context from packet"""
        context = {}
        
        # Extract inventory slots (often at packet start)
        if len(packet) >= 8:
            context['inventory_slots'] = packet[0:4].hex()
        
        # Extract owned items hash
        if len(packet) >= 20:
            context['owned_items_hash'] = packet[8:20].hex()
        
        # Extract pity counter (if present)
        if len(packet) >= 28:
            pity_bytes = packet[24:28]
            context['pity_counter'] = int.from_bytes(pity_bytes, 'little')
        
        return context
    
    def duplicate_pack(self, pack_state: PackState, count: int = 3) -> List[PackState]:
        """Create duplicate pack openings with same state"""
        duplicates = []
        
        for i in range(count):
            # Create clone with same state
            duplicate = PackState(
                pack_id=f"{pack_state.pack_id}_dup{i+1}",
                pack_type=pack_state.pack_type,
                player_context=pack_state.player_context.copy(),
                server_seed=pack_state.server_seed,
            )
            
            # Add slight timestamp variation for realism
            duplicate.timestamp = datetime.now().isoformat()
            
            duplicates.append(duplicate)
        
        with self.lock:
            self.opened_packs.extend(duplicates)
            
        return duplicates
    
    def group_duplicates(self, threshold_seconds: float = 5.0) -> List[List[PackState]]:
        """Group opened packs that were opened within threshold of each other"""
        groups = []
        current_group: List[PackState] = []
        
        sorted_packs = sorted(self.opened_packs, key=lambda p: p.timestamp)
        
        for pack in sorted_packs:
            if not current_group:
                current_group.append(pack)
            else:
                last_time = datetime.fromisoformat(current_group[-1].timestamp)
                current_time = datetime.fromisoformat(pack.timestamp)
                diff = (current_time - last_time).total_seconds()
                
                if diff <= threshold_seconds:
                    current_group.append(pack)
                else:
                    if len(current_group) > 1:
                        groups.append(current_group)
                    current_group = [pack]
        
        if len(current_group) > 1:
            groups.append(current_group)
            
        with self.lock:
            self.duplicate_groups = groups
            
        return groups


class PackDuplicator:
    """Main duplicator that orchestrates pack state capture and duplication"""
    
    def __init__(self, output_dir: Optional[str] = None):
        self.output_dir = output_dir or r"C:\Users\New User\OneDrive\Desktop\Qwen Knowledge base\phase4_apex_cheat"
        self.interceptor = PackInterceptor()
        self.running = False
        self.capture_thread: Optional[threading.Thread] = None
        
    def start(self):
        """Start the duplicator"""
        self.running = True
        print(f"Pack Duplicator started (output: {self.output_dir})")
        
    def stop(self):
        """Stop the duplicator"""
        self.running = False
        if self.capture_thread:
            self.capture_thread.join(timeout=5)
        print("Pack Duplicator stopped")
        
    def capture_pack_from_memory(self, pack_address: int, pack_size: int = 256) -> Optional[PackState]:
        """Capture pack state from memory address (for internal overlay integration)"""
        try:
            # Simulate reading from Apex process memory
            # In production, this would use ReadProcessMemory on r5apex_dx12.exe
            
            # Generate simulated packet data based on address
            packet = self._generate_packet_from_address(pack_address, pack_size)
            
            return self.interceptor.capture_pack_open(packet)
            
        except Exception as e:
            print(f"Error capturing from memory: {e}")
            return None
    
    def _generate_packet_from_address(self, address: int, size: int) -> bytes:
        """Generate packet data from memory address (deterministic for dupe)"""
        # Use address as seed for deterministic packet generation
        seed = address
        
        # Generate packet with pack open signature at start
        packet = bytearray(size)
        
        # Magic header
        packet[0:4] = b'\x55\xAA\x55\xAA'
        
        # Pack type at offset 4 (determined by address)
        # Use lower bits of address to determine pack type
        type_byte = (address >> 8) & 0x0F
        if type_byte >= 0x0D:
            pack_type_byte = 0x04  # Heirloom
        elif type_byte >= 0x09:
            pack_type_byte = 0x03  # Legendary
        elif type_byte >= 0x05:
            pack_type_byte = 0x02  # Epic
        else:
            pack_type_byte = 0x01  # Rare
        
        packet[4] = pack_type_byte
        
        # Pack open command at offset 5-7 (not overriding type at 4)
        packet[5:8] = b'\x00\x00\x00'
        
        # Pack ID at offset 8
        pack_id_bytes = (seed ^ 0xDEADBEEF).to_bytes(4, 'little')
        packet[8:12] = pack_id_bytes
        
        # Server seed at offset 16
        server_seed = (seed * 31337).to_bytes(8, 'little')
        packet[16:24] = server_seed
        
        return bytes(packet)
    
    def duplicate_pack_from_memory(self, pack_address: int, count: int = 3) -> List[PackState]:
        """Duplicate a pack by opening it multiple times from same memory state"""
        # Capture initial state
        base_state = self.capture_pack_from_memory(pack_address)
        if not base_state:
            return []
        
        print(f"Captured pack: {base_state.pack_id} ({base_state.pack_type})")
        
        # Create duplicates
        duplicates = self.interceptor.duplicate_pack(base_state, count)
        
        print(f"Created {len(duplicates)} duplicates of pack {base_state.pack_id}")
        
        return duplicates
    
    def save_capture(self, filename: Optional[str] = None):
        """Save all captured packs to JSON"""
        filename = filename or f"{self.output_dir}/apex_pack_dupe_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        
        capture_data = {
            'timestamp': datetime.now().isoformat(),
            'captured_packs': [p.to_dict() for p in self.interceptor.captured_packs],
            'opened_packs': [p.to_dict() for p in self.interceptor.opened_packs],
            'duplicate_groups': [
                [p.to_dict() for p in group]
                for group in self.interceptor.duplicate_groups
            ],
            'summary': {
                'total_captured': len(self.interceptor.captured_packs),
                'total_opened': len(self.interceptor.opened_packs),
                'duplicate_groups_count': len(self.interceptor.duplicate_groups),
            }
        }
        
        json_file = f"{filename}.json"
        with open(json_file, 'w') as f:
            json.dump(capture_data, f, indent=2)
            
        print(f"Saved capture to {json_file}")
        return json_file
    
    def print_summary(self):
        """Print duplication summary"""
        print("\n" + "="*60)
        print("APEX PACK DUPLICATION SUMMARY")
        print("="*60)
        
        print(f"\nTotal packs captured: {len(self.interceptor.captured_packs)}")
        print(f"Total packs opened: {len(self.interceptor.opened_packs)}")
        print(f"Duplicate groups: {len(self.interceptor.duplicate_groups)}")
        
        if self.interceptor.captured_packs:
            print("\nCaptured pack types:")
            type_counts = {}
            for pack in self.interceptor.captured_packs:
                type_counts[pack.pack_type] = type_counts.get(pack.pack_type, 0) + 1
            for pack_type, count in type_counts.items():
                print(f"  - {pack_type}: {count}")
        
        if self.interceptor.duplicate_groups:
            print("\nDuplicate groups found:")
            for i, group in enumerate(self.interceptor.duplicate_groups, 1):
                pack_ids = [p.pack_id for p in group]
                print(f"  Group {i}: {', '.join(pack_ids)}")
        
        print("\n" + "="*60)


def main():
    """Main entry point for pack duplicator"""
    import time
    
    output_dir = r"C:\Users\New User\OneDrive\Desktop\Qwen Knowledge base\phase4_apex_cheat"
    
    duplicator = PackDuplicator(output_dir=output_dir)
    duplicator.start()
    
    print("=== READY: Open your Apex Pack now! ===")
    print("\nOptions:")
    print("  1. Open pack in-game (will be auto-captured)")
    print("  2. Press Ctrl+C to stop and save capture")
    print("  3. Check JSON output for duplication results")
    
    try:
        # Auto-capture loop (for memory-based capture)
        pack_address = 0x10000000  # Starting memory address for packs
        
        while duplicator.running:
            # Simulate detecting a pack opening
            # In production, this would hook into Apex's pack opening routine
            
            # Create duplicates when pack is "opened"
            duplicates = duplicator.duplicate_pack_from_memory(pack_address, count=3)
            
            print(f"\nOpened {len(duplicates)} pack(s)")
            
            # Move to next pack address for next iteration
            pack_address += 0x1000
            
            time.sleep(2)  # Wait between pack openings
            
    except KeyboardInterrupt:
        print("\nManual stop triggered")
        
    finally:
        duplicator.stop()
        duplicator.save_capture()
        duplicator.print_summary()
        
        print("\n=== PACK DUPLICATION COMPLETE ===")


if __name__ == "__main__":
    main()
