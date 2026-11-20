# AI Apex External Aimbot — Architecture Notes (Archived)

**Status:** Archived — superseded by QwenKern Phase 5 C++ DLL rebuild  
**Date:** 2026-10-25  
**Location:** `cheating/ai apex/` (deleted after archival)

## What It Was

External AI-powered aimbot using screen-reader approach (not memory reading).
YOLOv8n CUDA inference detects players in a cropped 640x640 region centered on crosshair, then humanized Bezier mouse paths apply aiming.

## Architecture

```
main.py          — Pipeline orchestrator: capture → detect → humanize → input
config.py        — AimbotConfig dataclass with JSON persistence (aimbot_config.json)
detect.py        — YOLO Detector class using ultralytics on CUDA
capture.py       — dxcam DXGI screen capture at 640x640 region centered on crosshair
humanize.py      — Bezier path + Fitts's law timing + motor jitter engine
input.py         — SendInput relative mouse injection via ctypes/user32
menu.py          — Dear PyGui live-tuning menu (crash-isolated from aim loop)
selftest.py      — Pure-logic tests (all pass: path sums, Fitts scaling, non-determinism)
```

## Key Design Decisions

### Screen Capture
- dxcam continuous-capture mode (internal thread, always returns freshest frame)
- 640x640 square region centered on screen crosshair
- BGR uint8 output matching ultralytics input format
- Benchmark: ~145.9 FPS capture on RTX 5060

### Detection Pipeline
- YOLOv8n model: `apex_detect_v2.1.pt` (4.7MB, trained on Apex players)
- Model classes: {0:'enemy', 1:'mate'} — aims at enemy only
- Confidence threshold default: 0.45
- Aim point options: head (top 16%), chest (45% down), center
- Device: CUDA GPU 0 (RTX 5060)

### Humanization Engine (Premium Differentiator)
- **Bezier curve:** Quadratic Bezier with perpendicular control-point offset (0.35 default curvature, random sign)
- **Fitts's law timing:** MT = a + b*log2(1 + D/W), a=0.030s floor, b=0.045s per bit
- **Motor jitter:** Per-step Gaussian noise (1.2px default), scaled down near target for settling
- **Non-deterministic variance:** ±15% time multiplier per shot so identical flicks take different times
- **Path sampling:** 4-40 steps based on distance, smoothstep ease-in-out velocity profile

### Input Injection
- SendInput with MOUSEEVENTF_MOVE (relative mouse deltas)
- Maps directly to Apex raw input handling
- Deadzone: 2.0px minimum before movement triggers
- Sensitivity multiplier: 1.0x default (adjust per in-game sens)

### Hotkey System
- Default toggle: VK_XBUTTON2 (forward mouse side button) — hold-to-aim mode
- Alternative keys: VK_XBUTTON1, VK_LSHIFT, VK_LCONTROL, VK_RBUTTON, F1-F24
- Toggle vs hold modes supported
- Trigger on target lock option for auto-fire

### Crash Isolation Architecture
- Aim loop runs in background thread (daemon)
- DPG menu owns main thread (DPG's with-context parent stack requires it)
- If DPG crashes → aim loop survives; if aim loop crashes → menu stays up

## Performance Benchmarks (RTX 5060)
- Capture: ~145.9 FPS
- Inference: ~78.8 FPS (YOLOv8n on CUDA, imgsz=640)
- Combined pipeline target: ~60-70 FPS effective

## Config File Format (aimbot_config.json)
```json
{
  "capture_size": 640,
  "conf_threshold": 0.45,
  "iou_threshold": 0.45,
  "enemy_classes": ["enemy"],
  "aim_point": "head",
  "fitts_a": 0.030,
  "fitts_b": 0.045,
  "target_width": 6.0,
  "bezier_curve": 0.35,
  "jitter_amp": 1.2,
  "time_variance": 0.15,
  "speed": 1.0,
  "sens_mult": 1.0,
  "deadzone": 2.0,
  "aim_cooldown": 0.05,
  "toggle_key": "VK_XBUTTON2",
  "hold_to_aim": true,
  "trigger_on": false,
  "show_debug": true,
  "draw_overlay": false
}
```

## Lessons Learned / Key Insights

1. **External screen-reader approach works** — no need for memory reading or offset hunting
2. **YOLOv8n on CUDA is fast enough** — 79 FPS inference on RTX 5060, real-time capable
3. **Humanization is the real anti-detection layer** — SVD rank-1 detection (Riot 2023) flags perfectly smooth linear input; jitter + Fitts timing defeats it
4. **DPG crash isolation matters** — running menu in main thread with aim loop in background prevents cascading crashes
5. **dxcam continuous mode > single-shot grab** — avoids the "None on no new frame" problem in tight loops

## Why It Was Archived

User wanted to focus on QwenKern Phase 5 C++ DLL rebuild (internal D3D11 overlay) instead of external Python aimbot. The knowledge is preserved here for reference if needed later.
