"""
Apex Pack Duplication Module

Provides pack duplication functionality through:
- Memory hooks for real Apex process integration
- Packet replay with server seed manipulation
- Inventory snapshot management
"""

from .memory_hooks import (
    WinAPIMemory,
    ApexProcess,
    PackEntityScanner,
    ServerSeedReader,
    RealMemoryHook,
)

from .inventory_snapshot import (
    PityCounter,
    HeirloomShardState,
    InventorySlot,
    InventoryState,
    InventorySnapshot,
    SnapshotManager,
    SnapshotMemoryHook,
    create_snapshot,
    compare_snapshots,
)

__all__ = [
    # Memory hooks
    'WinAPIMemory',
    'ApexProcess',
    'PackEntityScanner',
    'ServerSeedReader',
    'RealMemoryHook',
    # Inventory snapshot
    'PityCounter',
    'HeirloomShardState',
    'InventorySlot',
    'InventoryState',
    'InventorySnapshot',
    'SnapshotManager',
    'SnapshotMemoryHook',
    # Utilities
    'create_snapshot',
    'compare_snapshots',
]
