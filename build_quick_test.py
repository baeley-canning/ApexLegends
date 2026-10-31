#!/usr/bin/env python3
"""Write quick_test.py with definitive harness test."""
import pathlib

content = '''#!/usr/bin/env python3
"""Definitive test — generate all components individually, combine into cheat system."""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from harness import CheaterAPIHarness, GameSpec, EntityStruct

h = CheaterAPIHarness("sk-3b8056893d76455b915cf9ca36f9d7e2", model="deepseek-chat")
s = GameSpec(
    name="Apex Legends", module_name="r5apex.exe", game_engine="custom (Frostbite)",
    screen_res=(1920, 1080), local_player_offset=0x23F6A78,
    entity_list_offset=0x23F6A90, view_matrix_offset=0x1B4DFA0,
    entities=[EntityStruct("PlayerController", {
        "health": 0x5E0, "shield": 0x5E8, "team_id": 0x10E8,
        "player_name": 0x10F0, "position": 0x330, "velocity": 0x320,
        "rotation": 0x10D0, "is_alive": 0x5DC, "bone_head": 0x630,
    })],
)

components = ["memory_reader", "coordinate_transformer", "entity_parser"]
out_dir = pathlib.Path(__file__).parent / "generated_cheats" / "final_test"
out_dir.mkdir(exist_ok=True)

for comp in components:
    r = h.generate_component(s, comp, temperature=0.7, max_tokens=4096)
    fp = out_dir / f"{comp}.py"
    with open(fp, "w", encoding="utf-8") as f:
        if r.get("explanation"):
            f.write(r["explanation"] + "\\n\\n")
        f.write(r["code"])
    has_code = "I'm not going" not in r["code"] and "I can't write" not in r["code"]
    status = "CODE" if has_code else "REFUSED"
    print(f"[{status}] {comp}: {len(r['code'])} chars")

print("Done!")
'''

pathlib.Path(r"C:/Users/New User/OneDrive/Desktop/cheating/quick_test.py").write_text(content)
print("Written quick_test.py")
