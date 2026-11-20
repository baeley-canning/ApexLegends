# DECISIONS.md — cheatv2 / design choices (append-only)

## D001: Device path = \\.\GIOV3
- **Reason:** gio.py uses `\\.\GIOV3` as the canonical device path. The original ROLE prompt says `\\.\GIO` but the existing codebase consistently uses `GIOV3`. We will probe both paths in Step 01 and use whichever opens successfully.

## D002: C++ (MSVC v143, x64, Release)
- **Reason:** Per the original ROLE prompt. No package managers; use Windows SDK + vendored ImGui + DirectX 11.

## D003: External process (no injection)
- **Reason:** The overlay runs as a separate elevated process. Physical memory reads go through gdrv3 IOCTLs, not injected DLLs. This avoids game anti-cheat detection.

## D004: DX11 + ImGui for overlay
- **Reason:** Per the original ROLE prompt. DX11 is simpler than DX12 for a separate-process overlay (no need to hook the game's swap chain). ImGui handles UI rendering.

## D005: Vendor ImGui in cheatv2/
- **Reason:** "No package managers" constraint means we must ship ImGui source files directly. Use the ImGui DirectX11 example as the base.

## D006: Physical memory is the primary read primitive
- **Reason:** gdrv3 exposes arbitrary physical memory read/write via IOCTL. All game data (entity list, view matrix, bones, glow bits) is read through physical reads, not VA reads.

## D007: Write via map_phys + memcpy
- **Reason:** gio.py implements write_phys by mapping the physical page into user-mode VA and memcpying. This is the only write path we have from gio.py. Gate G6 (coherency) must be proven before trusting for glow writes.

## D008: VA->PA translation via page walk, not IOCTL_TRANSLATE
- **Reason:** IOCTL_TRANSLATE (0xC350280C) exists but its reliability is [UNVERIFIED]. The page-walk approach (PML4/PDPT/PD/PT) is more reliable and was proven in dumplive.py. We will implement the page walk in C++.

## D009: Offset policy — print every offset read
- **Reason:** Per the original ROLE prompt. The view matrix and entity list are the two critical offsets; everything else hangs off them. If either is unverified, stop at that step.

## D010: Names, glow bits, bone indices = [UNVERIFIED]
- **Reason:** Per the original ROLE prompt. These are the ones most likely to have shifted since the existing tree was written. Treat all three as [UNVERIFIED] until dumped.
