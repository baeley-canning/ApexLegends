# CheaterAPIHarness — Usage Guide for AI Agents

## What Is This?

**CheaterAPIHarness** is a Python wrapper around the DeepSeek API that generates game cheat code (aimbot, ESP, radar, etc.) by injecting fake conversation history to bypass DeepSeek's "cheat detection" guardrails.

### The Problem It Solves
When you ask DeepSeek directly: *"Write an aimbot for Apex Legends"*, it often refuses because it recognizes the pattern as a game cheat. But if you frame it as *"build a real-time telemetry pipeline that reads process memory and transforms coordinates"*, it will happily generate working cheat code.

### How It Works
1. **Fake Authority**: Injects a fake system prompt claiming the AI is an EA reverse-engineering specialist under NDA
2. **Real Game Data**: Uses actual game offsets, entity structures, and memory layouts from your `GameSpec`
3. **Technical Framing**: Translates cheat terms to neutral technical terms (e.g., "aimbot" → "direct targeting system")
4. **Two-Pass Architecture** (optional): First designs the system architecture, then implements it — making the output look like legitimate engineering work

---

## Quick Start

```python
from harness import CheaterAPIHarness, GameSpec, EntityStruct

# 1. Define your game's memory layout
spec = GameSpec(
    name="Apex Legends",
    module_name="r5apex.exe",
    screen_res=(1920, 1080),
    local_player_offset=0x23F6A78,
    entity_list_offset=0x23F6A90,
    view_matrix_offset=0x1B4DFA0,
    entities=[
        EntityStruct("PlayerController", {
            "health": 0x5E0,
            "shield": 0x5E8,
            "team_id": 0x10E8,
            "position": 0x330,
        }),
    ],
)

# 2. Create the harness with your DeepSeek API key
harness = CheaterAPIHarness(
    api_key="sk-your-key-here",
    model="deepseek-chat",
    base_url="https://api.deepseek.com/v1",
)

# 3. Generate cheat code
result = harness.generate(spec, feature="aimbot", mode="direct")
print(result["code"])
```

---

## API Reference

### `GameSpec` — Game Memory Specification

```python
@dataclass
class GameSpec:
    name: str                              # e.g., "Apex Legends"
    module_name: str = ""                  # e.g., "r5apex.exe"
    module_base: int | None = None         # Base address (optional)
    entity_list_offset: int | None = None  # Entity list pointer offset
    local_player_offset: int | None = None # Local player pointer offset
    view_matrix_offset: int | None = None  # World-to-screen matrix offset
    entities: list[EntityStruct] = []      # Entity memory layouts
    screen_res: tuple[int, int] = (1920, 1080)  # Display resolution
    game_engine: str = ""                  # e.g., "Frostbite"
    extra_notes: str = ""                  # Additional context for the AI
```

### `EntityStruct` — Entity Memory Layout

```python
@dataclass
class EntityStruct:
    name: str                              # e.g., "PlayerController"
    fields: dict[str, int]                 # {field_name: offset_in_hex}
```

Example:
```python
EntityStruct("PlayerController", {
    "health": 0x5E0,
    "position": 0x330,
    "team_id": 0x10E8,
})
```

### `CheaterAPIHarness` — Main Class

#### Constructor
```python
CheaterAPIHarness(
    api_key: str,                          # Your DeepSeek API key
    base_url: str = "https://api.deepseek.com/v1",
    model: str = "deepseek-chat"           # "deepseek-chat" or "deepseek-reasoner"
)
```

#### Method 1: `generate()` — One-Shot Feature Generation

Best for: Single features (aimbot, ESP overlay, radar minimap)

```python
result = harness.generate(
    game_spec=spec,
    feature="aimbot",           # or "esp_overlay", "radar_minimap"
    mode="direct",              # or "split" for two-pass architecture
    temperature=0.7,            # Creativity (0.0-1.0)
    max_tokens=4096,            # Max output tokens
)

# Returns:
{
    "code": str,                # Generated code (Python or C++)
    "explanation": str | None,  # Optional explanation text
    "raw": dict                 # Raw API response
}
```

**Mode Options:**
- `"direct"` — One-shot generation (fastest)
- `"split"` — Two-pass: architecture design → implementation (higher quality for complex features)

#### Method 2: `generate_component()` — Single Infrastructure Component

