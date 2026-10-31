import struct, sys, math, collections

path = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
data = open(path, "rb").read()
print("size", len(data))

pe_off = struct.unpack_from("<I", data, 0x3C)[0]
print("e_lfanew", hex(pe_off), data[pe_off:pe_off+4])
machine, nsec = struct.unpack_from("<HH", data, pe_off + 4)
opt_size = struct.unpack_from("<H", data, pe_off + 20)[0]
opt_off = pe_off + 24
magic = struct.unpack_from("<H", data, opt_off)[0]
print("machine", hex(machine), "nsec", nsec, "optmagic", hex(magic))
image_base = struct.unpack_from("<Q", data, opt_off + 24)[0]
size_of_image = struct.unpack_from("<I", data, opt_off + 56)[0]
print("imagebase", hex(image_base), "sizeofimage", hex(size_of_image))

sec_off = opt_off + opt_size
secs = []
for i in range(nsec):
    o = sec_off + i * 40
    name = data[o:o+8].rstrip(b"\x00").decode("latin1")
    vsize, va, rawsize, rawptr = struct.unpack_from("<IIII", data, o + 8)
    chars = struct.unpack_from("<I", data, o + 36)[0]
    secs.append((name, va, vsize, rawptr, rawsize, chars))
    body = data[rawptr:rawptr+rawsize] if rawptr else b""
    ent = 0.0
    if body:
        cnt = collections.Counter(body)
        ent = -sum((c/len(body)) * math.log2(c/len(body)) for c in cnt.values())
    print(f"{name:9s} va={va:#010x} vsize={vsize:#09x} raw={rawptr:#09x} rawsize={rawsize:#09x} chars={chars:#010x} entropy={ent:.2f}")

def va_to_off(va):
    for name, sva, vsize, rawptr, rawsize, chars in secs:
        if sva <= va < sva + max(vsize, rawsize):
            return rawptr + (va - sva)
    return None

# look for tell-tale strings
for needle in [b"C_Player", b"C_BaseEntity", b"CGameEntitySystem", b"m_iHealth",
               b"ViewMatrix", b"view_matrix", b"LocalPlayer", b"local_player",
               b"CPlayer", b"WorldLayer", b".?AV"]:
    idx = data.find(needle)
    hits = 0
    pos = idx
    while pos != -1 and hits < 3:
        hits += 1
        pos = data.find(needle, pos + 1)
    print(f"string {needle!r}: first={idx if idx<0 else hex(va_to_off(0) or idx)} count>= {hits}")
