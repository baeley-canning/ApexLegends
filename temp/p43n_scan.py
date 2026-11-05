"""p43n - read-only: shape of the fresh dump + every non-hex-row line."""
import re

SRC = r'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p40d_progress.txt'
OUT = r'C:\Users\New User\OneDrive\Desktop\cheating\temp\p43n_scan.txt'

ls = open(SRC, encoding='utf-8', errors='replace').read().splitlines()
ROW = re.compile(r'^\s+0x[0-9a-f]+ rel=')
HEAD = re.compile(r'^\s+(== hit=|HEX )')
other = [(i + 1, l) for i, l in enumerate(ls) if not ROW.match(l)
         and not HEAD.match(l)]
hits = [l for l in ls if l.startswith('  == hit=')]
head = ['%5d| %s' % (i, l) for i, l in other[:40]]
tail = ['%5d| %s' % p for p in other[-40:]]
res = ['lines=%d non-row=%d hit-blocks=%d' % (len(ls), len(other), len(hits)),
       '--- first 40 non-row ---'] + head + ['--- last 40 non-row ---'] + tail
open(OUT, 'w', encoding='utf-8').write('\n'.join(res) + '\n')
print('\n'.join(res[:2]))
