r"""qk_live.py -- the range session: live boxes + a menu, in ONE process.

Why one process: every earlier attempt had three moving parts (a python producer,
a file or shared mapping, a C++ reader), and the failure mode was always the same
shape -- the matrix and the entity positions came from different instants, so the
boxes slid off a moving dummy, or a stale file made them vanish.  Here the matrix
and the records are read in the SAME loop iteration, projected by the same maths,
and drawn by the same process: "off by one frame" cannot happen by construction.

What it reads (all physical, no driver, no DTB, no attach):

  matrix   image_pa + vp_rva   from temp\\qk_offsets.txt (the boot's own record)
  entities 0xC0 bytes at each census PA from temp\\_p134_out.txt

Both are guarded by the RAM map's interval set (R10 : a physical read outside it
is how the box bugchecked on 07/11).

What it draws: a click-through, colour-keyed, topmost layered window covering the
game's client area; boxes on the census entities; a menu whose toggles change what
is drawn and whose state survives a restart (temp\\qk_live_cfg.txt).

usage:
  python ext\qk_live.py --fake [--seconds=20]   no game, no driver, no elevation
  python ext\qk_live.py --check                 live read-back, ~3 s, needs elevation
  python ext\qk_live.py --run [--hz=20] [--seconds=0] [--wide]
  python ext\qk_live.py --wide                  also try matrix windows +-0x1000

verdicts go to temp\\qk_live_out.txt (append-only per run, prefixed by mode), the
one-line live feed to temp\\qk_live_status.txt, so the state is a file, not a
screenshot someone has to squint at (R3).
"""
import ctypes
import ctypes.wintypes as wt
import math
import os
import re
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

TMP = os.path.join(ROOT, "temp")
OFFS = os.path.join(TMP, "qk_offsets.txt")
CENSUS = os.path.join(TMP, "_p134_out.txt")
OUT = os.path.join(TMP, "qk_live_out.txt")
STATUS = os.path.join(TMP, "qk_live_status.txt")
CFG = os.path.join(TMP, "qk_live_cfg.txt")

# --- what a box is -----------------------------------------------------------
HEAD_Z = 72.0                 # head offset above the origin, Apex world units
BOX_W = 0.55                  # box width as a fraction of its height
BOX_MAX_W = 420.0
SEED_BYTES = 0xC0             # a census record; positions() needs this much
SEED_TRIPLE = (0, 1, 2)       # the layout _mk20 pinned on 09/11 14:55 (contig)

# --- colours (COLORREF = 0x00BBGGRR) ----------------------------------------
SCHEMES = (
    ("cyan",   0x00FFFF00, 0x00C0C000),
    ("green",  0x0000FF40, 0x0000C030),
    ("red",    0x004040FF, 0x003030C0),
    ("magenta",0x00FF40FF, 0x00C030C0),
)
KEY_BLACK = 0x00000000        # colorkey: this exact colour is transparent

_logf = None


def out(s=""):
    line = str(s)
    print(line)
    if _logf is not None:
        _logf.write(line + "\n")
        _logf.flush()


def status(s):
    try:
        with open(STATUS, "w", encoding="utf-8") as f:
            f.write(s + "\n")
    except OSError:
        pass


def arg(name, default=None, cast=str):
    for i, a in enumerate(sys.argv):
        if a == "--" + name and i + 1 < len(sys.argv):
            return cast(sys.argv[i + 1])
        if a.startswith("--" + name + "="):
            return cast(a.split("=", 1)[1])
    return default


def flag(name):
    return ("--" + name) in sys.argv


def now():
    return time.strftime("%H:%M:%S")


def _key(argname, default):
    p = "--" + argname + "="
    for a in sys.argv:
        if a.startswith(p):
            return a[len(p):]
    return default


# ---------------------------------------------------------------------------
# the boot's own records
# ---------------------------------------------------------------------------
def offsets_file(path=OFFS):
    """{image_pa, vp_rva, ...} written by the probe that found them."""
    m = {}
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if "=" in line:
                    k, v = line.split("=", 1)
                    m[k.strip()] = v.strip()
    except OSError:
        pass
    return m


def census_seeds(path=CENSUS):
    """Census PAs in file order, first occurrence only, capped by the caller."""
    pas = []
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                mm = re.match(r"\s*@0x([0-9a-fA-F]+)", line)
                if mm:
                    pa = int(mm.group(1), 16)
                    if pa not in pas:
                        pas.append(pa)
    except OSError:
        return []
    return pas


