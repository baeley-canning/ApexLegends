r"""p98_ingest.py -- prove the health *ingest* path without touching Apex memory.

The memory sweeps (p88/p91/p96/p97) can bugcheck the host, so ingestion gets its own bench
that cannot: a synthetic feed and an OCR'd HUD, both into the same consumer.

Four scenarios, each with a stated expectation, because "it ran" is not a verdict:
  A clean synthetic   -> INGEST_OK
  B rendered HUD, OCR -> INGEST_OK and every digit must survive the round trip exactly
  C sabotaged feed    -> INGEST_REJECTED naming each injected fault
  D empty OCR text    -> parse returns None, no exception

Own output file per R5 (temp\_p98_ingest.txt), RESULT/VERDICT lines, non-zero exit on a miss.
Staged images go to C:\p37vm\ocr because Windows.Media.Ocr fails on OneDrive paths
(measured 11:13, OCRFAIL there, clean OCR from C:\p37vm).
"""
import os
import subprocess
import sys
import time
from datetime import datetime

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMP = os.path.join(REPO, 'temp')
sys.path.insert(0, os.path.join(REPO, 'ext'))

import health_consumer as hc   # noqa: E402
import health_feed as hf       # noqa: E402

OUT = os.path.join(TEMP, '_p98_ingest.txt')
OCRPS = os.path.join(REPO, '_ritual', 'ocr.ps1')
STAGE = r'C:\p37vm\ocr'
DELAY = 0.05

_lines = []


def L(s):
    _lines.append(s)
    print(s, flush=True)


def run_ocr(img, tag):
    out = os.path.join(STAGE, '_ocr_%s.txt' % tag)
    subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', OCRPS,
                    '-Path', img, '-Out', out], capture_output=True, text=True, errors='replace')
    try:
        with open(out, 'r', encoding='utf-8-sig', errors='replace') as f:
            return f.read()
    except OSError:
        return ''


def main():
    os.makedirs(STAGE, exist_ok=True)
    fails = []
    L('=== p98_ingest %s ===' % datetime.now().strftime('%Y-%m-%d %H:%M:%S'))

    # ---- A: clean synthetic feed -----------------------------------------
    recs = hf.gen(seed=7, t0=time.time())
    path = os.path.join(TEMP, '_p98_feed.jsonl')
    n = hf.write_jsonl(path, recs)
    rep = hc.consume(hf.read_jsonl(path))
    L('A synthetic: wrote=%d frames=%d entities=%d respawns=%d errors=%d anomalies=%d -> %s'
      % (n, rep['frames'], rep['entities'], rep['respawns'], rep['errors'], rep['anomalies'],
         rep['verdict']))
    for x in rep['anomaly_list']:
        L('  A| ' + x)
    if rep['verdict'] != 'INGEST_OK' or rep['frames'] != n:
        fails.append('A:%s frames=%d/%d' % (rep['verdict'], rep['frames'], n))
    L('RESULT A expect=INGEST_OK got=%s' % rep['verdict'])

    # ---- B: HUD -> OCR -> consumer ---------------------------------------
    frames = [(100, 100, False), (87, 50, False), (0, 0, True)]
    got = []
    for i, (hp, sh, dn) in enumerate(frames):
        img = os.path.join(STAGE, 'hud_%d.bmp' % i)
        hf.render_hud(img, hp, sh, downed=dn)
        time.sleep(DELAY)
        text = run_ocr(img, str(i))
        parsed, problems = hf.parse_ocr(text, time.time() + i * 0.2, i + 1)
        L('B frame %d drew hp=%d shield=%d downed=%d ocr=%r problems=%s parsed=%s'
          % (i, hp, sh, int(dn), text.strip().replace('\n', '|'), problems or '-',
             (parsed['hp'], parsed['shield'], parsed['state']) if parsed else None))
        if parsed is None:
            fails.append('B:frame%d no-parse' % i)
            continue
        if (parsed['hp'], parsed['shield'], parsed['state']) != (hp, sh, 'downed' if dn else 'alive'):
            fails.append('B:frame%d mismatch' % i)
        got.append(parsed)
    rep = hc.consume(got)
    L('B consumer: frames=%d errors=%d anomalies=%d -> %s'
      % (rep['frames'], rep['errors'], rep['anomalies'], rep['verdict']))
    for x in rep['error_list'] + rep['anomaly_list']:
        L('  B| ' + x)
    if rep['verdict'] != 'INGEST_OK' or rep['frames'] != len(frames):
        fails.append('B:%s frames=%d/%d' % (rep['verdict'], rep['frames'], len(frames)))
    L('RESULT B expect=INGEST_OK %d/%d frames exact_digits got=%s'
      % (rep['frames'], len(frames), rep['verdict']))

    # ---- C: sabotage, the consumer must not be a rubber stamp ------------
    bad = hf.gen(seed=8, t0=time.time())
    bad[3] = dict(bad[3], hp=140)                 # hp over max
    bad[6] = dict(bad[6], seq=bad[5]['seq'])      # seq regression
    bad[8] = dict(bad[8], shield=250)             # shield over max
    bad[10] = dict(bad[10], state='hovering')     # unknown state
    rep = hc.consume(bad)
    codes = sorted({e.split()[0] for e in rep['error_list']})
    L('C sabotage: frames=%d errors=%d -> %s codes=%s'
      % (rep['frames'], rep['errors'], rep['verdict'], codes))
    for x in rep['error_list']:
        L('  C| ' + x)
    want = ['hp:140', 'seq-not-increasing', 'shield:250', 'state:hovering']
    missing = [w for w in want if w not in codes]
    if rep['verdict'] != 'INGEST_REJECTED' or missing:
        fails.append('C:%s missing=%s' % (rep['verdict'], missing))
    L('RESULT C expect=INGEST_REJECTED 4/4 codes got=%d/%d %s'
      % (len(want) - len(missing), len(want), rep['verdict']))

    # ---- D: empty OCR frame ----------------------------------------------
    parsed, problems = hf.parse_ocr('', time.time(), 1)
    L('D empty ocr: parsed=%s problems=%s' % (parsed, problems))
    if parsed is not None or 'no-hp' not in problems:
        fails.append('D')

    L('RESULT fails=%d %s' % (len(fails), ','.join(fails) or 'none'))
    L('VERDICT: %s' % ('P98_INGEST_OK' if not fails else 'P98_INGEST_FAIL ' + ','.join(fails)))
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(_lines) + '\n')
    return 0 if not fails else 1


if __name__ == '__main__':
    sys.exit(main())
