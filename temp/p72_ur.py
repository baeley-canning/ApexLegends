import sys
sys.path.insert(0, "ext")
import dumplive as d

top, lo, hi = 0x800000000, 0x7CE000000, 0x7D000000
good, _ = d.ram_map()
bad = d.load_bad()
good = d._minus([(a, min(b, top)) for a, b in good if a < top], bad)
print("mid", good)
out = []
for a, b in good:
    a, b = max(a, lo), min(b, hi)
    a, b = (a + 0xFFF) & ~0xFFF, b & ~0xFFF
    print(hex(a), hex(b), b > a)
    if b > a:
        out.append((a, b))
print("out", out)