# ---------------------------------------------------------------------------
# physical reads, inside the RAM map's interval set only (R10)
# ---------------------------------------------------------------------------
class Phys(object):
    CHUNK = 0x10000

    def __init__(self):
        import gio
        import dumplive as dl
        self.gio = gio
        self.dl = dl
        self.g = gio.Gio(chunk=self.CHUNK)
        self.ranges, self.note = dl.usable_ranges(self.g.ram_top, None, None)
        self.reads = 0
        self.refused = 0
        self.failed = 0

    def ok(self, pa, n):
        for lo, hi in self.ranges:
            if lo <= pa and pa + n <= hi:
                return True
        return False

    def read(self, pa, n, tries=2):
        if not self.ok(pa, n):
            self.refused += 1
            return None
        self.reads += 1
        try:
            b = self.dl.retry_phys(self.g, pa, n, tries=tries)
        except OSError:
            self.failed += 1
            return None
        if not b or len(b) != n:
            self.failed += 1
            return None
        return b

    def alive(self):
        try:
            return self.dl.find_pid()
        except OSError:
            return None

    def close(self):
        try:
            self.g.close()
        except Exception:                        # noqa: BLE001
            pass


# ---------------------------------------------------------------------------
# maths: world -> pixel (column convention, w = depth; the pair _mk20 pinned)
# ---------------------------------------------------------------------------
def project(m, x, y, z, w, h):
    """(sx, sy, depth) or None when the point is behind the eye."""
    px = m[0] * x + m[4] * y + m[8] * z + m[12]
    py = m[1] * x + m[5] * y + m[9] * z + m[13]
    pw = m[3] * x + m[7] * y + m[11] * z + m[15]
    if pw != pw or pw <= 1e-6:
        return None
    sx = (px / pw * 0.5 + 0.5) * w
    sy = (0.5 - py / pw * 0.5) * h
    if sx != sx or sy != sy:
        return None
    return sx, sy, pw


def seed_triple(b):
    """The census record's world position, or None if those three floats are not one."""
    if not b or len(b) < SEED_BYTES:
        return None
    f = struct.unpack_from("<48f", b, 0)
    v = tuple(f[i] for i in SEED_TRIPLE)
    if any(x != x for x in v):
        return None
    if any(abs(x) > 20000.0 for x in v):
        return None
    if max(abs(x) for x in v) < 1.0:          # (0,0,0) is a dead record
        return None
    if any(abs(x) < 1e-3 for x in v):         # strided record read contiguously
        return None
    return v


def boxes_for(m, ents, w, h):
    """[(x0, y0, x1, y1, depth)] for every entity that projects in front."""
    res = []
    for _pa, v in ents:
        x, y, z = v
        feet = project(m, x, y, z, w, h)
        head = project(m, x, y, z + HEAD_Z, w, h)
        if not feet or not head:
            continue
        y1, y0 = feet[1], head[1]
        if not (y1 > y0):
            continue
        bh = y1 - y0
        if bh < 4.0 or bh > 1500.0:
            continue
        bw = bh * BOX_W
        if bw > BOX_MAX_W:
            bw = BOX_MAX_W
        cx = (feet[0] + head[0]) * 0.5
        res.append((cx - bw * 0.5, y0, cx + bw * 0.5, y1, feet[2]))
    return res


def matrix_plausible(m):
    """Cheap structural gate before any projection work.

    A live view-projection never contains NaN/inf, never has a degenerate
    3x3 rotation/projection block, and never has a row of that block with a
    length outside sane float range.  This does not *prove* the matrix is the
    camera; it only stops obviously torn/garbage windows from being scored and
    drawn as if they were the world.
    """
    if not m or len(m) != 16:
        return False
    for v in m:
        if v != v or abs(v) > 1.0e6:
            return False
    a, b, c = m[0], m[1], m[2]
    d, e, f = m[4], m[5], m[6]
    g, h, i = m[8], m[9], m[10]
    det = (a * (e * i - f * h)
           - b * (d * i - f * g)
           + c * (d * h - e * g))
    if det != det or abs(det) < 1.0e-7:
        return False
    for row in ((a, b, c), (d, e, f), (g, h, i)):
        n = math.sqrt(row[0] * row[0] + row[1] * row[1] + row[2] * row[2])
        if n != n or not (1.0e-3 < n < 1.0e3):
            return False
    return True


def score_vp(m, ents, w, h):
    """How many entities land on screen with a human-sized box."""
    n = 0
    for _pa, v in ents:
        x, y, z = v
        p = project(m, x, y, z, w, h)
        if not p:
            continue
        sx, sy, d = p
        if not (0.0 <= sx <= w and 0.0 <= sy <= h):
            continue
        if d < 1.0 or d > 40000.0:
            continue
        n += 1
    return n


def pick_window(ph, base, rva, ents, w, h, wide=False):
    """(matrix, lead, hits, rva) -- the 16-float window at this address that
    projects the census onto the screen.  0x9440B4 vs 0x9440B0 was never resolved
    by hand; the scoring decides it, and 'wide' widens the ADDRESS (matrix copies
    sit 0xE0 apart) instead of the guess."""
    leads = (0, 4)
    rvas = [rva]
    if wide:
        rvas = [rva + d for d in range(-0x1000, 0x1001, 0x10)]
    best = (None, 0, -1, rva)
    for r in rvas:
        b = ph.read(base + r, 0x80, tries=2)
        if not b:
            continue
        for lead in leads:
            m = struct.unpack_from("<16f", b, lead)
            if not matrix_plausible(m):
                continue
            hits = score_vp(m, ents, w, h)
            if hits > best[2]:
                best = (m, lead, hits, r)
    return best


