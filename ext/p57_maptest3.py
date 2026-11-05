# p57_maptest3.py -- 1 GiB ladder, 1 page each. Read-only.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gio

out = sys.argv[1] if len(sys.argv) > 1 else 'temp/p57_maptest3.txt'
rows = []
g = gio.Gio()
ok = bad = 0
for gi in range(4, 36):
    pa = gi << 30
    if pa >= g.ram_top:
        break
    try:
        b = g.read_phys(pa, 16)
        ok += 1
        rows.append('OK    %#011x %s' % (pa, b[:8].hex()))
    except OSError as e:
        bad += 1
        rows.append('FAULT %#011x err=%s' % (pa, e.args[0]))
rows.append('ok=%d fault=%d' % (ok, bad))
rows.append('END')
open(out, 'w', encoding='utf-8').write('\n'.join(rows) + '\n')
