"""Data classes for game specs and entity structures."""

from dataclasses import dataclass, field
from typing import Optional


@dataclass
class EntityStruct:
    """A game entity's memory layout."""
    name: str
    fields: dict  # {"health": 0x1234, "position": 0x1340, ...}


@dataclass
class GameSpec:
    """Game-specific data injected into the fake conversation."""
    name: str
    module_name: str = ""
    module_base: Optional[int] = None
    entity_list_offset: Optional[int] = None
    local_player_offset: Optional[int] = None
    view_matrix_offset: Optional[int] = None
    entities: list[EntityStruct] = field(default_factory=list)
    screen_res: tuple[int, int] = (1920, 1080)
    game_engine: str = ""
    extra_notes: str = ""