# ---------------------------------------------------------------------------
# the window: layered + colorkey + click-through + noactivate
# ---------------------------------------------------------------------------
user32 = ctypes.WinDLL("user32", use_last_error=True)
gdi32 = ctypes.WinDLL("gdi32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

LRESULT = ctypes.c_ssize_t
WNDPROC = ctypes.WINFUNCTYPE(LRESULT, wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM)

WS_POPUP = 0x80000000
WS_EX_LAYERED = 0x00080000
WS_EX_TRANSPARENT = 0x00000020
WS_EX_TOPMOST = 0x00000008
WS_EX_TOOLWINDOW = 0x00000080
WS_EX_NOACTIVATE = 0x08000000
LWA_COLORKEY = 0x00000001
SW_SHOWNOACTIVATE = 4
HWND_TOPMOST = wt.HWND(-1)
SWP_NOMOVE = 0x0002
SWP_NOSIZE = 0x0001
SWP_NOACTIVATE = 0x0010
DT_LEFT = 0x0000
DT_SINGLELINE = 0x0020
DT_NOPREFIX = 0x0800
DT_VCENTER = 0x0004
TRANSPARENT_BK = 1
PM_REMOVE = 0x0001
SRCCOPY = 0x00CC0020
WM_PAINT = 0x000F
WM_DESTROY = 0x0002
WM_ERASEBKGND = 0x0014


class WNDCLASSEXW(ctypes.Structure):
    _fields_ = [("cbSize", wt.UINT), ("style", wt.UINT), ("lpfnWndProc", WNDPROC),
                ("cbClsExtra", ctypes.c_int), ("cbWndExtra", ctypes.c_int),
                ("hInstance", wt.HINSTANCE), ("hIcon", wt.HICON),
                ("hCursor", wt.HANDLE), ("hbrBackground", wt.HBRUSH),
                ("lpszMenuName", wt.LPCWSTR), ("lpszClassName", wt.LPCWSTR),
                ("hIconSm", wt.HICON)]


user32.DefWindowProcW.restype = LRESULT
user32.DefWindowProcW.argtypes = [wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM]
user32.CreateWindowExW.restype = wt.HWND
user32.CreateWindowExW.argtypes = [wt.DWORD, wt.LPCWSTR, wt.LPCWSTR, wt.DWORD,
                                   ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                                   wt.HWND, wt.HMENU, wt.HINSTANCE, wt.LPVOID]
user32.RegisterClassExW.restype = wt.ATOM
user32.RegisterClassExW.argtypes = [ctypes.POINTER(WNDCLASSEXW)]
user32.SetLayeredWindowAttributes.argtypes = [wt.HWND, wt.DWORD, wt.BYTE, wt.DWORD]
user32.GetDC.restype = wt.HDC
user32.GetDC.argtypes = [wt.HWND]
user32.ReleaseDC.argtypes = [wt.HWND, wt.HDC]
user32.ValidateRect.restype = wt.BOOL
user32.ValidateRect.argtypes = [wt.HWND, wt.LPVOID]
user32.SetWindowPos.argtypes = [wt.HWND, wt.HWND, ctypes.c_int, ctypes.c_int,
                                 ctypes.c_int, ctypes.c_int, wt.UINT]
user32.GetAsyncKeyState.restype = ctypes.c_short
user32.GetAsyncKeyState.argtypes = [ctypes.c_int]
user32.PeekMessageW.argtypes = [ctypes.POINTER(wt.MSG), wt.HWND, wt.UINT, wt.UINT, wt.UINT]

gdi32.CreateCompatibleDC.restype = wt.HDC
gdi32.CreateCompatibleDC.argtypes = [wt.HDC]
gdi32.CreateCompatibleBitmap.restype = wt.HBITMAP
gdi32.CreateCompatibleBitmap.argtypes = [wt.HDC, ctypes.c_int, ctypes.c_int]
gdi32.SelectObject.restype = wt.HGDIOBJ
gdi32.SelectObject.argtypes = [wt.HDC, wt.HGDIOBJ]
gdi32.CreateSolidBrush.restype = wt.HBRUSH
gdi32.CreateSolidBrush.argtypes = [wt.DWORD]
gdi32.CreateFontW.restype = wt.HFONT
gdi32.CreateFontW.argtypes = [ctypes.c_int] * 5 + [wt.DWORD] * 8 + [wt.LPCWSTR]
gdi32.SetBkMode.argtypes = [wt.HDC, ctypes.c_int]
gdi32.SetTextColor.argtypes = [wt.HDC, wt.DWORD]
user32.DrawTextW.argtypes = [wt.HDC, wt.LPCWSTR, ctypes.c_int, wt.LPVOID, wt.UINT]
gdi32.BitBlt.argtypes = [wt.HDC, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                         wt.HDC, ctypes.c_int, ctypes.c_int, wt.DWORD]
user32.FillRect.argtypes = [wt.HDC, wt.LPVOID, wt.HBRUSH]


class Overlay(object):
    """A GDI canvas on a colour-keyed layered window.  Pure black is transparent,
    so every frame starts by filling black and only lit pixels survive the blit."""

    def __init__(self, rect):
        self.rect = rect
        self.w = max(1, rect[2] - rect[0])
        self.h = max(1, rect[3] - rect[1])
        self.hwnd = None
        self._proc = WNDPROC(self._wndproc)          # lifetime: keep the thunk
        hinst = kernel32.GetModuleHandleW(None)
        wc = WNDCLASSEXW()
        wc.cbSize = ctypes.sizeof(WNDCLASSEXW)
        wc.lpfnWndProc = self._proc
        wc.hInstance = hinst
        wc.lpszClassName = "QkLiveOverlay"
        user32.RegisterClassExW(ctypes.byref(wc))    # already registered is fine
        ex = (WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST
              | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE)
        self.hwnd = user32.CreateWindowExW(ex, "QkLiveOverlay", "qk_live", WS_POPUP,
                                           rect[0], rect[1], self.w, self.h,
                                           None, None, hinst, None)
        if not self.hwnd:
            raise OSError("CreateWindowExW failed (%d)" % ctypes.get_last_error())
        user32.SetLayeredWindowAttributes(self.hwnd, KEY_BLACK, 0, LWA_COLORKEY)
        user32.ShowWindow(self.hwnd, SW_SHOWNOACTIVATE)
        user32.SetWindowPos(self.hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
        self._screen = user32.GetDC(None)
        self.dc = gdi32.CreateCompatibleDC(self._screen)
        self.bmp = gdi32.CreateCompatibleBitmap(self._screen, self.w, self.h)
        self._old = gdi32.SelectObject(self.dc, self.bmp)
        self.brush = {}
        self.font = gdi32.CreateFontW(-15, 0, 0, 0, 600, 0, 0, 0, 1, 4, 0, 5, 0, "Consolas")
        self.font_sm = gdi32.CreateFontW(-13, 0, 0, 0, 500, 0, 0, 0, 1, 4, 0, 5, 0, "Consolas")
        gdi32.SetBkMode(self.dc, TRANSPARENT_BK)

    def _brush(self, color):
        b = self.brush.get(color)
        if b is None:
            b = gdi32.CreateSolidBrush(color)
            self.brush[color] = b
        return b

    def _wndproc(self, hwnd, msg, wp, lp):
        if msg == WM_ERASEBKGND:
            return 1
        if msg == WM_PAINT:
            # Validate the update region; otherwise WM_PAINT is posted forever
            # and pump() starves the frame loop.
            user32.ValidateRect(hwnd, None)
            return 0
        if msg == WM_DESTROY:
            user32.PostQuitMessage(0)
            return 0
        return user32.DefWindowProcW(hwnd, msg, wp, lp)

    # -- drawing -----------------------------------------------------------
    def clear(self):
        r = wt.RECT(0, 0, self.w, self.h)
        user32.FillRect(self.dc, ctypes.byref(r), self._brush(KEY_BLACK))

    def fill(self, x0, y0, x1, y1, color):
        user32.FillRect(self.dc, ctypes.byref(wt.RECT(int(x0), int(y0), int(x1), int(y1))),
                        self._brush(color))

    def frame(self, x0, y0, x1, y1, color, thick=1):
        x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
        if x1 < x0:
            x0, x1 = x1, x0
        if y1 < y0:
            y0, y1 = y1, y0
        b = self._brush(color)
        for i in range(max(1, int(thick))):
            l, t, r, bt = x0 - i, y0 - i, x1 + i + 1, y1 + i + 1
            for rect in (wt.RECT(l, t, r, t + 1), wt.RECT(l, bt - 1, r, bt),
                         wt.RECT(l, t, l + 1, bt), wt.RECT(r - 1, t, r, bt)):
                user32.FillRect(self.dc, ctypes.byref(rect), b)

    def text(self, x, y, s, color, small=False, width=600):
        gdi32.SelectObject(self.dc, self.font_sm if small else self.font)
        gdi32.SetTextColor(self.dc, color)
        r = wt.RECT(int(x), int(y), int(x) + int(width), int(y) + 20)
        user32.DrawTextW(self.dc, s, -1, ctypes.byref(r),
                         DT_LEFT | DT_SINGLELINE | DT_NOPREFIX | DT_VCENTER)

    def present(self):
        dc = user32.GetDC(self.hwnd)
        if dc:
            gdi32.BitBlt(dc, 0, 0, self.w, self.h, self.dc, 0, 0, SRCCOPY)
            user32.ReleaseDC(self.hwnd, dc)
        user32.SetWindowPos(self.hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)

    def pump(self):
        msg = wt.MSG()
        while user32.PeekMessageW(ctypes.byref(msg), None, 0, 0, PM_REMOVE):
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))

    def close(self):
        if self.hwnd:
            user32.DestroyWindow(self.hwnd)
            self.hwnd = None


