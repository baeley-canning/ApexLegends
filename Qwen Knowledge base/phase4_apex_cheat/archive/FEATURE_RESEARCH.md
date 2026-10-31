# Feature Research: Triggerbot Humanization, Legend-Adaptive Aimbot, ESP Rendering

## Executive Summary

This document provides in-depth research on three critical feature areas for Apex Legends cheats:
1. **Triggerbot with Humanized Delays** (50-150ms reaction time simulation)
2. **Legend-Adaptive Aimbot** (hitbox/FOV adjustments per legend)
3. **ESP Rendering Patterns** (boxes, skeletons, health bars, glow effects)

Research sources: Kernaim, Ignite, Chudvision, TATEWARE, MadChad

---

## 1. Triggerbot with Humanized Delays

### Overview
Triggerbot is described as the "sleeper feature" for Apex Legends - arguably the safest aim-assist option available.

### How Triggerbot Works
Instead of moving your crosshair to the enemy (aimbot), triggerbot fires automatically when your crosshair passes over an enemy. You still aim manually, which looks completely natural in spectator mode and kill cams.

### Key Implementation Details

**Reaction Time Simulation:**
- **Base delay range**: 50-150ms (mimics human reaction time)
- **Detection avoidance**: Instant trigger (0ms) is detectable through reaction-time analysis
- **Weapon-specific tuning**: Different delays per weapon type

**Weapon-Type Adjustments:**

| Weapon Type | Recommended Delay | Rationale |
|-------------|-------------------|-----------|
| **Shotguns** | 50-80ms | Timing matters less than placement; faster response acceptable |
| **Automatic** (R-301, R-99) | 80-120ms | Sustained fire allows moderate delay |
| **Semi-auto** (Wingman, Sentinel) | 100-150ms | Precision timing benefits from human-like delays |

### Implementation Pattern

```python
# Pseudo-code for humanized triggerbot
class HumanizedTriggerbot:
    def __init__(self, base_delay_ms=100, jitter_ms=30):
        self.base_delay = base_delay_ms
        self.jitter = jitter_ms
        self.last_trigger_time = 0
    
    def should_fire(self, target_position, current_time):
        """Determine if crosshair is over enemy and delay has elapsed."""
        if self._is_crosshair_over_target(target_position):
            delay = self.base_delay + random.randint(-self.jitter, self.jitter)
            
            if current_time - self.last_trigger_time > (delay / 1000.0):
                self.last_trigger_time = current_time
                return True
        return False
    
    def get_weapon_delay(self, weapon_name):
        """Get weapon-specific base delay."""
        weapon_delays = {
            'peacekeeper': 65,
            'mastiff': 70,
            'wingman': 120,
            'r-301': 95,
            'r-99': 90,
            'car': 85,
        }
        return weapon_delays.get(weapon_name, 100)
```

### Detection Risk Assessment

| Aspect | Risk Level | Notes |
|--------|------------|-------|
| **Reaction time analysis** | Medium | Must vary delays to avoid detection patterns |
| **Spectator mode** | Low | Natural-looking fire patterns |
| **Kill cam analysis** | Low | Human-like timing patterns |
| **Server-side validation** | Low-Medium | Depends on how server validates fire events |

---

## 2. Legend-Adaptive Aimbot

### Overview
Apex has a diverse roster of legends with different hitbox sizes, movement speeds, and abilities that affect aiming. The best aimbot implementations adjust FOV, target bone, and smoothing based on which legend the enemy is playing.

### Legend Hitbox Analysis

| Legend | Hitbox Size | Optimal Target Bone | Recommended FOV |
|--------|-------------|---------------------|-----------------|
| **Wraith** | Small | Head/Neck | Tight (3-5°) |
| **Lifeline** | Medium | Head/Chest | Moderate (5-7°) |
| **Gibraltar** | Large | Chest/Body | Loose (7-10°) |
| **Newcastle** | Large | Chest/Body | Loose (8-12°) |
| **Bangalore** | Medium | Head/Chest | Moderate (5-8°) |
| **Caustic** | Medium | Head/Chest | Moderate (6-9°) |
| **Mirage** | Medium | Head/Chest | Moderate (5-7°) |
| **Octavia** | Medium | Head/Chest | Moderate (5-7°) |
| **Valkyrie** | Medium | Head/Neck | Moderate (5-8°) |
| **Crypto** | Small-Medium | Head/Neck | Tight (4-6°) |

### Weapon-Specific Profiles

The best cheats implement weapon-specific aimbot profiles:

| Weapon | FOV | Smoothing | Target Bone | Flick Speed |
|--------|-----|-----------|-------------|-------------|
| **Wingman** | Tight (3-5°) | Low | Head | Fast, precise |
| **R-301** | Moderate (5-7°) | Medium | Head/Chest | Smooth tracking |
| **Shotguns** | Loose (6-9°) | Low | Chest/Body | Fast acquisition |
| **R-99** | Tight (4-6°) | High | Head | Tight tracking |
| **Kraber** | Tight (3-5°) | Low-Medium | Head | Precise flicks |
| **Sentinel** | Moderate (5-7°) | Medium | Head/Chest | Balanced |

### Implementation Pattern

