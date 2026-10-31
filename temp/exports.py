"""Parse the on-disk r5apex_dx12.exe: exports + interesting interface/netvar strings."""
import struct

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
data = open(PATH, "rb").read()

pe = struct.unpack_from("<I", data, 0x3C)[0]
nsec = struct.unpack_from("<H", data, pe + 6)[0]
opt_size = struct.unpack_from("<H", data, pe + 20)[0]
opt = pe + 24
image_base = struct.unpack_from("<Q", data, opt + 24)[0]

# data directories: export table is index 0
dd_off = opt + 112
export_rva, export_size = struct.unpack_from("<II", data, dd_off + 0)

sec_off = opt + opt_size
secs = []
for i in range(nsec):
    o = sec_off + i * 40
    vsize, va, rawsize, rawptr = struct.unpack_from("<IIII", data, o + 8)
    secs.append((va, vsize, rawptr, rawsize))


def rva2off(rva):
    for va, vsize, rawptr, rawsize in secs:
        if va <= rva < va + max(vsize, rawsize):
            return rawptr + (rva - va)
    return None


print("export_rva=%#x size=%#x" % (export_rva, export_size))
if export_rva:
    eo = rva2off(export_rva)
    (nfunc, nnames, afunc, anames, aords) = struct.unpack_from("<IIIII", data, eo + 20)
    print("num funcs=%d names=%d" % (nfunc, nnames))
    names = []
    for i in range(nnames):
        name_rva = struct.unpack_from("<I", data, rva2off(anames) + i * 4)[0]
        ordv = struct.unpack_from("<H", data, rva2off(aords) + i * 2)[0]
        func_rva = struct.unpack_from("<I", data, rva2off(afunc) + ordv * 4)[0]
        nm = data[rva2off(name_rva):data.find(b"\x00", rva2off(name_rva))].decode("latin1")
        names.append((nm, func_rva))
    print("--- exports ---")
    for nm, frva in names:
        print("%-48s rva=%#010x" % (nm, frva))

print("--- interface / netvar strings ---")
for needle in [b"CreateInterface", b"VClientEntityList", b"VEngineClient", b"VClient0",
               b"VEngineTrace", b"VGUI_System", b"DT_BaseEntity", b"DT_Player",
               b"DT_BasePlayer", b"m_vecAbsOrigin", b"m_iTeamNum", b"m_lifeState",
               b"CClientEntityList", b"CGameEntitySystem", b"m_currentFrame",
               b"s_pInterfaceRegs", b"Source2Client", b"m_angEyeAngles"]:
    pos = data.find(needle)
    if pos < 0:
        print("%-22s MISSING" % needle.decode())
        continue
    # report rva of first hit
    rva = None
    for va, vsize, rawptr, rawsize in secs:
        if rawptr <= pos < rawptr + rawsize:
            rva = va + (pos - rawptr)
    print("%-22s first_off=%#x rva=%s" % (needle.decode(), pos,
                                          "?" if rva is None else hex(rva)))