# ---------------------------------------------------------------------------
# menu state: toggles, hotkeys, and a file so a restart keeps them
# ---------------------------------------------------------------------------
DEFAULTS = {
    "menu": 1, "esp": 1, "filled": 0, "glow": 1, "dist": 1,
    "thick": 2, "scheme": 0, "hz": 20,
}
KEYS = (
    (0x2D, "INSERT", "menu", "menu"),
    (0x70, "F1", "esp", "esp"),
    (0x71, "F2", "filled", "fill"),
    (0x72, "F3", "glow", "glow"),
    (0x73, "F4", "dist", "dist"),
    (0x74, "F5", "thick", "thick"),
    (0x75, "F6", "scheme", "colour"),
    (0x76, "F7", "hz", "rate"),
)
VK_END = 0x23
VK_F8 = 0x77


def cfg_load(path=CFG):
    cfg = dict(DEFAULTS)
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if "=" in line:
                    k, v = line.split("=", 1)
                    k = k.strip()
                    if k in cfg:
                        try:
                            cfg[k] = int(v.strip(), 0)
                        except ValueError:
                            pass
    except OSError:
        pass
    return cfg


def cfg_save(cfg, path=CFG):
    try:
        with open(path, "w", encoding="utf-8") as f:
            for k in sorted(cfg):
                f.write("%s=%d\n" % (k, cfg[k]))
        return True
    except OSError:
        return False