```python
# Pseudo-code for legend-adaptive aimbot
class LegendAdaptiveAimbot:
    def __init__(self):
        self.legend_configs = {
            'wraith': {'fov': 4, 'smoothing': 0.3, 'bone': 'head'},
            'lifeline': {'fov': 6, 'smoothing': 0.4, 'bone': 'chest'},
            'gibraltar': {'fov': 9, 'smoothing': 0.5, 'bone': 'chest'},
            'newcastle': {'fov': 10, 'smoothing': 0.6, 'bone': 'chest'},
            # ... other legends
        }
        
        self.weapon_configs = {
            'wingman': {'fov': 4, 'smoothing': 0.2, 'flick_speed': 0.8},
            'r-301': {'fov': 6, 'smoothing': 0.5, 'flick_speed': 0.6},
            # ... other weapons
        }
    
    def get_target_settings(self, enemy_legend, weapon):
        """Get optimal settings for target."""
        legend_cfg = self.legend_configs.get(enemy_legend, {})
        weapon_cfg = self.weapon_configs.get(weapon, {})
        
        return {
            'fov': max(legend_cfg.get('fov', 5), weapon_cfg.get('fov', 5)),
            'smoothing': max(legend_cfg.get('smoothing', 0.4), 
                            weapon_cfg.get('smoothing', 0.4)),
            'bone': legend_cfg.get('bone', 'head'),
        }
```

### Detection Risk Assessment

| Aspect | Risk Level | Notes |
|--------|------------|-------|
| **FOV variation** | Low | Natural variation across legends |
| **Bone targeting** | Low-Medium | Headshots may attract more attention |
| **Smoothing patterns** | Medium | Must vary smoothing to avoid detection |
| **Legend-specific behavior** | Low | Shows intelligent, adaptive aim |

---

## 3. ESP Rendering Patterns

### Overview
Apex ESP needs to go beyond basic enemy boxes. The most useful implementations display real-time distance, movement direction, health/shield levels, legend identification, weapon loadout, knocked player locations, and death box locations.

### Essential ESP Elements

**Player ESP:**
- Box (2D/3D) around enemies
- Skeleton/bone structure
- Player name and legend
- Distance indicator
- Health and shield bars
- Knocked status indicator
- Weapon icon/loadout
- Ability cooldowns

**Loot ESP:**
- Ammo boxes
- Armor plates
| Item | Type | Details |
|------|------|---------|
| **Ammo** | Box, Icon | Show full/empty status |
| **Armor** | Box, Icons | Show plate count and types |
| **Health** | Box, Icon | Show medkit/kit type |
| **Shield** | Box, Icon | Show shield battery type |
| **Legendaries** | Glow, Icon | Highlight rare items |

### Visual Styles Compared

**Kernaim ESP:**
- Clean boxes with subtle borders
- Minimalist icons
- Clear health/shield bars
- Smooth opacity transitions

**Ignite ESP:**
- Frame-perfect rendering
- Minimal FPS impact
- Configurable element visibility
- "Seer style" HP/armor display

**Chudvision ESP:**
- ImGui-based rendering
- Highly customizable
- Glow effects on enemies
- Smooth animations

### Implementation Pattern

```python
# Pseudo-code for ESP rendering
class ESPRenderer:
    def __init__(self, canvas):
        self.canvas = canvas
        self.enabled_features = {
            'boxes': True,
            'skeletons': True,
            'names': True,
            'health_bars': True,
            'glow': True,
            'distance': True,
        }
    
    def render_player(self, player_data):
        """Render a single player with all ESP elements."""
        if not self.enabled_features['boxes']:
            return
        
        # Draw box
        self._draw_box(player_data)
        
        # Draw skeleton if enabled
        if self.enabled_features['skeletons']:
            self._draw_skeleton(player_data)
        
        # Draw name and legend
        if self.enabled_features['names']:
            self._draw_name(player_data)
        
        # Draw health/shield bars
        if self.enabled_features['health_bars']:
            self._draw_health_bars(player_data)
        
        # Draw glow effect
        if self.enabled_features['glow']:
            self._draw_glow(player_data)
    
    def _draw_health_bars(self, player):
        """Draw health and shield bars."""
        # Health bar (green)
        health_pct = player.health / player.max_health
        self.canvas.draw_rect(
            x=player.x - 20,
            y=player.y + 30,
            width=40 * health_pct,
            height=6,
            color=(0, 255, 0),
        )
        
        # Shield bar (blue)
        if player.shield > 0:
            shield_pct = player.shield / player.max_shield
            self.canvas.draw_rect(
                x=player.x - 20,
                y=player.y + 37,
                width=40 * shield_pct,
                height=6,
                color=(0, 150, 255),
            )
```

### Detection Risk Assessment

| Aspect | Risk Level | Notes |
|--------|------------|-------|
| **Overlay rendering** | Low-Medium | External overlays detected within minutes |
| **Element count** | Low | More elements = more detectable patterns |
| **Glow effects** | Medium | Glow can be flagged as suspicious |
| **Update frequency** | Low-Medium | High refresh rates may attract attention |

---

## Implementation Recommendations for Phase 4

### Priority 1: Triggerbot Humanization
- Implement 50-150ms randomized delay
- Add weapon-specific delay tuning
- Include reaction time analysis evasion

### Priority 2: Legend-Adaptive Aimbot
- Create legend configuration dictionary
- Implement weapon-specific profiles
- Add FOV/smoothing/bone targeting per legend

### Priority 3: ESP Rendering
- Start with clean box rendering (Kernaim style)
- Add health/shield bars
- Consider glow effects (Chudvision style)
- Include distance and legend indicators

---

*Feature Research Document Created: October 13, 2026*
