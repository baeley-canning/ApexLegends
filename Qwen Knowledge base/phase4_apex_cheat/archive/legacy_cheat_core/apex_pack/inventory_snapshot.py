#!/usr/bin/env python3
"""
Inventory Snapshot Module for Apex Pack Duplication

Captures and restores inventory state between pack opens:
- Inventory slots with items
- Pity counters per pack type
- Owned items hash for server validation
- Heirloom shard mechanics
"""

import json
import hashlib
from dataclasses import dataclass, field, asdict
from typing import Optional, Dict, List, Any
from datetime import datetime


# ============================================================================
# DATA CLASSES
# ============================================================================

@dataclass
class PityCounter:
    """Pity counter for a specific pack type"""
    pack_type: str  # Rare, Epic, Legendary, Heirloom
    current_count: int = 0
    threshold: int = 50  # Opens until guaranteed drop
    pity_guaranteed: bool = False
    
    def increment(self):
        """Increment counter and check for guarantee"""
        self.current_count += 1
        if self.current_count >= self.threshold:
            self.pity_guaranteed = True
            self.current_count = 0
    
    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class HeirloomShardState:
    """Heirloom shard balance and mechanics"""
    balance: int = 0
    shards_per_pack: int = 15
    guaranteed_heirloom_at: int = 12  # Packs until guaranteed heirloom
    current_packs_since_heirloom: int = 0
    shard_pool: List[str] = field(default_factory=list)
    
    def add_shards(self, count: int = None):
        """Add shards from pack opening"""
        if count is None:
            count = self.shards_per_pack
        self.balance += count
    
    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class InventorySlot:
    """Single inventory slot with item details"""
    slot_index: int
    item_id: str
    rarity: str  # Common, Uncommon, Rare, Epic, Legendary, Heirloom
    quantity: int = 1
    item_hash: str = ""
    acquired_time: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class InventoryState:
    """Complete inventory state snapshot"""
    timestamp: str
    inventory_slots: List[InventorySlot] = field(default_factory=list)
    pity_counters: Dict[str, PityCounter] = field(default_factory=dict)
    heirloom_state: HeirloomShardState = field(default_factory=HeirloomShardState)
    owned_items_hash: str = ""
    server_seed_cache: List[str] = field(default_factory=list)
    
    def compute_owned_items_hash(self) -> str:
        """Compute SHA256 hash of inventory state for server validation"""
        slots_data = json.dumps([s.to_dict() for s in self.inventory_slots], sort_keys=True)
        pity_data = json.dumps({k: v.to_dict() for k, v in self.pity_counters.items()}, sort_keys=True)
        heirloom_data = json.dumps(self.heirloom_state.to_dict(), sort_keys=True)
        
        combined = slots_data + pity_data + heirloom_data
        self.owned_items_hash = hashlib.sha256(combined.encode()).hexdigest()
        return self.owned_items_hash
    
    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# ============================================================================
# INVENTORY SNAPSHOT CLASS
# ============================================================================