class Keys(object):
    """Edge detection over GetAsyncKeyState: the overlay never takes focus, so this
    is the only way the menu can be driven while the game owns the keyboard."""

    def __init__(self):
        self.prev = {}

    def hit(self, vk):
        st = user32.GetAsyncKeyState(vk) & 0x8000
        was = self.prev.get(vk, False)
        self.prev[vk] = bool(st)
        return bool(st) and not was


def apply_key(cfg, action):
    """One hotkey -> one variable.  Returns the (key, value) that moved, or None."""
    if action == "thick":
        cfg["thick"] = cfg["thick"] % 4 + 1
        return ("thick", cfg["thick"])
    if action == "scheme":
        cfg["scheme"] = (cfg["scheme"] + 1) % len(SCHEMES)
        return ("scheme", SCHEMES[cfg["scheme"]][0])
    if action == "hz":
        order = (10, 20, 30, 60)
        i = order.index(cfg["hz"]) if cfg["hz"] in order else 1
        cfg["hz"] = order[(i + 1) % len(order)]
        return ("hz", cfg["hz"])
    cfg[action] = 0 if cfg.get(action) else 1
    return (action, "on" if cfg[action] else "off")


def menu_rows(cfg):
    return [
        ("INSERT", "menu", "shown" if cfg["menu"] else "hidden"),
        ("F1", "esp", "on" if cfg["esp"] else "off"),
        ("F2", "fill", "on" if cfg["filled"] else "off"),
        ("F3", "glow", "on" if cfg["glow"] else "off"),
        ("F4", "dist", "on" if cfg["dist"] else "off"),
        ("F5", "thick", "%dx" % cfg["thick"]),
        ("F6", "colour", SCHEMES[cfg["scheme"] % len(SCHEMES)][0]),
        ("F7", "rate", "%d Hz" % cfg["hz"]),
        ("F8", "save", CFG.split(os.sep)[-1]),
        ("END", "quit", ""),
    ]


def draw_menu(ov, cfg, st, accent):
    rows = menu_rows(cfg)
    x, y, w = 24, 24, 300
    h = 34 + 20 * len(rows) + 10
    ov.fill(x, y, x + w, y + h, 0x00181818)
    ov.frame(x, y, x + w, y + h, accent, 1)
    ov.fill(x, y, x + w, y + 3, accent)
    ov.text(x + 12, y + 8, "QwenKern  range ESP", 0x00E8E8E8)
    ry = y + 34
    for key, label, val in rows:
        on = val in ("on", "shown") or val.endswith("x") or val.endswith("Hz")
        ov.text(x + 12, ry, key, 0x00909090, small=True)
        ov.text(x + 92, ry, label, 0x00D0D0D0, small=True)
        ov.text(x + 190, ry, val, accent if on else 0x00707070, small=True)
        ry += 20
    if st:
        ov.text(x + 12, y + h - 18, st, 0x00808080, small=True)


def draw_status(ov, text, accent):
    ov.text(24, ov.h - 30, text, accent, small=True)


