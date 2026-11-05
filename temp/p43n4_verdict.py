"""p43n4 - read-only: verdict region + survivor context of the fresh dump."""
import re

SRC = r'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p40d_livedump.txt'
OUT = r'C:\Users\New User\OneDrive\Desktop\cheating\temp\p43n4_verdict.txt'
ls = open(SRC, encoding='utf-8', errors='replace').read().splitlines()
pat = re.compile(r'PRE |walk|VERDICT|no PE|eprocess|gate|MASK|param|dtb=|elapsed')
keep = [('%5d| %s' % (i + 1, l))[:160] for i, l in enumerate(ls) if pat.search(l)]
# every candidate line, truncated: which delta/type/dtb and accept/reject
cand = [('%5d| %s' % (i + 1, l))[:160] for i, l in enumerate(ls)
        if l.startswith('  cand ')]
res = ['lines=%d verdict-lines=%d cand-lines=%d' % (len(ls), len(keep), len(cand)),
       '--- verdict/gate region ---'] + keep[:40] + \
      ['--- candidate deltas (first 60) ---'] + cand[:60]
open(OUT, 'w', encoding='utf-8').write('\n'.join(res) + '\n')
print('\n'.join(res[:2]))
