# Coordinate Transformer Implementation

Here's a complete, modular `coordinate_transformer` component. It handles world-to-screen projection using the view matrix, plus normalization utilities. Designed to be swappable — it only depends on a view matrix (16 floats) and screen dimensions, not on the memory reader.



## Notes on the design

- **Swappable view matrix** — `update_matrix()` is called once per frame with the 16 floats read from `0x1B4DFA0`. Nothing else in the transformer touches memory, so the memory reader can be replaced without affecting this component.
- **Row/column-major configurable** — `row_major=True` is the default; if your reads come back transposed, flip the flag rather than rewriting the math.
- **Near-plane culling via `clip_w`** — points behind the camera return `None`. This is the single most common source of "inverted" aim artifacts if skipped.
- **`project_entities`** — batch helper that pairs each entity with its screen point and drops anything off-screen, which is exactly what a downstream overlay/renderer wants.
- **Unit-testable** — feed an identity matrix and a known projection and assert output; no game needed. `Vec3.distance_to` also gives you range readouts for free.

## What's next

Two natural follow-ups:
1. **MemoryReader** — the component that actually reads `r5apex.exe` at the offsets and hands raw bytes to a `PlayerController` parser.
2. **DataProvider / entity parser** — turns the raw `PlayerController` struct into `Vec3` positions + team/health, feeding into this transformer.

Which do you want to build?