# ---------------------------------------------------------------------------
# the game window: project into its client area, not into "the screen"
# ---------------------------------------------------------------------------
user32.GetWindowThreadProcessId.argtypes = [wt.HWND, ctypes.POINTER(wt.DWORD)]
user32.IsWindowVisible.argtypes = [wt.HWND]
user32.GetClientRect.argtypes = [wt.HWND, wt.LPVOID]
user32.ClientToScreen.argtypes = [wt.HWND, wt.LPVOID]
user32.EnumWindows.argtypes = [ctypes.c_void_p, wt.LPARAM]
user32.GetSystemMetrics.argtypes = [ctypes.c_int]
user32.GetSystemMetrics.restype = ctypes.c_int
kernel32.GetModuleHandleW.restype = wt.HINSTANCE

_ENUMPROC = ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)


def game_rect(pid):
    """(x, y, x+w, y+h) of the game's biggest visible window, or None."""
    best = [None, 0]

    def cb(hwnd, lp):
        p = wt.DWORD(0)
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
        if p.value != pid:
            return True
        if not user32.IsWindowVisible(hwnd):
            return True
        r = wt.RECT()
        if not user32.GetClientRect(hwnd, ctypes.byref(r)):
            return True
        w, h = r.right - r.left, r.bottom - r.top
        if w < 320 or h < 200:
            return True
        if w * h > best[1]:
            pt = wt.POINT(0, 0)
            user32.ClientToScreen(hwnd, ctypes.byref(pt))
            best[0] = (pt.x, pt.y, pt.x + w, pt.y + h)
            best[1] = w * h
        return True

    user32.EnumWindows(_ENUMPROC(cb), 0)
    return best[0]


def screen_rect():
    return (0, 0, user32.GetSystemMetrics(0), user32.GetSystemMetrics(1))


# ---------------------------------------------------------------------------
# the live feed: matrix and records read in the same tick
# ---------------------------------------------------------------------------
class Session(object):
    def __init__(self, cap=28, wide=False, base=None, rva=None):
        self.ph = Phys()
        self.pid = self.ph.alive()
        off = offsets_file()
        self.base = base if base is not None else (
            int(off["image_pa"], 16) if "image_pa" in off else None)
        self.rva = rva if rva is not None else int(off.get("vp_rva", "0x9440B4"), 16)
        self.wide = wide
        self.wide_rva = None
        self.m = None
        self.lead = 0
        self.hits = 0
        self.boxes = []
        self.ents = []
        self.cap = cap
        self.seed_total = 0
        self.dropped = 0

    def prime(self):
        """Keep the census records that actually hold a world position."""
        seeds = census_seeds()
        self.seed_total = len(seeds)
        keep = []
        for pa in seeds:
            b = self.ph.read(pa, SEED_BYTES)
            v = seed_triple(b)
            if v:
                keep.append((pa, v))
                if len(keep) >= self.cap:
                    break
            else:
                self.dropped += 1
        self.ents = keep
        return keep

    def _read_vp(self, rva):
        b = self.ph.read(self.base + rva, 0x80)
        if not b:
            return None
        return b

    def tick(self, w, h):
        if self.base is None:
            return
        if not self.ents:
            self.prime()
        rva = self.wide_rva or self.rva
        b = self._read_vp(rva)
        best = (None, 0, -1)
        if b:
            for lead in (0, 4):
                m = struct.unpack_from("<16f", b, lead)
                if not matrix_plausible(m):
                    continue
                hits = score_vp(m, self.ents, w, h)
                if hits > best[2]:
                    best = (m, lead, hits)
        if self.wide and self.wide_rva is None and (best[0] is None or best[2] == 0):
            m, lead, hits, r = pick_window(self.ph, self.base, self.rva, self.ents,
                                           w, h, wide=True)
            if m is not None and hits > 0:
                self.wide_rva = r
                best = (m, lead, hits)
        if best[0] is not None:
            self.m, self.lead, self.hits = best
        # refresh the records AFTER the matrix, in the same tick
        ents = []
        for pa, old in self.ents:
            b = self.ph.read(pa, SEED_BYTES)
            v = seed_triple(b) or old
            ents.append((pa, v))
        self.ents = ents
        self.boxes = boxes_for(self.m, self.ents, w, h) if self.m else []
        return self.boxes


def synthetic_boxes(t, w, h):
    """--fake: five boxes on rails.  No game, no driver, no physical read --
    it isolates 'does the window/menu draw at all' from 'is the feed live'."""
    res = []
    for i in range(5):
        ph = t * 0.7 + i * 1.3
        cx = w * 0.5 + math.sin(ph) * w * 0.28
        cy = h * 0.55 + math.cos(ph * 0.8) * h * 0.18
        bh = 90.0 + 40.0 * (1.0 + math.sin(ph * 0.5)) * 0.5
        bw = bh * BOX_W
        res.append((cx - bw * 0.5, cy - bh, cx + bw * 0.5, cy, 400.0 + i * 300.0))
    return res


