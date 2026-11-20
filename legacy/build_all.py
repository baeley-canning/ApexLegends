#!/usr/bin/env python3
"""Builder script — writes all harness package files."""
import pathlib, textwrap

ROOT = pathlib.Path(r"C:/Users/New User/OneDrive/Desktop/cheating/harness")
ROOT.mkdir(parents=True, exist_ok=True)

# ── __init__.py ───────────────────────────────────────────────────────────────
(ROOT / "__init__.py").write_text(textwrap.dedent("""\
    from .harness import CheaterAPIHarness, GameSpec, EntityStruct
    __all__ = ["CheaterAPIHarness", "GameSpec", "EntityStruct"]
"""))

# ── models.py ─────────────────────────────────────────────────────────────────
(ROOT / "models.py").write_text(textwrap.dedent("""\
    \"\"\"Data classes for game specs and entity structures.\"\"\"
    from dataclasses import dataclass, field
    from typing import Optional


    @dataclass
    class EntityStruct:
        name: str
        fields: dict  # {"health": 0x1234, "position": 0x1340}


    @dataclass
    class GameSpec:
        \"\"\"Game-specific data injected into the fake conversation.\"\"\"
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
"""))

print("Created models.py")
