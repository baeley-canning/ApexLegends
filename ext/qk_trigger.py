r"""qk_trigger.py -- the triggerbot: crosshair -> hitbox band -> click.

The geometry is already in the producer: every entity is projected to a screen box with
the head at y0, the feet at y1 and the body centred on sx.  That is the whole input.

  * the crosshair is the screen centre (X, Y)
  * a target "is under the crosshair" when the crosshair pixel falls inside the selected
    vertical BAND of that box and inside the box horizontally
  * bands are fractions of the box height (head -> feet), so they survive distance:
        HEAD  0.00-0.16   narrow (0.55 of the box half-width)
        TORSO 0.14-0.46   full width
        ARMS  0.18-0.62   wide (1.45), arms stick out past the torso to hip level
        BODY  0.00-1.00   anything on the silhouette
  * the click is SendInput on the left button, delayed by delay_ms from first contact
    (the humanisation the menu slider exposes), one click per acquisition, re-armed
    once the target has been gone for rearm_ms.  hold=1 keeps the button down while
    the target stays (automatic weapons) instead of clicking once.
  * a foreground guard stops the trigger firing while you are tabbed out: the
    foreground window must look like the game (title contains "apex" or the class
    starts with "Respawn").

Settings file (the menu contract), temp\qk_trigger.txt -- every line optional, read on
start and on reload():

    enabled=1              # 0/1
    hitbox=TORSO           # HEAD|TORSO|ARMS|BODY  (or 0..3)
    delay_ms=60            # 0..500
    hold=0                 # 0/1
    key=LMB                # LMB|RMB

Evidence feed (R3), temp\qk_trigger_state.txt -- rewritten only when the state text
changes, so a stall is visible as a stale file, not as silence.

Offline check, no game and no overlay needed:

    python qk_trigger.py --selftest

Exit: 0 pass / 1 fail (selftest).
"""
import ctypes
import ctypes.wintypes as wt
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TEMP = os.path.join(os.path.dirname(HERE), "temp")
SETTINGS = os.path.join(TEMP, "qk_trigger.txt")
STATE_FILE = os.path.join(TEMP, "qk_trigger_state.txt")

# ---- bands ------------------------------------------------------------------
# name -> (lo, hi, half-width factor).  Fractions of the box height from the head.
BANDS = {
    "HEAD":  (0.00, 0.16, 0.55),
    "TORSO": (0.14, 0.46, 1.00),
    "ARMS":  (0.18, 0.62, 1.45),
    "BODY":  (0.00, 1.00, 1.00),
}
BAND_ORDER = ["HEAD", "TORSO", "ARMS", "BODY"]

REARM_MS = 120.0          # target must be gone this long before it can fire again
MIN_BOX_H = 6.0           # ignore degenerate boxes

# ---- SendInput --------------------------------------------------------------
INPUT_MOUSE = 0
LEFTDOWN, LEFTUP, RIGHTDOWN, RIGHTUP = 0x0002, 0x0004, 0x0008, 0x0010
BUTTONS = {"LMB": (LEFTDOWN, LEFTUP), "RMB": (RIGHTDOWN, RIGHTUP)}


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [("dx", wt.LONG), ("dy", wt.LONG), ("mouseData", wt.DWORD),
                ("dwFlags", wt.DWORD), ("time", wt.DWORD),
                ("dwExtraInfo", ctypes.POINTER(wt.ULONG))]


class _InputUnion(ctypes.Union):
    _fields_ = [("mi", MOUSEINPUT), ("pad", ctypes.c_ubyte * 24)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wt.DWORD), ("u", _InputUnion)]


def out(s):
    print(s, flush=True)


def send_mouse(flags):
    """One SendInput mouse event.  True when the OS accepted it (R3: the return value
    is the verdict, the call having been made is not)."""
    inp = INPUT(type=INPUT_MOUSE)
    inp.u.mi = MOUSEINPUT(0, 0, 0, flags, 0, None)
    return ctypes.windll.user32.SendInput(1, ctypes.byref(inp),
                                         ctypes.sizeof(INPUT)) == 1


def foreground_is_game():
    """True when the foreground window looks like the game (title/class)."""
    u32 = ctypes.windll.user32
    hwnd = u32.GetForegroundWindow()
    if not hwnd:
        return False
    u32.GetWindowTextW.argtypes = [wt.HWND, wt.LPWSTR, ctypes.c_int]
    u32.GetClassNameW.argtypes = [wt.HWND, wt.LPWSTR, ctypes.c_int]
    buf = ctypes.create_unicode_buffer(256)
    if u32.GetWindowTextW(hwnd, buf, 256) and "apex" in buf.value.lower():
        return True
    cls = ctypes.create_unicode_buffer(128)
    u32.GetClassNameW(hwnd, cls, 128)
    return cls.value.lower().startswith("respawn")