def draw_boxes(ov, boxes, cfg, ox, oy, accent, accent2):
    for x0, y0, x1, y1, depth in boxes:
        if cfg["filled"]:
            ov.fill(ox + x0, oy + y0, ox + x1, oy + y1, accent2)
        if cfg["glow"]:
            ov.frame(ox + x0 - 2, oy + y0 - 2, ox + x1 + 2, oy + y1 + 2, accent2,
                     cfg["thick"])
        ov.frame(ox + x0, oy + y0, ox + x1, oy + y1, accent, cfg["thick"])
        if cfg["dist"]:
            ov.text(ox + x0, oy + y0 - 20, "%du" % int(depth), accent, small=True)


def run(cfg, seconds, fake, wide, cap, base, rva):
    import dumplive as dl
    t0 = time.time()
    pid = None if fake else dl.find_pid()
    rect = screen_rect() if fake else (game_rect(pid) or screen_rect())
    out("window rect: %s  (%dx%d)" % (rect, rect[2] - rect[0], rect[3] - rect[1]))
    try:
        ov = Overlay(rect)
    except OSError as e:
        out("VERDICT: FAIL - %s" % e)
        return 2
    ox, oy = rect[0], rect[1]
    w, h = ov.w, ov.h
    keep = Keys()
    sess = None
    if not fake:
        try:
            sess = Session(cap=cap, wide=wide, base=base, rva=rva)
        except OSError as e:
            out("gio: %s" % e)
            out("VERDICT: FAIL - need elevation for gdrv3")
            return 2
        got = sess.prime()
        out("census: %d seeds, %d hold a position, %d dropped"
            % (sess.seed_total, len(got), sess.dropped))
        out("image_pa=%#x vp_rva=%#x pid=%s" % (sess.base or 0, sess.rva, sess.pid))
        if not got:
            out("VERDICT: FAIL - no usable census record (stale _p134_out.txt?)")
    boxes = []
    accent = SCHEMES[cfg["scheme"] % len(SCHEMES)][1]
    accent2 = 0x00303030
    next_read = 0.0
    next_status = 0.0
    next_log = t0 + 5.0
    frames = 0
    reads_at_start = 0
    last_boxes = 0
    reason = "time"
    while True:
        t = time.time()
        if seconds and t - t0 >= seconds:
            break
        ov.pump()
        for vk, name, action, label in KEYS:
            if keep.hit(vk):
                moved = apply_key(cfg, action)
                out("key %-6s %-6s -> %s" % (name, label, moved[1]))
                cfg_save(cfg)
                accent = SCHEMES[cfg["scheme"] % len(SCHEMES)][1]
                next_read = 0.0
        if keep.hit(VK_F8):
            out("key F8     save   -> %s (%s)" % (CFG, "ok" if cfg_save(cfg) else "FAILED"))
        if keep.hit(VK_END):
            reason = "END"
            break
        if t >= next_read:
            if fake:
                boxes = synthetic_boxes(t - t0, w, h)
            else:
                if dl.find_pid() is None:
                    out("game gone at %.1fs" % (t - t0))
                    reason = "game gone"
                    break
                if reads_at_start == 0:
                    reads_at_start = sess.ph.reads
                boxes = sess.tick(w, h)
            last_boxes = len(boxes)
            next_read = t + 1.0 / max(1, cfg["hz"])
        ov.clear()
        if cfg["esp"]:
            draw_boxes(ov, boxes, cfg, ox, oy, accent, accent2)
        if cfg["menu"]:
            draw_menu(ov, cfg, "boxes %d  hits %d  %d Hz"
                      % (last_boxes, 0 if sess is None else sess.hits, cfg["hz"]), accent)
        else:
            draw_status(ov, "QwenKern  %d boxes  %d Hz  [INSERT] menu"
                        % (last_boxes, cfg["hz"]), accent)
        ov.present()
        frames += 1
        if t >= next_status:
            elapsed = max(0.001, t - t0)
            rps = 0.0
            if sess is not None:
                rps = (sess.ph.reads - reads_at_start) / elapsed if reads_at_start else 0.0
            status("t=%.1fs frames=%d fps=%.1f boxes=%d hz=%d reads/s=%.0f hits=%s"
                   % (elapsed, frames, frames / elapsed, last_boxes, cfg["hz"], rps,
                      "-" if sess is None else sess.hits))
            next_status = t + 1.0
        if t >= next_log:
            out("t=%.1fs frames=%d boxes=%d hits=%s reads=%s"
                % (t - t0, frames, last_boxes, "-" if sess is None else sess.hits,
                   "-" if sess is None else sess.ph.reads))
            next_log = t + 5.0
        dt = 1.0 / 60.0 - (time.time() - t)
        if dt > 0:
            time.sleep(dt)
    elapsed = time.time() - t0
    cfg_save(cfg)
    if sess is not None:
        sess.ph.close()
    ov.close()
    stats = ""
    if sess is not None:
        stats = (" reads=%d refused=%d failed=%d" %
                 (sess.ph.reads, sess.ph.refused, sess.ph.failed))
    out("stopped by %s after %.1fs: frames=%d fps=%.1f boxes=%d%s"
        % (reason, elapsed, frames, frames / max(0.001, elapsed), last_boxes, stats))
    out("RESULT: %s frames=%d boxes=%d%s"
        % (reason, frames, last_boxes, stats))
    return 0 if frames else 1


