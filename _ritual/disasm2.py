import struct, sys
sys.stdout = open(r"c:\Users\New User\OneDrive\Desktop\cheating\_ritual\_disasm2.txt", "w", encoding="utf-8")
path = r"C:\Windows\System32\drivers\gdrv3.sys"
data = open(path, "rb").read()
e = struct.unpack_from("<I", data, 0x3c)[0]
machine, nsec, tds, symptr, nsym, optsize, chars = struct.unpack_from("<HHIIIHH", data, e+4)
opt = e + 24
image_base = struct.unpack_from("<Q", data, opt+24)[0]
so = opt + optsize
secs = []
for i in range(nsec):
    nm, vs, va, rs, ra = struct.unpack_from("<8sIIII", data, so + i*40)
    nm = nm.rstrip(b"\0").decode("latin1")
    secs.append((nm, vs, va, rs, ra))
    print("sec %-8s va=0x%-6x vs=0x%-6x raw=0x%-6x rs=0x%x" % (nm, va, vs, ra, rs))

# import directory
imp_rva, imp_sz = struct.unpack_from("<II", data, opt + 120)  # data dir 1
print("import dir rva=0x%x sz=0x%x" % (imp_rva, imp_sz))
def rva2off(rva):
    for nm, vs, va, rs, ra in secs:
        if va <= rva < va + max(vs, rs):
            return ra + (rva - va)
    return None
iat = {}  # rva -> name
o = rva2off(imp_rva)
while True:
    oft, tds2, fwd, namerva, firstthunk = struct.unpack_from("<IIIII", data, o)
    if namerva == 0: break
    dn = data[rva2off(namerva):]
    dllname = dn[:dn.index(b"\0")].decode("latin1")
    thunk = rva2off(oft if oft else firstthunk)
    idx = 0
    while True:
        val = struct.unpack_from("<Q", data, thunk + idx*8)[0]
        if val == 0: break
        if val & (1 << 63):
            name = "ord#%d" % (val & 0xffff)
        else:
            fn = data[rva2off(val):]
            name = fn[2:fn.index(b"\0")].decode("latin1")
        iat[firstthunk + idx*8] = name + "!" + dllname.split(".")[0]
        idx += 1
    o += 20
print("IAT entries:", len(iat))

from capstone import Cs, CS_ARCH_X86, CS_MODE_64
md = Cs(CS_ARCH_X86, CS_MODE_64)
# find .text
tnm, tvs, tva, trs, tra = None, None, None, None, None
for nm, vs, va, rs, ra in secs:
    if nm == ".text":
        tnm, tvs, tva, trs, tra = nm, vs, va, rs, ra
code = data[tra:tra+trs]
ins_list = []
pos = 0
while pos < len(code):
    got = False
    for ins in md.disasm(code[pos:], tva + pos):
        ins_list.append(ins)
        pos = ins.address - tva + ins.size
        got = True
    if not got:
        pos += 1  # resync one byte on invalid data
print("instructions:", len(ins_list))
addr2ins = {}
for ins in ins_list:
    addr2ins[ins.address] = ins

def imp_call_targets(ins):
    # call/jmp qword ptr [rip + X]
    if ins.mnemonic in ("call", "jmp") and "rip" in ins.op_str and "qword ptr" in ins.op_str:
        try:
            disp = int(ins.op_str.split("rip +")[1].rstrip("]").strip() if "rip +" in ins.op_str else "-" + ins.op_str.split("rip -")[1].rstrip("]").strip(), 16) if False else None
        except Exception:
            disp = None
        import re
        m = re.search(r"rip ([+-]) (0x[0-9a-f]+|\d+)", ins.op_str)
        if m:
            d = int(m.group(2), 0)
            if m.group(1) == "-": d = -d
            tgt = ins.address + ins.size + d
            return tgt
    return None

callsites = {}
for ins in ins_list:
    if ins.mnemonic in ("call", "jmp"):
        t = imp_call_targets(ins)
        if t is not None and t in iat:
            callsites.setdefault(iat[t], []).append(ins.address)
print("=== import call sites ===")
for k in sorted(callsites):
    print("%-45s %s" % (k, " ".join("0x%x" % a for a in callsites[k])))

def dump_window(lo, hi, title):
    print("=== %s [0x%x..0x%x] ===" % (title, lo, hi))
    for ins in ins_list:
        if lo <= ins.address <= hi:
            ann = ""
            if ins.mnemonic in ("call", "jmp"):
                t = imp_call_targets(ins)
                if t is not None and t in iat:
                    ann = "  ; " + iat[t]
            print("%08x  %-8s %-46s%s" % (ins.address, ins.mnemonic, ins.op_str, ann))

dump_window(0x4a80, 0x4c40, "COPY LOOP around fault RIP 0x4b4a")
dump_window(0x3600, 0x3a80, "IOCTL DISPATCH (caller 0x37df)")
for k, sites in callsites.items():
    if "MmMap" in k or "MmUnmap" in k or "MapIoSpace" in k:
        for s in sites:
            dump_window(s - 0x100, s + 0x40, "around call to " + k)
