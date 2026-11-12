import sys
sys.path.insert(0, r"C:\Users\New User\OneDrive\Desktop\cheating\ext")
import gio

# The game's PML4/base from the 22:06 session (pid 20268, now dead - the frames may
# be reused, but a read either succeeds or returns 1450, which is the question).
pa_list = [
    0x34C9EE000,   # the game's PML4 (driver DTB from 22:06)
    0x34C9EE000 - 0x1000,
    0x34C9EE000 + 0x1000,
    0x31D3F6000,   # a frame gdrv3 already refused earlier tonight
    0x100000,      # known-good control
]
with gio.Gio() as g:
    print("ram_top=%#x" % g.ram_top)
    for pa in pa_list:
        try:
            b = g.read_phys(pa, 16)
            print("%#012x OK   %s" % (pa, b.hex()))
        except OSError as e:
            print("%#012x FAIL %s" % (pa, e))

