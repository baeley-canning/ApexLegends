"""p43n5 - read-only: tail verdict block + everything about page 0x312861000."""
import re

SRC = r'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p40d_livedump.txt'
OUT = r'C:\Users\New User\OneDrive\Desktop\cheating\temp\p43n5_tail.txt'
ls = open(SRC, encoding='utf-8', errors='replace').read().splitlines()
tail = [('%5d| %s' % (i + 1, l))[:170] for i, l in enumerate(ls)
        if re.search(r'walk|VERDICT|eprocess|no PE|accept|score|MZ|ELAPSED', l)]
surv = [('%5d| %s' % (i + 1, l))[:170] for i, l in enumerate(ls)
        if '0x312861' in l or '0x3abe7' in l]
last = [('%5d| %s' % (len(ls) - 60 + i, l))[:170]
        for i, l in enumerate(ls[-61:])]
res = ['verdict-hits=%d survivor-hits=%d total=%d' % (len(tail), len(surv), len(ls)),
       '--- verdict lines ---'] + tail[-25:] + \
      ['--- survivor / dtb lines ---'] + surv[:25] + ['--- file tail 61 ---'] + last
open(OUT, 'w', encoding='utf-8').write('\n'.join(res) + '\n')
print('\n'.join(res[:2]))