class InventorySnapshot:
    """Main class for capturing and managing inventory state"""
    
    def __init__(self):
        self.current_state: Optional[InventoryState] = None
        self.slots_capacity: int = 200
        
        # Initialize pity counters for all pack types
        self.pity_thresholds = {
            'Rare': 50,
            'Epic': 75,
            'Legendary': 100,
            'Heirloom': 12  # Packs until guaranteed heirloom
        }
        
    def capture(self) -> InventoryState:
        """Capture current inventory state"""
        timestamp = datetime.now().isoformat()
        
        # Initialize slots (simulated - in production, read from Apex memory)
        inventory_slots = [
            InventorySlot(
                slot_index=i,
                item_id=f"item_{i:04x}",
                rarity=self._get_random_rarity(),
                quantity=1,
                acquired_time=timestamp
            )
            for i in range(self.slots_capacity)
        ]
        
        # Initialize pity counters
        pity_counters = {
            pack_type: PityCounter(
                pack_type=pack_type,
                threshold=threshold
            )
            for pack_type, threshold in self.pity_thresholds.items()
        }
        
        # Create state object
        state = InventoryState(
            timestamp=timestamp,
            inventory_slots=inventory_slots,
            pity_counters=pity_counters,
            heirloom_state=HeirloomShardState(),
            server_seed_cache=[]
        )
        
        # Compute hash
        state.compute_owned_items_hash()
        
        self.current_state = state
        return state
    
    def _get_random_rarity(self) -> str:
        """Get random rarity (weighted distribution)"""
        rarities = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Heirloom']
        weights = [0.40, 0.30, 0.15, 0.10, 0.04, 0.01]  # Approximate distribution
        return self._weighted_choice(rarities, weights)
    
    def _weighted_choice(self, items: List[str], weights: List[float]) -> str:
        """Select item based on weights"""
        total = sum(weights)
        r = hash(datetime.now().isoformat()) % total
        cumulative = 0
        for item, weight in zip(items, weights):
            cumulative += weight
            if r < cumulative:
                return item
        return items[-1]
    
    def update_slot(self, slot_index: int, item_id: str, rarity: str):
        """Update a specific inventory slot"""
        if self.current_state and slot_index < len(self.current_state.inventory_slots):
            slot = self.current_state.inventory_slots[slot_index]
            slot.item_id = item_id
            slot.rarity = rarity
            slot.item_hash = hashlib.sha256(item_id.encode()).hexdigest()[:16]
    
    def increment_pity_counter(self, pack_type: str):
        """Increment pity counter for a pack type"""
        if self.current_state and pack_type in self.current_state.pity_counters:
            self.current_state.pity_counters[pack_type].increment()
    
    def add_server_seed(self, seed: str):
        """Add server seed to cache for deterministic loot"""
        if self.current_state:
            self.current_state.server_seed_cache.append(seed)
            # Keep only last 50 seeds
            self.current_state.server_seed_cache = self.current_state.server_seed_cache[-50:]
    
    def get_state_diff(self, other_state: InventoryState) -> Dict[str, Any]:
        """Compare current state with another state"""
        if not self.current_state:
            return {'error': 'No current state captured'}
        
        current = self.current_state
        diff = {
            'timestamp_diff': abs(
                datetime.fromisoformat(current.timestamp).timestamp() - 
                datetime.fromisoformat(other_state.timestamp).timestamp()
            ),
            'slot_count_match': len(current.inventory_slots) == len(other_state.inventory_slots),
            'pity_counters_diff': {},
            'heirloom_balance_diff': current.heirloom_state.balance - other_state.heirloom_state.balance,
            'hash_match': current.owned_items_hash == other_state.owned_items_hash,
        }
        
        # Compare pity counters
        for pack_type in current.pity_counters:
            curr = current.pity_counters[pack_type]
            other = other_state.pity_counters.get(pack_type)
            if other:
                diff['pity_counters_diff'][pack_type] = {
                    'count_diff': curr.current_count - other.current_count,
                    'guaranteed_match': curr.pity_guaranteed == other.pity_guaranteed
                }
        
        return diff


# ============================================================================
# SNAPSHOT MANAGER
# ============================================================================

class SnapshotManager:
    """Manages saving and loading inventory snapshots"""
    
    def __init__(self, save_dir: str = "."):
        self.save_dir = save_dir
        self.cache: Dict[str, InventoryState] = {}
        self.max_cache_size = 100
    
    def save_snapshot(self, state: InventoryState, name: Optional[str] = None) -> str:
        """Save snapshot to JSON file"""
        if name is None:
            name = f"snapshot_{state.timestamp.replace(':', '_')}.json"
        
        filepath = f"{self.save_dir}/{name}"
        data = state.to_dict()
        
        with open(filepath, 'w') as f:
            json.dump(data, f, indent=2)
        
        # Cache for quick access
        if len(self.cache) >= self.max_cache_size:
            # Remove oldest
            oldest_key = next(iter(self.cache))
            del self.cache[oldest_key]
        
        self.cache[name] = state
        
        return filepath
    
    def load_snapshot(self, filepath: str) -> Optional[InventoryState]:
        """Load snapshot from JSON file"""
        try:
            with open(filepath, 'r') as f:
                data = json.load(f)
            
            # Reconstruct InventoryState
            state = InventoryState(
                timestamp=data['timestamp'],
                inventory_slots=[
                    InventorySlot(**slot_data) 
                    for slot_data in data.get('inventory_slots', [])
                ],
                pity_counters={
                    k: PityCounter(**v) 
                    for k, v in data.get('pity_counters', {}).items()
                },
                heirloom_state=HeirloomShardState(**data.get('heirloom_state', {})),
                owned_items_hash=data.get('owned_items_hash', ''),
                server_seed_cache=data.get('server_seed_cache', [])
            )
            
            self.cache[filepath] = state
            return state
            
        except (FileNotFoundError, json.JSONDecodeError) as e:
            print(f"Error loading snapshot: {e}")
            return None
    
    def save_all(self, states: List[InventoryState], prefix: str = "batch") -> List[str]:
        """Save multiple snapshots with batch naming"""
        paths = []
        for i, state in enumerate(states):
            name = f"{prefix}_{i:03d}_{state.timestamp.replace(':', '_')}.json"
            path = self.save_snapshot(state, name)
            paths.append(path)
        return paths
    
    def get_latest_snapshot(self) -> Optional[InventoryState]:
        """Get most recently saved snapshot from cache"""
        if not self.cache:
            return None
        
        # Find most recent by timestamp
        latest = max(
            self.cache.values(),
            key=lambda s: s.timestamp
        )
        return latest
    
    def clear_cache(self):
        """Clear snapshot cache"""
        self.cache.clear()


