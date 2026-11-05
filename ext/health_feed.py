r"""health_feed.py -- synthetic health feed for the ingest path, and the OCR twin of it.

Why this exists: the physical-memory sweep keeps bugchecking the host (AGENTS.md R1), and every
one of those crashes costs a reboot before any app code runs at all. But "does the app handle
health data" does not need Apex memory. It needs a *contract* and a *producer*. This module is
the producer - two of them:

  * syn  - a deterministic scenario generator (seeded), covering damage, shield break, down,
           revive, death, respawn, out-of-PVS and reappearance,
  * ocr  - the same records produced from the visible HUD instead of memory: a rendered HUD
           image is OCR'd with _ritual\ocr.ps1 and the digit lines are parsed back into records.

Both emit the identical JSONL contract, so one consumer tests both and a later real reader
(gio -> fields) can be swapped in without touching the consumer.

Contract, one JSON object per line, schema v1:
    ts     float   epoch seconds, producer clock
    seq    int     per-producer, strictly increasing from 1
    pid    int     source pid, 0 when unknown (ocr)
    ent    str     entity id ("local", "bot1".."botN")
    name   str     display name, may be empty
    team   int     team id, -1 when unknown
    hp     int     0..hp_max
    shield int     0..shield_max
    state  str     alive | downed | dead | gone
    src    str     syn | ocr

Read-only, stdlib only. BMP is written by hand so the module works without Pillow.
"""
import json
import os
import random
import subprocess

SCHEMA = 1
HP_MAX = 100
SHIELD_MAX = 100
STATES = ('alive', 'downed', 'dead', 'gone')

# 5x7 glyphs, one int per scanline, bit 4 = leftmost pixel. Enough for "HP 87" / "SHIELD 50".
_FONT = {
    '0': (0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E),
    '1': (0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E),
    '2': (0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F),
    '3': (0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E),
    '4': (0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02),
    '5': (0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E),
    '6': (0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E),
    '7': (0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08),
    '8': (0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E),
    '9': (0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C),
    'H': (0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11),
    'P': (0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10),
    'S': (0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E),
    'I': (0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E),
    'E': (0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F),
    'L': (0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F),
    'D': (0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E),
    ' ': (0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00),
}



def rec(ts, seq, ent, hp, shield, state, src='syn', pid=0, name='', team=-1):
    return {'ts': round(float(ts), 3), 'seq': int(seq), 'pid': int(pid), 'ent': ent,
            'name': name, 'team': int(team), 'hp': int(hp), 'shield': int(shield),
            'state': state, 'src': src}


def gen(seed=1, t0=0.0):
    """Deterministic scenario: 3 bots + local, full life-cycle, plus a PVS drop.

    Ordering matters - the consumer must see every transition the reader can really produce,
    including the ones a naive validation forgets (gone -> alive on re-entry).
    """
    rnd = random.Random(seed)
    out = []
    seq = 0
    t = t0

    def add(ent, hp, shield, state, team=-1, name='', dt=0.2):
        nonlocal seq, t
        seq += 1
        t += dt
        out.append(rec(t, seq, ent, max(0, hp), max(0, shield), state, team=team, name=name))

    add('local', 100, 100, 'alive', team=0, name='me')
    for i in range(1, 4):
        add('bot%d' % i, 100, rnd.choice([0, 25, 50]), 'alive', team=1, name='bot%d' % i)

    add('bot1', 100, 0, 'alive', team=1, name='bot1')          # shield break
    add('bot1', 70, 0, 'alive', team=1, name='bot1')
    add('bot1', 20, 0, 'alive', team=1, name='bot1')
    add('bot1', 0, 0, 'downed', team=1, name='bot1')           # knocked
    add('bot1', 100, 50, 'alive', team=1, name='bot1')         # revived + shield cell
    add('bot2', 45, 0, 'alive', team=1, name='bot2')
    add('bot2', 0, 0, 'downed', team=1, name='bot2')
    add('bot2', 0, 0, 'dead', team=1, name='bot2')             # finished
    add('bot3', 30, 0, 'alive', team=1, name='bot3')
    add('bot3', 0, 0, 'gone')                                  # left the PVS mid-fight
    add('local', 85, 100, 'alive', team=0, name='me')          # local took chip damage
    add('local', 60, 75, 'alive', team=0, name='me')           # shield cracked
    add('bot3', 30, 0, 'alive', team=1, name='bot3')           # re-entered the PVS
    add('local', 100, 75, 'alive', team=0, name='me')          # healed at a cell
    return out


def write_jsonl(path, records):
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        for r in records:
            f.write(json.dumps(r, sort_keys=True) + '\n')
    return len(records)


def read_jsonl(path):
    out = []
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out