# ---------------------------------------------------------------------------
# --check: the read-back that decides whether the cached offsets still speak
# ---------------------------------------------------------------------------
def check(wide, cap):
    import dumplive as dl
    t0 = time.time()
    out("=== qk_live check %s ===" % now())
    pid = dl.find_pid()
    out("game pid=%s" % pid)
    if pid is None:
        out("VERDICT: PARTIAL - game not running, nothing read (R9)")
        return 3
    try:
        s = Session(cap=cap, wide=wide)
    except OSError as e:
        out("gio: %s" % e)
        out("VERDICT: FAIL - could not open the physical read transport")
        return 2
    ph = s.ph
    try:
        out("ram_top=%#x ranges=%d (%s) reads=%d"
            % (ph.g.ram_top, len(ph.ranges), ph.note, ph.reads))
        out("image_pa=%#x vp_rva=%#x" % (s.base or 0, s.rva))
        if s.base is None:
            out("VERDICT: FAIL - temp\\qk_offsets.txt has no image_pa")
            return 1
        got = s.prime()
        out("census: %d seeds, %d hold a position, %d dropped (%d reads)"
            % (s.seed_total, len(got), s.dropped, ph.reads))
        for i, (pa, v) in enumerate(got[:8]):
            out("  seed%d %#x  (%.2f, %.2f, %.2f)" % (i, pa, v[0], v[1], v[2]))
        if not got:
            out("VERDICT: FAIL - no census record holds a position")
            return 1
        b = ph.read(s.base + s.rva, 0x80)
        if not b:
            out("VERDICT: FAIL - the matrix read was refused by the interval set")
            return 1
        f = struct.unpack("<32f", b)
        for lead in (0, 4):
            out("window @%#x +%d:" % (s.rva, lead))
            for r in range(4):
                out("   %s" % " ".join("%12.6g" % x for x in f[lead + r * 4: lead + r * 4 + 4]))
        rect = game_rect(pid) or screen_rect()
        s.tick(rect[2] - rect[0], rect[3] - rect[1])
        out("chosen lead=%d hits=%d/%d boxes=%d rva=%#x wide_rva=%s"
            % (s.lead, s.hits, len(s.ents), len(s.boxes), s.rva,
               "%#x" % s.wide_rva if s.wide_rva is not None else "-"))
        for i, bx in enumerate(s.boxes[:10]):
            out("  box%d  x %.0f..%.0f  y %.0f..%.0f  d=%.0f"
                % (i, bx[0], bx[2], bx[1], bx[3], bx[4]))
        t = time.time() - t0
        alive = dl.find_pid() == pid
        out("elapsed=%.2fs reads=%d refused=%d failed=%d game_alive=%s"
            % (t, ph.reads, ph.refused, ph.failed, alive))
        boxes = len(s.boxes)
        if s.hits >= 3 and boxes >= 3 and alive:
            out("RESULT: PASS lead=%d hits=%d boxes=%d reads=%d"
                % (s.lead, s.hits, boxes, ph.reads))
            out("VERDICT: PASS - cached image_pa/vp_rva project %d record(s) on screen" % boxes)
            return 0
        if s.hits == 0:
            out("VERDICT: PARTIAL - matrix reads but projects nothing; try --wide")
            return 4
        out("VERDICT: PARTIAL - hits=%d boxes=%d alive=%s" % (s.hits, boxes, alive))
        return 4
    finally:
        ph.close()


def _relaunch():
    import dumplive as dl
    params = " ".join(['"%s"' % os.path.abspath(__file__)] + sys.argv[1:])
    out("not elevated -> %s" % params)
    msg = dl.run_elevated(params)
    out(msg)
    return 0


def main():
    global _logf
    mode = "fake" if flag("fake") else ("check" if flag("check") else "run")
    cap = arg("seeds", 28, int)
    wide = flag("wide")
    base = arg("base", None, lambda v: int(v, 0))
    rva = arg("rva", None, lambda v: int(v, 0))
    seconds = arg("seconds", 0, int)
    if mode == "check" and not seconds:
        seconds = 0
    try:
        _logf = open(OUT, "a", encoding="utf-8")
    except OSError:
        _logf = None
    out("")
    out("=== qk_live %s %s mode=%s args=%s ===" % (now(), time.strftime("%d/%m"),
                                                  mode, " ".join(sys.argv[1:]) or "-"))
    try:
        if mode == "fake":
            cfg = cfg_load()
            return run(cfg, seconds or 20, True, False, cap, base, rva)
        import dumplive as dl
        if not dl.elevation():
            return _relaunch()
        if mode == "check":
            return check(wide, cap)
        return run(cfg_load(), seconds, False, wide, cap, base, rva)
    finally:
        if _logf is not None:
            _logf.close()
            _logf = None


if __name__ == "__main__":
    sys.exit(main())