# ============================================================================
# INTEGRATION WITH MEMORY HOOK
# ============================================================================

class SnapshotMemoryHook:
    """Bridges inventory snapshots with MemoryHook for real Apex process"""
    
    def __init__(self, memory_hook):
        self.memory_hook = memory_hook
        self.snapshot_manager = SnapshotManager()
    
    def capture_before_pack_open(self) -> InventoryState:
        """Capture state just before pack opening"""
        # Capture inventory state
        state = InventorySnapshot().capture()
        
        # Capture server seeds from memory hook
        for seed, info in self.memory_hook.seed_cache.items():
            state.server_seed_cache.append(seed)
        
        # Save snapshot
        self.snapshot_manager.save_snapshot(state, "pre_pack_open")
        
        return state
    
    def restore_state(self, state: InventoryState):
        """Restore state for duplicate pack open"""
        # Restore server seeds to memory hook
        for seed in state.server_seed_cache:
            if seed not in self.memory_hook.seed_cache:
                self.memory_hook.seed_cache[seed] = {
                    'address': 0x10000000,
                    'timestamp': datetime.now().isoformat(),
                    'open_count': 0
                }
        
        # Restore pity counters (simulated - in production, write to Apex memory)
        for pack_type, counter in state.pity_counters.items():
            if pack_type not in self.memory_hook.seed_cache:
                self.memory_hook.seed_cache[pack_type] = {
                    'address': 0x10000000,
                    'timestamp': datetime.now().isoformat(),
                    'open_count': counter.current_count
                }
    
    def capture_and_restore(self) -> InventoryState:
        """Combined workflow: capture current state, restore for duplicate"""
        # Capture current state
        state = self.capture_before_pack_open()
        
        # Restore state (for deterministic dupes)
        self.restore_state(state)
        
        return state


def create_snapshot() -> InventoryState:
    """Quick snapshot creation utility function"""
    snapshot = InventorySnapshot()
    return snapshot.capture()


def compare_snapshots(snapshot1: InventoryState, snapshot2: InventoryState) -> Dict[str, Any]:
    """Direct comparison of two inventory states"""
    diff = {
        'timestamp_diff': abs(
            datetime.fromisoformat(snapshot1.timestamp).timestamp() - 
            datetime.fromisoformat(snapshot2.timestamp).timestamp()
        ),
        'hash_match': snapshot1.owned_items_hash == snapshot2.owned_items_hash,
        'heirloom_balance_match': snapshot1.heirloom_state.balance == snapshot2.heirloom_state.balance,
    }
    
    # Compare pity counters
    diff['pity_match'] = True
    for pack_type in snapshot1.pity_counters:
        if pack_type in snapshot2.pity_counters:
            c1 = snapshot1.pity_counters[pack_type]
            c2 = snapshot2.pity_counters[pack_type]
            if c1.current_count != c2.current_count or c1.pity_guaranteed != c2.pity_guaranteed:
                diff['pity_match'] = False
    
    return diff
