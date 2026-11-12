"""Refusal pattern: 64 pages each side of the DTB frame, plus RAM facts."""
import sys
sys.path.insert(0, "..\\ext")
import gio

g = gio.Gio(chunk=0x1000)
print("ram_top=%#x installed=%#x" % (g.ram_top, gio.installed_ram_bytes()))
row = []
for k in range(-64, 65):
    pa = 0x33bcb0000 + k * 0x1000
    try:
        g.read_phys(pa, 0x1000)
        row.append(".")
    except OSError:
        row.append("X")
print("k=-64..64 (X=refused):")
print("".join(row))
print("refused:", sum(1 for c in row if c == "X"), "of", len(row))
