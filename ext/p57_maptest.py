# p57_maptest.py -- one PA list, one line per PA: OK/FAULT with errno. Read-only.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gio

PAS = [0x100000, 0x100000000, 0x140000000, 0x180000000, 0x200000000,
       0x300000000, 0x400000000, 0x500000000, 0x600000000, 0x700000000,
       0x7ff000000]
out = sys.argv[1] if len(sys.argv) > 1 else 'temp/p57_maptest.txt'
rows = []
try:
    g = gio.Gio()
except OSError as e:
    rows.append('FATAL %s' % e)
    g = None
if g:
    rows.append('ram_top=%#x' % g.ram_top)
    for pa in PAS:
        try:
            b = g.read_phys(pa, 16)
            rows.append('OK    %#011x %s' % (pa, b[:8].hex()))
        except OSError as e:
            rows.append('FAULT %#011x err=%s' % (pa, e.args[0]))
    del g
rows.append('END')
open(out, 'w', encoding='utf-8').write('\n'.join(rows) + '\n')
