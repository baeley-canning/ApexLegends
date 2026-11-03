import struct, hashlib
path = r"C:\Windows\System32\drivers\gdrv3.sys"
data = open(path, "rb").read()
print("gdrv3.sys bytes:", len(data))
print("sha256:", hashlib.sha256(data).hexdigest())
e = struct.unpack_from("<I", data, 0x3c)[0]
machine, nsec, tds, symptr, nsym, optsize, chars = struct.unpack_from("<HHIIIHH", data, e+4)
print("machine=0x%x nsec=%d optsz=%d" % (machine, nsec, optsize))
opt = e + 24
magic = struct.unpack_from("<H", data, opt)[0]
image_base = struct.unpack_from("<Q", data, opt+24)[0]
print("magic=0x%x image_base=0x%x" % (magic, image_base))
so = opt + optsize
secs = []
for i in range(nsec):
    nm, vs, va, rs, ra = struct.unpack_from("<8sIIII", data, so + i*40)
    nm = nm.rstrip(b"\0").decode("latin1")
    secs.append((nm, vs, va, rs, ra))
    print("sec %-8s va=0x%-6x vs=0x%-6x raw=0x%-6x rs=0x%x" % (nm, va, vs, ra, rs))
rva = 0x4b4a
off = None; secname = ""
for nm, vs, va, rs, ra in secs:
    if va <= rva < va + max(vs, rs):
        off = ra + (rva - va); secname = nm; break
print("RVA 0x%x -> file offset 0x%x (%s)" % (rva, off, secname))
print("raw bytes @rva:", " ".join("%02x" % b for b in data[off:off+16]))
try:
    from capstone import Cs, CS_ARCH_X86, CS_MODE_64
    md = Cs(CS_ARCH_X86, CS_MODE_64)
    for back in (0x18, 0x30, 0x60, 0xc0):
        start = rva - back
        print("--- window start 0x%x ---" % start)
        for ins in md.disasm(data[off-back:off+0x50], start):
            tag = ""
            if ins.address == rva: tag = "  <<<<<<< FAULT RIP (bugcheck gdrv3+0x4b4a)"
            print("%08x  %-8s %-40s%s" % (ins.address, ins.mnemonic, ins.op_str, tag))
            if ins.address > rva + 0x30: break
except ImportError as ex:
    print("capstone missing:", ex)
