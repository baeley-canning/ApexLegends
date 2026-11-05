#!/usr/bin/env python3
# p88_refresh_sweep.py -- one process, two steps: refresh live targets (p85) and, only if
# that says TARGETS_OK, sweep the IOCTL shapes (p84) against them.
#
# Why this exists: the scheduled-task listener (ext\p64_arm.ps1) dies mid-job (task goes
# Ready, lastResult 0) roughly a minute in; the python child survives as an orphan, the
# nested powershell wrapper (temp\p86_chain.ps1) does not. So the chaining lives in python:
# subprocess-only, no nested shell. Verified 09:19 run: chain log froze 1 s in while p85
# kept scanning to PIDSCANEND.
#
# Read-only throughout: p85 only opens/closes the device, p84 only issues the map/translate/
# alloc ioctls. Own stamped log per R5; p84 result file is a fresh pNN slot, never overwritten
# in place (p84 writes _p84_ioctl_shapes.txt, archived here as _p88_p84_<stamp>.txt).
import os
import re
import subprocess
import sys
import time
from datetime import datetime

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMP = os.path.join(REPO, 'temp')
P85 = os.path.join(TEMP, 'p85_refresh.py')
P84 = os.path.join(TEMP, 'p84_ioctl_shapes.py')
LOG85 = os.path.join(TEMP, '_p85_refresh.txt')
TGT = os.path.join(TEMP, '_p85_targets.txt')
OUT84 = os.path.join(TEMP, '_p84_ioctl_shapes.txt')
CON85 = os.path.join(TEMP, 'p85_console.txt')
CON84 = os.path.join(TEMP, 'p84_console.txt')

STAMP = datetime.now().strftime('%Y%m%d_%H%M%S')
LOG = os.path.join(TEMP, '_p88_%s.txt' % STAMP)
LAST = os.path.join(TEMP, '_p88_last.txt')

_fh = open(LOG, 'w', encoding='utf-8', newline='\n')


def L(msg):
    line = '%s  %s' % (datetime.now().strftime('%H:%M:%S'), msg)
    print(line, flush=True)
    _fh.write(line + '\n')
    _fh.flush()


def read(path):
    try:
        with open(path, 'r', encoding='utf-8', errors='replace') as f:
            return f.read()
    except OSError:
        return ''


def keyed(text, key):
    m = re.search(r'^%s=(.*)$' % re.escape(key), text, re.M)
    return m.group(1).strip() if m else ''


def pid_alive(pid):
    r = subprocess.run(['tasklist', '/FI', 'PID eq %d' % pid, '/NH'],
                       capture_output=True, text=True, errors='replace')
    return str(pid) in (r.stdout or '')


def main():
    with open(LAST, 'w', encoding='utf-8') as f:
        f.write(LOG + '\n')
    L('=== p88_refresh_sweep %s ===' % STAMP)
    L('argv: python=%s' % sys.executable)

    for p in (LOG85, TGT, OUT84):
        try:
            os.remove(p)
        except OSError:
            pass

    L('step 1: p85_refresh')
    t0 = time.time()
    with open(CON85, 'w', encoding='utf-8', errors='replace') as con:
        r85 = subprocess.run([sys.executable, '-u', P85], cwd=REPO,
                             stdout=con, stderr=subprocess.STDOUT).returncode
    L('p85 rc=%d after %.1fs' % (r85, time.time() - t0))

    log85 = read(LOG85)
    verdict_line = ''
    for line in log85.splitlines():
        if line.startswith('VERDICT:'):
            verdict_line = line.strip()
    L('p85 verdict: %s' % (verdict_line or '<none>'))

    if 'TARGETS_OK' not in verdict_line:
        for line in log85.splitlines():
            if 'TARGET' in line or line.startswith('VERDICT:'):
                L('  p85| ' + line.strip())
        L('RESULT skipped p84: no live targets')
        L('VERDICT: P88_NO_TARGETS p85_rc=%d' % r85)
        return 4

    tgt = read(TGT)
    ctl, bad, pid = keyed(tgt, 'CTL'), keyed(tgt, 'BAD'), keyed(tgt, 'PID')
    state = keyed(tgt, 'BAD_STATE')
    L('targets pid=%s ctl=%s bad=%s (%s)' % (pid, ctl, bad, state))
    if not (ctl.startswith('0x') and bad.startswith('0x')):
        L('RESULT unparsable targets file')
        L('VERDICT: P88_BAD_TARGETS')
        return 5

    alive = pid_alive(int(pid)) if pid.isdigit() else False
    L('pid %s alive at step 2: %s' % (pid, alive))
    if not alive:
        L('WARNING pid died between steps; p84 still run, verdict marked STALE')

    L('step 2: p84_ioctl_shapes %s %s' % (ctl, bad))
    t1 = time.time()
    with open(CON84, 'w', encoding='utf-8', errors='replace') as con:
        r84 = subprocess.run([sys.executable, '-u', P84, ctl, bad], cwd=REPO,
                             stdout=con, stderr=subprocess.STDOUT).returncode
    L('p84 rc=%d after %.1fs' % (r84, time.time() - t1))

    out84 = read(OUT84)
    arch = os.path.join(TEMP, '_p88_p84_%s.txt' % STAMP)
    if out84:
        with open(arch, 'w', encoding='utf-8', newline='\n') as f:
            f.write(out84)
        L('p84 output archived: %s' % os.path.basename(arch))
    else:
        L('p84 wrote no output file')

    for line in out84.splitlines():
        if line.startswith(('RESULT', 'VERDICT', 'SHAPE', 'MAP', 'TRANS', 'ALLOC')):
            L('  p84| ' + line.strip())
    if con84_tail := read(CON84).strip().splitlines()[-6:]:
        for line in con84_tail:
            L('  con| ' + line.strip())

    v84 = ''
    for line in out84.splitlines():
        if line.startswith('VERDICT:'):
            v84 = line.strip()
    L('RESULT p85_rc=%d p84_rc=%d pid=%s alive=%s ctl=%s bad=%s'
      % (r85, r84, pid, alive, ctl, bad))
    L('VERDICT: %s%s' % ('P88_STALE_PID ' if not alive else 'P88_RAN ', v84 or '<p84 gave no verdict>'))
    return r84


if __name__ == '__main__':
    try:
        sys.exit(main())
    finally:
        _fh.close()