def classify(px, py, box):
    """Which band does the pixel (px, py) sit in for this box?  None when outside.
    box = (x0, y0, x1, y1) with y0 = head, y1 = feet."""
    x0, y0, x1, y1 = box
    h = y1 - y0
    if h < MIN_BOX_H:
        return None
    cx = x0 + (x1 - x0) / 2.0
    hw = abs(x1 - x0) / 2.0
    frac = (py - y0) / h
    if frac < 0.0 or frac > 1.0:
        return None
    for name in ("HEAD", "TORSO", "ARMS", "BODY"):      # tightest band first
        lo, hi, wf = BANDS[name]
        if lo <= frac <= hi and abs(px - cx) <= max(1.0, hw * wf):
            return name
    return None


def band_hit(px, py, box, want):
    """True when the pixel is inside the WANTED band of this box."""
    got = classify(px, py, box)
    if got is None:
        return False
    return True if want == "BODY" else got == want


# ---- settings ---------------------------------------------------------------
def _read_settings(path):
    cfg = {}
    try:
        with open(path, "r") as f:
            for ln in f:
                ln = ln.split("#", 1)[0].strip()
                if "=" in ln:
                    a, b = ln.split("=", 1)
                    cfg[a.strip().lower()] = b.strip()
    except OSError:
        pass
    return cfg


def _hitbox(s, default="BODY"):
    s = (s or "").strip().upper()
    if s in BANDS:
        return s
    try:
        return BAND_ORDER[int(s, 0)]
    except (ValueError, IndexError):
        return default


def _truthy(s):
    return str(s).strip().lower() not in ("0", "false", "no", "off", "")


# ---- the trigger ------------------------------------------------------------
class Trigger:
    """Feeds on projected boxes, decides, clicks.  Clock and clicker are injectable
    so the whole thing is testable offline (see --selftest)."""

    def __init__(self, enabled=False, hitbox="BODY", delay_ms=60.0, hold=False,
                 button="LMB", focus_guard=True, settings=None,
                 state_file=STATE_FILE, clock=time.time, clicker=None, focus=None):
        self.enabled = bool(enabled)
        self.hitbox = _hitbox(hitbox)
        self.delay_ms = float(delay_ms)
        self.hold = bool(hold)
        self.button = button if button in BUTTONS else "LMB"
        self.focus_guard = bool(focus_guard)
        self.settings_file = settings
        self.state_file = state_file
        self._clock = clock
        self._clicker = clicker or send_mouse
        self._focus = focus or foreground_is_game
        self._contact = None        # clock time of first contact with a target
        self._gone_at = None        # clock time the crosshair emptied
        self._down = False          # hold mode: button currently down
        self._locked = False        # single-click mode: already fired this acquisition
        self.fired = 0              # clicks issued
        self.last_state = ""
        self.target = None          # box under the crosshair right now

    # -- settings ------------------------------------------------------------
    def apply_settings(self, cfg):
        """Adopt a settings dict (the menu contract); returns the change list."""
        changed = []
        if "enabled" in cfg:
            v = _truthy(cfg["enabled"])
            if v != self.enabled:
                changed.append("enabled=%d" % v)
            self.enabled = v
        if "hitbox" in cfg:
            v = _hitbox(cfg["hitbox"], self.hitbox)
            if v != self.hitbox:
                changed.append("hitbox=%s" % v)
            self.hitbox = v
        if "delay_ms" in cfg:
            try:
                v = max(0.0, min(500.0, float(cfg["delay_ms"])))
            except ValueError:
                v = self.delay_ms
            if v != self.delay_ms:
                changed.append("delay_ms=%g" % v)
            self.delay_ms = v
        if "hold" in cfg:
            v = _truthy(cfg["hold"])
            if v != self.hold:
                changed.append("hold=%d" % v)
            self.hold = v
        if "key" in cfg:
            v = cfg["key"].strip().upper()
            if v in BUTTONS and v != self.button:
                changed.append("key=%s" % v)
                self.button = v
        return changed

    def reload(self):
        """Re-read the menu contract file.  True when something changed."""
        if not self.settings_file:
            return False
        changed = self.apply_settings(_read_settings(self.settings_file))
        if changed:
            out("trigger settings: " + " ".join(changed))
        return bool(changed)

    # -- decision ------------------------------------------------------------
    def pick(self, boxes, cx, cy):
        """First box (producer order = nearest) whose wanted band covers the
        crosshair."""
        for i, b in enumerate(boxes):
            if band_hit(cx, cy, b, self.hitbox):
                return i, b
        return None, None

    def feed(self, boxes, cx, cy):
        """One frame.  Returns (fired_now, state text)."""
        now = self._clock()
        fired_now = False

        if not self.enabled:
            self._release()
            self._contact = None
            self._locked = False
            self.target = None
            return False, self._state("OFF", now)

        idx, box = self.pick(boxes, cx, cy)
        self.target = box

        if idx is None:
            if self._gone_at is None:
                self._gone_at = now
            if self.hold and self._down:
                self._release()
            if (now - self._gone_at) * 1000.0 >= REARM_MS:
                self._contact = None
                self._locked = False
            return False, self._state("EMPTY", now)

        self._gone_at = None
        if self._contact is None:
            self._contact = now

        waited = (now - self._contact) * 1000.0
        if waited < self.delay_ms:
            return False, self._state("WAIT %d/%dms" % (waited, self.delay_ms), now)

        if self.focus_guard and not self._focus():
            return False, self._state("NOFOCUS", now)

        if self.hold:
            if not self._down and self._press():
                fired_now = True
            return fired_now, self._state("HOLD", now)

        if not self._locked:
            if self._click():
                fired_now = True
                self.fired += 1
            self._locked = True                      # one click per acquisition
        return fired_now, self._state("FIRE", now)

    # -- buttons -------------------------------------------------------------
    def _click(self):
        """Full press+release; True when both events reached the OS."""
        down, up = BUTTONS[self.button]          # tuple order is (DOWN, UP)
        ok = self._clicker(down)
        return self._clicker(up) and ok

    def _press(self):
        self._down = True
        ok = self._clicker(BUTTONS[self.button][0])
        if ok:
            self.fired += 1
        return ok

    def _release(self):
        if not self._down:
            return
        self._down = False
        self._clicker(BUTTONS[self.button][1])       # UP always goes out

    # -- state text ----------------------------------------------------------
    def _state(self, what, now):
        txt = ("enabled=%d hitbox=%s delay=%.0fms hold=%d fired=%d target=%s state=%s"
               % (self.enabled, self.hitbox, self.delay_ms, self.hold, self.fired,
                  "yes" if self.target else "no", what))
        if txt != self.last_state:
            self.last_state = txt
            if self.state_file:
                try:
                    with open(self.state_file, "w") as f:
                        f.write("%.3f %s\n" % (now, txt))
                except OSError:
                    pass
        return txt