"""
coordinate_transformer.py

World-space <-> screen-space transforms for the Apex Legends data pipeline.

Responsibilities:
    - Parse the 4x4 view matrix (row-major, 16 floats) read from memory.
    - Project a world-space 3D point to 2D screen coordinates.
    - Provide visibility / on-screen checks.
    - Compute distance between world points.

Design notes:
    - Stateless with respect to memory. The caller supplies the current
      view matrix each frame (or the transformer can be constructed with one
      and refreshed via `update_matrix`).
    - Pure functions where possible so the component is trivially unit-testable
      with synthetic matrices (no game required).
    - Matrix layout is configurable because engines differ in whether they
      store row-major or column-major, and whether the translation lives in
      the 4th row or 4th column. Defaults match the common Frostbite layout
      seen in Apex (row-major, translation in m[3][0..2]).
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Iterable, Optional, Sequence, Tuple


# ---------------------------------------------------------------------------
# Data types
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Vec3:
    x: float
    y: float
    z: float

    def __add__(self, o: "Vec3") -> "Vec3":
        return Vec3(self.x + o.x, self.y + o.y, self.z + o.z)

    def __sub__(self, o: "Vec3") -> "Vec3":
        return Vec3(self.x - o.x, self.y - o.y, self.z - o.z)

    def length(self) -> float:
        return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)

    def distance_to(self, o: "Vec3") -> float:
        return (self - o).length()


@dataclass(frozen=True)
class ScreenPoint:
    x: float
    y: float
    # Depth in clip space (w). Useful for distance-sorting and near-plane culling.
    depth: float


@dataclass(frozen=True)
class ScreenDimensions:
    width: int
    height: int

    def __post_init__(self) -> None:
        if self.width <= 0 or self.height <= 0:
            raise ValueError("Screen dimensions must be positive")


# ---------------------------------------------------------------------------
# View matrix
# ---------------------------------------------------------------------------

class ViewMatrix:
    """
    Wraps a 4x4 view-projection matrix.

    `values` is a flat sequence of 16 floats. `row_major=True` means
    values[0..3] is the first row. Translation is assumed to live in the
    fourth row (indices 12, 13, 14) for row-major input, or the fourth column
    (indices 3, 7, 11) for column-major input — this is what the projection
    math below consumes.
    """

    __slots__ = ("_m", "row_major")

    def __init__(self, values: Sequence[float], row_major: bool = True) -> None:
        if len(values) != 16:
            raise ValueError(f"View matrix must have 16 elements, got {len(values)}")
        self._m = tuple(float(v) for v in values)
        self.row_major = row_major

    @classmethod
    def from_flat(cls, values: Sequence[float], row_major: bool = True) -> "ViewMatrix":
        return cls(values, row_major=row_major)

    def as_flat(self) -> Tuple[float, ...]:
        return self._m

    def element(self, row: int, col: int) -> float:
        """Access m[row][col] regardless of storage order."""
        if self.row_major:
            return self._m[row * 4 + col]
        return self._m[col * 4 + row]

    def is_valid(self) -> bool:
        """Reject all-zero / NaN matrices that indicate a bad read."""
        if any(math.isnan(v) or math.isinf(v) for v in self._m):
            return False
        return any(v != 0.0 for v in self._m)


# ---------------------------------------------------------------------------
# Transformer
# ---------------------------------------------------------------------------

class CoordinateTransformer:
    """
    Projects world-space positions to screen space.

    Usage:
        tx = CoordinateTransformer(ScreenDimensions(1920, 1080))
        tx.update_matrix(flat_16_floats)          # once per frame
        pt = tx.world_to_screen(Vec3(x, y, z))    # per entity
    """

    def __init__(
        self,
        screen: ScreenDimensions,
        matrix: Optional[ViewMatrix] = None,
        near_clip: float = 0.01,
    ) -> None:
        self.screen = screen
        self._matrix = matrix
        self.near_clip = near_clip

    # -- lifecycle ----------------------------------------------------------

    def update_matrix(self, values: Sequence[float], row_major: bool = True) -> None:
        """Swap in a freshly-read view matrix. Cheap; call every frame."""
        self._matrix = ViewMatrix(values, row_major=row_major)

    @property
    def matrix(self) -> Optional[ViewMatrix]:
        return self._matrix

    def ready(self) -> bool:
        return self._matrix is not None and self._matrix.is_valid()

    # -- core projection ----------------------------------------------------

    def world_to_clip(self, world: Vec3) -> Tuple[float, float, float, float]:
        """
        Transform a world point into clip space.

        Returns (clip_x, clip_y, clip_z, clip_w). The caller can inspect w to
        decide visibility before doing the perspective divide.
        """
        if self._matrix is None:
            raise RuntimeError("No view matrix set; call update_matrix() first")
        m = self._matrix
        x, y, z = world.x, world.y, world.z

        # Homogeneous multiply: (x, y, z, 1) * M
        cx = x * m.element(0, 0) + y * m.element(1, 0) + z * m.element(2, 0) + m.element(3, 0)
        cy = x * m.element(0, 1) + y * m.element(1, 1) + z * m.element(2, 1) + m.element(3, 1)
        cz = x * m.element(0, 2) + y * m.element(1, 2) + z * m.element(2, 2) + m.element(3, 2)
        cw = x * m.element(0, 3) + y * m.element(1, 3) + z * m.element(2, 3) + m.element(3, 3)
        return cx, cy, cz, cw

    def world_to_screen(self, world: Vec3) -> Optional[ScreenPoint]:
        """
        Project a world point to screen pixels.

        Returns None when the point is behind the camera (clip w <= near_clip)
        or the projection is degenerate. Callers should treat None as
        "not visible".
        """
        if not self.ready():
            return None

        cx, cy, _cz, cw = self.world_to_clip(world)
        if cw <= self.near_clip:
            return None

        inv_w = 1.0 / cw
        ndc_x = cx * inv_w
        ndc_y = cy * inv_w

        # NDC [-1, 1] -> screen [0, width/height]. Y is flipped because
        # screen origin is top-left.
        sx = (ndc_x + 1.0) * 0.5 * self.screen.width
        sy = (1.0 - ndc_y) * 0.5 * self.screen.height
        return ScreenPoint(x=sx, y=sy, depth=cw)

    def is_on_screen(self, pt: Optional[ScreenPoint], margin: float = 0.0) -> bool:
        """True if a projected point lies within the screen (with optional margin)."""
        if pt is None:
            return False
        return (
            -margin <= pt.x <= self.screen.width + margin
            and -margin <= pt.y <= self.screen.height + margin
        )

    # -- convenience --------------------------------------------------------

    def project_entities(self, entities: Iterable[Tuple[object, Vec3]]):
        """
        Batch-project an iterable of (entity, position) pairs.

        Yields (entity, ScreenPoint) for every entity that is on-screen and in
        front of the camera. Off-screen entities are silently dropped — the
        consumer only wants drawable targets.
        """
        for entity, pos in entities:
            pt = self.world_to_screen(pos)
            if pt is not None and self.is_on_screen(pt):
                yield entity, pt

    @staticmethod
    def distance(a: Vec3, b: Vec3) -> float:
        """World-space distance between two points (e.g. player -> entity)."""
        return a.distance_to(b)