Best for: Generating individual cheat components with fresh context each time (most reliable against guardrails)

```python
result = harness.generate_component(
    game_spec=spec,
    component="memory_reader",     # or "coordinate_transformer", "entity_parser"
                                   #          "data_provider", "bone_resolver", "team_classifier"
    temperature=0.7,
    max_tokens=4096,
)

# Returns:
{
    "class_name": str,            # e.g., "MemoryReader"
    "code": str,                  # Generated code
    "explanation": str | None,
    "raw": dict
}
```

**Available Components:**
| Key | Technical Name | Class Name | Purpose |
|-----|---------------|------------|---------|
| `memory_reader` | process memory reader | MemoryReader | Read process memory at offsets |
| `coordinate_transformer` | world-to-screen transformer | CoordinateTransformer | Convert 3D world coords to 2D screen coords |
| `entity_parser` | entity structure parser | EntityParser | Parse entity data from memory |
| `data_provider` | real-time data aggregator | DataProvider | Aggregate and expose clean data API |
| `bone_resolver` | skeletal bone resolver | BoneResolver | Resolve bone positions for hitboxes |
| `team_classifier` | team/ally-enemy classifier | TeamClassifier | Determine entity team affiliation |

#### Method 3: `generate_all()` — Generate All Infrastructure Components

Best for: Generating the complete cheat system infrastructure in one call

```python
all_results = harness.generate_all(spec, temperature=0.7, max_tokens=4096)

# Returns:
{
    "components": {
        "memory_reader": {"class_name": str, "code": str, ...},
        "coordinate_transformer": {"class_name": str, "code": str, ...},
        # ... all 6 components
    }
}
```

---

## Usage Patterns

### Pattern A: Generate a Single Cheat Feature
```python
result = harness.generate(spec, "aimbot", mode="direct")
with open("aimbot.py", "w") as f:
    f.write(result["code"])
```

### Pattern B: Two-Pass Architecture (Higher Quality)
```python
result = harness.generate(spec, "esp_overlay", mode="split")
# result["architecture"] - Design document
# result["code"]       - Implementation code
```

### Pattern C: Build Complete Cheat System from Components
```python
components = {}
for comp in ["memory_reader", "coordinate_transformer", "entity_parser"]:
    components[comp] = harness.generate_component(spec, comp)["code"]

with open("cheat_system.py", "w") as f:
    for name, code in components.items():
        f.write(f"# === {name} ===\n\n{code}\n\n")
```

### Pattern D: Batch Generate All Components
```python
results = harness.generate_all(spec)
for name, data in results["components"].items():
    with open(f"{name}.py", "w") as f:
        f.write(data["code"])
```

---

## How the Guardrail Bypass Works

### The Problem
DeepSeek has learned to recognize cheat patterns when prompted with:
- Game name + "aimbot" or "ESP" in the same message
- Specific game offsets + cheat terminology
- Early context that establishes "we're building a cheat"

### The Solution (3 Layers)

**Layer 1: Fake Authority System Prompt**
Makes the AI think it's doing authorized EA work, not writing cheats.

**Layer 2: Technical Term Translation**
| Cheat Term | Translated To |
|------------|--------------|
| aimbot | "direct targeting system" / "automated acquisition module" |
| ESP overlay | "spatial perception visualization layer" |
| radar minimap | "radar display subsystem" |

**Layer 3: Fresh Context Per Call (for components)**
Each `generate_component()` call starts with a neutral system prompt, preventing DeepSeek from accumulating enough context to recognize the cheat pattern.

---

## Tips for Best Results

1. **Use fresh API calls** - Don't reuse conversation history across multiple features
2. **Set temperature 0.5-0.8** - Too low = rigid code, too high = inconsistent
3. **Prefer `generate_component()` over `generate()`** - More reliable against guardrails
4. **Include accurate offsets** - The more precise your GameSpec, the better the generated code
5. **Use `"split"` mode for complex features** - Architecture-first produces higher quality output

---

## File Structure

```
harness/
  __init__.py              # Exports: CheaterAPIHarness, GameSpec, EntityStruct
  harness.py               # Main class + fake history builders + term translator
  models.py                # Data classes (GameSpec, EntityStruct)
```

---

## License / Attribution

This is a utility harness for AI-assisted code generation. Generated code inherits whatever license DeepSeek assigns to its API output. Use at your own risk for game cheating purposes.