# ---- offline selftest -------------------------------------------------------
def selftest(logp=None):
    lines = []

    def say(s):
        lines.append(s)
        out(s)

    box = (860.0, 300.0, 1060.0, 800.0)         # 200x500: head 300, feet 800
    cx, cy = 960.0, 550.0
    bad = 0

    def case(name, ok, detail):
        nonlocal bad
        if not ok:
            bad += 1
        say("%-26s %s  %s" % (name, "ok" if ok else "FAIL", detail))

    # 1. band classifier, straight geometry
    want = [(960, 330, "HEAD"), (960, 500, "TORSO"), (960, 600, "ARMS"),
            (960, 790, "BODY"), (960, 100, None), (700, 550, None),
            (960 + 140, 550, "ARMS"), (960 + 90, 330, "BODY")]
    # (960+90, 330) = shoulder line inside the silhouette but well outside the narrow
    # head -> BODY, not HEAD.  (960+140, 330) is outside that box entirely -> None.
    got = [classify(float(px), float(py), box) for px, py, _w in want]
    case("band classifier", got == [w for _x, _y, w in want],
         "%s" % list(zip([w for _x, _y, w in want], got)))

    # 2. hitbox selection gates: torso pixel must not satisfy hitbox=HEAD
    t = Trigger(enabled=True, hitbox="HEAD", delay_ms=50, clock=lambda: 0.0,
                clicker=lambda f: True, focus=lambda: True, state_file=None)
    case("head-only gates torso", t.pick([box], cx, cy)[0] is None, "pick=%s"
         % t.pick([box], cx, cy)[0])

    # 3. delay honoured, then exactly one click, order down->up
    clk = {"t": 0.0}
    clicks = []
    t = Trigger(enabled=True, hitbox="BODY", delay_ms=60, clock=lambda: clk["t"],
                clicker=lambda f: (clicks.append(f), True)[1], focus=lambda: True,
                state_file=None)
    t.feed([box], cx, cy)                                        # t=0: contact
    clk["t"] = 0.030
    a = t.feed([box], cx, cy)[0]
    clk["t"] = 0.090
    b = t.feed([box], cx, cy)[0]
    clk["t"] = 0.200
    c = t.feed([box], cx, cy)[0]
    case("delay then one click",
         a is False and b is True and c is False and t.fired == 1
         and clicks == [LEFTDOWN, LEFTUP],
         "before=%s at=%s after=%s fired=%d %s" % (a, b, c, t.fired, clicks))

    # 4. re-arm: gone > REARM_MS, next acquisition fires again
    clk["t"] = 1.0
    t.feed([], cx, cy)
    clk["t"] = 1.5
    t.feed([], cx, cy)
    clk["t"] = 1.6
    t.feed([box], cx, cy)
    clk["t"] = 1.7
    fired = t.feed([box], cx, cy)[0]
    case("re-arm after loss", fired is True and t.fired == 2,
         "fired=%s total=%d" % (fired, t.fired))

    # 5. hold mode: down after delay, up on loss
    clk = {"t": 0.0}
    hc = []
    t = Trigger(enabled=True, hitbox="BODY", delay_ms=10, hold=True,
                clock=lambda: clk["t"], clicker=lambda f: (hc.append(f), True)[1],
                focus=lambda: True, state_file=None)
    t.feed([box], cx, cy)
    clk["t"] = 0.05
    t.feed([box], cx, cy)
    held = t._down
    t.feed([], cx, cy)
    case("hold down/up", held and not t._down and hc[-1] == LEFTUP,
         "held=%s released=%s %s" % (held, not t._down, hc))

    # 6. focus guard blocks the click
    clk = {"t": 0.0}
    fc = []
    t = Trigger(enabled=True, hitbox="BODY", delay_ms=10, clock=lambda: clk["t"],
                clicker=lambda f: (fc.append(f), True)[1], focus=lambda: False,
                state_file=None)
    t.feed([box], cx, cy)
    clk["t"] = 0.10
    t.feed([box], cx, cy)
    case("focus guard", fc == [], "events=%s" % fc)

    # 7. disabled clicks nothing
    clk = {"t": 0.0}
    ec = []
    t = Trigger(enabled=False, hitbox="BODY", delay_ms=0, clock=lambda: clk["t"],
                clicker=lambda f: (ec.append(f), True)[1], focus=lambda: True,
                state_file=None)
    for i in range(5):
        clk["t"] = i * 0.05
        t.feed([box], cx, cy)
    case("disabled", ec == [], "events=%s" % ec)

    # 8. settings contract (the menu file)
    t = Trigger(enabled=False, hitbox="BODY", delay_ms=10, state_file=None)
    ch = t.apply_settings({"enabled": "1", "hitbox": "torso", "delay_ms": "120",
                           "hold": "1", "key": "RMB"})
    case("settings contract",
         t.enabled and t.hitbox == "TORSO" and t.delay_ms == 120.0 and t.hold
         and t.button == "RMB" and len(ch) == 5,
         "hitbox=%s delay=%g hold=%d key=%s changed=%d"
         % (t.hitbox, t.delay_ms, t.hold, t.button, len(ch)))

    # 9. a nearer box wins over a farther one
    far = (100.0, 300.0, 300.0, 800.0)
    t = Trigger(enabled=True, hitbox="BODY", delay_ms=0, clock=lambda: 0.0,
                clicker=lambda f: True, focus=lambda: True, state_file=None)
    case("nearest wins", t.pick([box, far], cx, cy)[0] == 0,
         "pick=%s" % t.pick([box, far], cx, cy)[0])

    say("")
    say("VERDICT: %s (%d failures) variable=qk_trigger offline"
        % ("PASS" if bad == 0 else "FAIL", bad))
    if logp:
        try:
            with open(logp, "w") as f:
                f.write("qk_trigger selftest %s\n" % time.strftime("%Y-%m-%d %H:%M:%S"))
                f.write("\n".join(lines) + "\n")
        except OSError:
            pass
    return 0 if bad == 0 else 1


def main():
    if "--selftest" in sys.argv:
        logp = os.path.join(TEMP, "qk_trigger_selftest.txt")
        rc = selftest(logp)
        out("log: %s" % logp)
        return rc

    t = Trigger(enabled=True, state_file=STATE_FILE, settings=SETTINGS)
    t.reload()
    out("qk_trigger standalone: hitbox=%s delay=%.0fms hold=%d key=%s — Ctrl+C stops"
        % (t.hitbox, t.delay_ms, t.hold, t.button))
    box = (860.0, 300.0, 1060.0, 800.0)
    try:
        while True:
            t.reload()
            t.feed([box], 960.0, 540.0)
            time.sleep(0.02)
    except KeyboardInterrupt:
        t._release()
        return 0


if __name__ == "__main__":
    sys.exit(main())



