# p57_maps.py -- print the declared RAM map (no device needed). Read-only.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dumplive as dl

out = sys.argv[1] if len(sys.argv) > 1 else 'temp/p57_maps.txt'
rows = []
r, note = dl.ram_map()
rows.append('note=%s n=%d' % (note, len(r)))
tot = 0
for lo, hi in sorted(r):
    tot += hi - lo
    rows.append('%#012x-%#012x %8.1f MiB' % (lo, hi, (hi - lo) / 1048576.0))
rows.append('total=%.1f GiB' % (tot / 1073741824.0))
rows.append('END')
open(out, 'w', encoding='utf-8').write('\n'.join(rows) + '\n')
