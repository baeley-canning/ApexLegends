"""p43n2 - read-only: literal substring census of the fresh progress dump."""
SRC = r'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p40d_livedump.txt'
OUT = r'C:\Users\New User\OneDrive\Desktop\cheating\temp\p43n2_census_out.txt'
raw = open(SRC, 'rb').read()
txt = raw.decode('utf-8', 'replace')
ls = txt.splitlines()
keys = ['== hit=', 'HEX ', 'rel=', 'walk', 'PRE ', 'no PE', 'VERDICT', 'cand ',
        'ram_top', 'eprocess']
census = ['bytes=%d lines=%d nul=%d crlf=%d' % (len(raw), len(ls),
                                                raw.count(b'\x00'), raw.count(b'\r\n'))]
for k in keys:
    census.append('%-10s count=%d' % (k, txt.count(k)))
first = [('%5d| %s' % (i + 1, l))[:150] for i, l in enumerate(ls)
         if 'hit=' in l][:6]
census += ['--- first hit= lines ---'] + first
open(OUT, 'w', encoding='utf-8').write('\n'.join(census) + '\n')
print('\n'.join(census))
