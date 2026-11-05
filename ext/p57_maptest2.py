# p57_maptest2.py -- stickiness + size dependence. Read-only.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gio

PAS = [0x600000000, 0x600001000, 0x601000000, 0x608000000, 0x610000000,
       0x620000000, 0x628000000, 0x630000000, 0x140000000, 0x140001000]
out = sys.argv[1] if len(sys.argv) > 1 else 'temp/p57_maptest2.txt'
rows = []
g = gio.Gio()
rows.append('ram_top=%#x' % g.ram_top)
for pa in PAS:
    line = '%#011x' % pa
    for attempt in range(1, 4):
        try:
            g.read_phys(pa, 16)
            line += ' try%d=OK' % attempt
        except OSError as e:
            line += ' try%d=%s' % (attempt, e.args[0])
    for sz in (4, 0x1000):
        try:
            g.read_phys(pa, sz)
            line += ' sz%d=OK' % sz
        except OSError as e:
            line += ' sz%d=%s' % (sz, e.args[0])
    rows.append(line)
rows.append('END')
open(out, 'w', encoding='utf-8').write('\n'.join(rows) + '\n')