def _bmp(width, height, bg=(18, 22, 26)):
    """24-bit bottom-up BMP bytearray + row stride. No Pillow."""
    row = (width * 3 + 3) & ~3
    size = row * height
    hdr = bytearray(b'BM' + (54 + size).to_bytes(4, 'little') + b'\0\0\0\0' + (54).to_bytes(4, 'little'))
    hdr += (40).to_bytes(4, 'little') + width.to_bytes(4, 'little') + height.to_bytes(4, 'little')
    hdr += (1).to_bytes(2, 'little') + (24).to_bytes(2, 'little') + (0).to_bytes(4, 'little')
    hdr += size.to_bytes(4, 'little') + (2835).to_bytes(4, 'little') + (2835).to_bytes(4, 'little')
    hdr += (0).to_bytes(4, 'little') + (0).to_bytes(4, 'little')
    px = bytearray(row * height)
    for y in range(height):
        base = y * row
        for x in range(width):
            px[base + x * 3] = bg[2]
            px[base + x * 3 + 1] = bg[1]
            px[base + x * 3 + 2] = bg[0]
    return hdr, px, row, height


def _text(px, row, height, x0, y0, s, scale=8, fg=(235, 235, 235)):
    cx = x0
    for ch in s:
        g = _FONT.get(ch, _FONT[' '])
        for gy, bits in enumerate(g):
            for gx in range(5):
                if bits & (1 << (4 - gx)):
                    for sy in range(scale):
                        y = y0 + gy * scale + sy
                        base = (height - 1 - y) * row
                        for sx in range(scale):
                            o = base + (cx + gx * scale + sx) * 3
                            px[o] = fg[2]
                            px[o + 1] = fg[1]
                            px[o + 2] = fg[0]
        cx += 6 * scale


def render_hud(path, hp, shield, downed=False, width=900, height=230):
    """Draw one HUD frame: GDI+ text via _ritual\\hud_mock.ps1, BMP fallback if PS is missing.

    Stand-in for the game window. Same shape as a real capture from _ritual\\shot_full.ps1, so
    swapping in a screenshot region later changes nothing downstream. A real font beats the
    built-in glyphs: measured 11:20, Windows OCR read "HP 87 / SHIELD 50" from Consolas 56 and
    returned only "SHIELD IØØ" from the 5x7 blocks at 8x.
    """
    ps = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      '_ritual', 'hud_mock.ps1')
    if os.path.isfile(ps):
        r = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ps,
                            '-Hp', str(hp), '-Shield', str(shield), '-Down', str(int(bool(downed))),
                            '-Out', path, '-W', str(width), '-H', str(height)],
                           capture_output=True, text=True, errors='replace')
        if os.path.isfile(path) and os.path.getsize(path) > 0:
            return path
        raise OSError('hud_mock failed rc=%d %s' % (r.returncode, (r.stdout or '')[-200:]))
    return _render_bmp(path, hp, shield, downed, width, height)


def _render_bmp(path, hp, shield, downed=False, width=760, height=230):
    hdr, px, row, h = _bmp(width, height)
    _text(px, row, h, 30, 30, 'HP %d' % hp)
    _text(px, row, h, 30, 110, 'SHIELD %d' % shield, fg=(150, 210, 255))
    if downed:
        _text(px, row, h, 470, 30, 'DOWN', fg=(255, 190, 90))
    with open(path, 'wb') as f:
        f.write(bytes(hdr))
        f.write(bytes(px))
    return path


def parse_ocr(text, ts, seq, pid=0):
    """Turn one OCR'd HUD frame into one record. Reports what it could not read.

    Digits only, plus the confusions the engine actually produces. Measured 11:21: Consolas is
    read as "lee" (slashed zero), Arial 64 as "IOO" (letter I/O), so both are normalised here.
    'DOWN' anywhere marks the frame downed: a knocked HUD stops showing a readable number.
    """
    import re
    problems = []
    hp = shield = None

    def num(tok):
        return int(tok.replace('O', '0').replace('o', '0').replace('Ø', '0').replace('ø', '0')
                   .replace('I', '1').replace('l', '1').replace('|', '1')
                   .replace('L', '1').replace('E', '0'))

    for line in text.splitlines():
        up = line.upper()
        # separator class must exclude alphanumerics, else \D eats the L of "LOO"
        if hp is None:
            m = re.search(r'\bHP[^0-9A-Z]{0,3}([0-9OØILE|]{1,3})\b', up)
            if m:
                hp = num(m.group(1))
        if shield is None:
            m = re.search(r'\b(?:SHIELD|SH)[^0-9A-Z]{0,3}([0-9OØILE|]{1,3})\b', up)
            if m:
                shield = num(m.group(1))
    downed = bool(re.search(r'\bDOW', text.upper()))
    if downed and hp is None:
        hp = 0                     # a knocked HUD is 0 hp by definition, number or not
    if hp is None and not downed:
        problems.append('no-hp')
    if shield is None:
        problems.append('no-shield')
    if hp is not None and hp > HP_MAX:
        problems.append('hp-over-max')
    if shield is not None and shield > SHIELD_MAX:
        problems.append('shield-over-max')
    if hp is None and shield is None:
        return None, problems
    return rec(ts, seq, 'local', hp if hp is not None else 0,
               shield if shield is not None else 0,
               'downed' if downed else 'alive', src='ocr', pid=pid), problems

